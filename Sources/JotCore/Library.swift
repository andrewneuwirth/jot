import Foundation
import Combine
import AVFoundation

public enum JotPaths {
    public static let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Jot")
    public static let models = root.appendingPathComponent("Models")
    public static let recordings = root.appendingPathComponent("Recordings")
    public static func prepare() throws {
        for path in [root, models, recordings] { try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true) }
    }
}
public struct Note: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var title = "Untitled note"
    public var body = ""
    public var folder = "Personal"
    public var pinned = false
    public var updated = Date()
    public init(title: String = "Untitled note", body: String = "", folder: String = "Personal") { self.title = title; self.body = body; self.folder = folder }
}
public struct Dictation: Codable, Identifiable {
    public var id = UUID()
    public var date = Date()
    public var text: String
    public var originalText: String?
    public var cleanupMS: Double?
    public var cleanupStatus: String?
    public var audioFile: String?
    public var duration: Double
    public var finishMS: Double
    public var model: String
    public var destination: String
    public var status: String
    public init(text: String, audioFile: String?, duration: Double, finishMS: Double, model: String, destination: String, status: String) {
        self.text = text; self.audioFile = audioFile; self.duration = duration; self.finishMS = finishMS; self.model = model; self.destination = destination; self.status = status
    }
}
public struct Benchmark: Codable, Identifiable {
    public var id = UUID()
    public var date = Date()
    public var model: String
    public var source: String
    public var audioSeconds: Double
    public var processingSeconds: Double
    public var finalizationMS: Double
    public var transcript: String
    public var reference: String?
    public var wordErrorRate: Double?
    public var hardware: String
    public var speed: Double { audioSeconds / max(processingSeconds, 0.0001) }
}
struct Archive: Codable {
    var notes: [Note] = []
    var history: [Dictation] = []
    var benchmarks: [Benchmark] = []
    var folders: [String] = ["Personal", "Projects", "Study"]
    var vocabulary = ""
}
@MainActor public final class Library: ObservableObject {
    @Published public var notes: [Note] = []
    @Published public var history: [Dictation] = []
    @Published public var benchmarks: [Benchmark] = []
    @Published public var folders = ["Personal", "Projects", "Study"]
    @Published public var vocabulary = ""
    @Published public var error: String?
    private let url: URL
    public init(root: URL = JotPaths.root) {
        url = root.appendingPathComponent("library.json")
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: url.path) {
                let a = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: url))
                notes = a.notes; history = a.history; benchmarks = a.benchmarks; folders = a.folders; vocabulary = a.vocabulary
            }
        } catch { self.error = "Could not load your library: \(error.localizedDescription). Original file has been preserved." }
    }
    /// Files left behind by an interrupted process remain discoverable after relaunch.
    public func recoverInterruptedRecordings() {
        guard error == nil else { return }
        let directory = url.deletingLastPathComponent().appendingPathComponent("Recordings")
        let known = Set(history.compactMap(\.audioFile))
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "caf" && !known.contains(file.lastPathComponent) {
            guard let audio = try? AVAudioFile(forReading: file), audio.length > 0 else { continue }
            history.insert(Dictation(text: "", audioFile: file.lastPathComponent, duration: Double(audio.length) / audio.processingFormat.sampleRate, finishMS: 0, model: "Interrupted recording", destination: "History", status: "Interrupted · retry available"), at: 0)
        }
        if history.count > known.count { save() }
    }
    public func save() {
        // Never overwrite an unreadable library with an empty one.
        guard error == nil else { return }
        do {
            let a = Archive(notes: notes, history: history, benchmarks: benchmarks, folders: folders, vocabulary: vocabulary)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(a).write(to: url, options: .atomic)
        } catch { self.error = "Could not save: \(error.localizedDescription)" }
    }
    @discardableResult public func addNote(body: String = "", title: String = "Untitled note") -> UUID {
        let note = Note(title: title, body: body); notes.insert(note, at: 0); save(); return note.id
    }
    public func add(_ entry: Dictation) { history.insert(entry, at: 0); save() }
    public func add(_ entry: Benchmark) { benchmarks.insert(entry, at: 0); save() }
    public func removeHistory(_ id: UUID) {
        if let entry = history.first(where: { $0.id == id }), let file = entry.audioFile, !history.contains(where: { $0.id != id && $0.audioFile == file }) {
            try? FileManager.default.trashItem(at: JotPaths.recordings.appendingPathComponent(file), resultingItemURL: nil)
        }
        history.removeAll { $0.id == id }; save()
    }
}
public enum TranscriptTools {
    public static func normalize(_ text: String) -> [String] {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }
    public static func wordErrorRate(reference: String, hypothesis: String) -> Double {
        let a = normalize(reference), b = normalize(hypothesis)
        guard !a.isEmpty else { return b.isEmpty ? 0 : 1 }
        var row = Array(0...b.count)
        for (i, word) in a.enumerated() {
            var next = [i + 1] + Array(repeating: 0, count: b.count)
            for j in b.indices { next[j+1] = min(next[j]+1, row[j+1]+1, row[j] + (word == b[j] ? 0 : 1)) }
            row = next
        }
        return Double(row[b.count]) / Double(a.count)
    }
    /// Explicit alias rules only: spoken phrase = desired spelling. No silent rewriting.
    public static func applyVocabulary(_ text: String, rules: String) -> String {
        var result = text
        for line in rules.split(separator: "\n") {
            let pair = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard pair.count == 2, !pair[0].isEmpty, !pair[1].isEmpty,
                  let regex = try? NSRegularExpression(pattern: "(?i)(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: pair[0]) + "(?![\\p{L}\\p{N}])") else { continue }
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: NSRegularExpression.escapedTemplate(for: pair[1]))
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
