import XCTest
import AVFoundation
@testable import JotCore

final class JotTests: XCTestCase {
    func testVocabularyOnlyReplacesWholePhrasesAndEscapesTemplates() {
        XCTAssertEqual(TranscriptTools.applyVocabulary("tar's and stars cost ten bucks.", rules: "tar's = Tars\nten bucks = $10"), "Tars and stars cost $10.")
        XCTAssertEqual(TranscriptTools.applyVocabulary("Cartography", rules: "art = Art"), "Cartography")
    }
    func testWordErrorRateUsesEditDistanceAndIgnoresPunctuation() {
        XCTAssertEqual(TranscriptTools.wordErrorRate(reference: "Hello, world!", hypothesis: "hello world"), 0)
        XCTAssertEqual(TranscriptTools.wordErrorRate(reference: "keep the last word", hypothesis: "keep the last"), 0.25)
        XCTAssertEqual(TranscriptTools.wordErrorRate(reference: "one two", hypothesis: "one three two"), 0.5)
    }
    @MainActor func testLibrarySurvivesRelaunchAndKeepsHistory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = Library(root: root)
        let id = library.addNote(body: "A thought worth keeping", title: "Test")
        library.vocabulary = "jot = Jot"; library.save()
        library.add(Dictation(text: "Final words", audioFile: "recovery.caf", duration: 2.1, finishMS: 210, model: "test", destination: "TextEdit", status: "Inserted"))
        let reopened = Library(root: root)
        XCTAssertEqual(reopened.notes.first?.id, id)
        XCTAssertEqual(reopened.notes.first?.body, "A thought worth keeping")
        XCTAssertEqual(reopened.history.first?.audioFile, "recovery.caf")
        XCTAssertEqual(reopened.vocabulary, "jot = Jot")
    }
    @MainActor func testUnreadableLibraryIsNeverOverwritten() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("library.json")
        try Data("broken original".utf8).write(to: file)
        let library = Library(root: root)
        XCTAssertNotNil(library.error)
        library.addNote(body: "Do not overwrite")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "broken original")
    }
    @MainActor func testInterruptedAudioIsRecoveredOnlyOnce() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let recordings = root.appendingPathComponent("Recordings")
        try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1600)!
        buffer.frameLength = 1600
        do {
            let file = try AVAudioFile(forWriting: recordings.appendingPathComponent("interrupted.caf"), settings: format.settings)
            try file.write(from: buffer)
        }
        let library = Library(root: root)
        library.recoverInterruptedRecordings()
        XCTAssertEqual(library.history.count, 1)
        XCTAssertEqual(library.history.first?.duration ?? 0, 0.1, accuracy: 0.001)
        let reopened = Library(root: root)
        reopened.recoverInterruptedRecordings()
        XCTAssertEqual(reopened.history.count, 1)
        XCTAssertEqual(reopened.history.first?.audioFile, "interrupted.caf")
    }

}
