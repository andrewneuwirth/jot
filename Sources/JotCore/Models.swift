import Foundation
import FluidAudio

/// One speech-to-text option on the Models page. Jot runs every one of them on this Mac.
public struct SpeechModel: Identifiable, Sendable {
    public let id: String
    /// nil for Apple's built-in speech, which macOS installs and updates itself.
    public let mode: SpeechMode?
    public let name: String
    public let maker: String
    public let summary: String
    public let languages: String
    /// Published size of the files Jot downloads; the download must reach most of it to count as complete.
    public let bytes: Int64
    public let speed: Int       // 1–5
    public let accuracy: Int    // 1–5
    public let badge: String?
    public let source: URL
    public let symbol: String
    public let hue: Double
}

public enum SpeechCatalog {
    /// Sizes from the Hugging Face file listings of each repository (the compiled Core ML files Jot fetches).
    public static let all: [SpeechModel] = [
        SpeechModel(id: "parakeet-ultra", mode: .ultra, name: "Parakeet Ultra", maker: "NVIDIA · FluidInference",
                    summary: "The most accurate English model. Apple shows words live; Ultra writes the final text when you stop.",
                    languages: "English", bytes: 632_000_000, speed: 4, accuracy: 5, badge: "Recommended",
                    source: URL(string: "https://huggingface.co/FluidInference/parakeet-ultra-coreml")!, symbol: "bird.fill", hue: 0.60),
        SpeechModel(id: "parakeet-v3", mode: .multilingual, name: "Parakeet v3", maker: "NVIDIA · FluidInference",
                    summary: "Final text in 25 European languages, detected automatically. The live preview stays English.",
                    languages: "25 languages", bytes: 483_000_000, speed: 4, accuracy: 4, badge: "Multilingual",
                    source: URL(string: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml")!, symbol: "globe", hue: 0.47),
        SpeechModel(id: "parakeet-eou-160", mode: .fast, name: "Parakeet Realtime", maker: "NVIDIA · FluidInference",
                    summary: "A small streaming model that types as you talk, in 160 ms steps. Fastest, a little less accurate.",
                    languages: "English", bytes: 225_000_000, speed: 5, accuracy: 3, badge: "Fastest",
                    source: URL(string: "https://huggingface.co/FluidInference/parakeet-realtime-eou-120m-coreml")!, symbol: "bolt.fill", hue: 0.08),
        SpeechModel(id: "parakeet-eou-320", mode: .balanced, name: "Parakeet Realtime · 320 ms", maker: "NVIDIA · FluidInference",
                    summary: "The same streaming model with more context per step: steadier words, slightly later.",
                    languages: "English", bytes: 224_000_000, speed: 4, accuracy: 3, badge: nil,
                    source: URL(string: "https://huggingface.co/FluidInference/parakeet-realtime-eou-120m-coreml")!, symbol: "gauge.with.dots.needle.67percent", hue: 0.11),
        SpeechModel(id: "apple-speech", mode: nil, name: "Apple Speech", maker: "Built into macOS",
                    summary: "Live words while you dictate, and the transcript for class and call recordings. macOS downloads it.",
                    languages: "English", bytes: 0, speed: 5, accuracy: 3, badge: "Built in",
                    source: URL(string: "https://developer.apple.com/documentation/speech/speechanalyzer")!, symbol: "apple.logo", hue: 0),
    ]

    public static func model(for mode: SpeechMode) -> SpeechModel { all.first { $0.mode == mode }! }

    /// Where FluidAudio keeps each model under ~/Library/Application Support/Jot/Models (its own folder names).
    public static func folder(_ mode: SpeechMode, root: URL = JotPaths.models) -> URL {
        switch mode {
        case .ultra: root.appendingPathComponent("parakeet-ultra")
        case .multilingual: root.appendingPathComponent("parakeet-tdt-0.6b-v3")
        case .fast: root.appendingPathComponent("parakeet-eou-streaming/160ms")
        case .balanced: root.appendingPathComponent("parakeet-eou-streaming/320ms")
        }
    }
}

/// How models are fetched and recognised. The real one asks FluidAudio, which downloads from Hugging Face; the
/// self-check swaps in a fake that writes a small file, so nothing large is ever downloaded in a test.
public struct ModelBackend: Sendable {
    public var fetch: @Sendable (SpeechMode, URL, @escaping @Sendable (Double) -> Void) async throws -> Void
    public var present: @Sendable (SpeechMode, URL) -> Bool

    public static let fluidAudio = ModelBackend(
        fetch: { mode, folder, progress in
            let report: ProgressHandler = { progress($0.fractionCompleted) }
            if mode.isBatch {
                try await AsrModels.download(to: folder, version: mode.asrVersion, progressHandler: report)
            } else {
                // The models root; FluidAudio adds parakeet-eou-streaming/<chunk> itself.
                let root = folder.deletingLastPathComponent().deletingLastPathComponent()
                try await ModelHub.download(mode == .fast ? .parakeetEou160 : .parakeetEou320, to: root, progressHandler: report)
            }
        },
        present: { mode, folder in
            if mode.isBatch { return AsrModels.modelsExist(at: folder, version: mode.asrVersion) }
            return ModelNames.ParakeetEOU.requiredModels.allSatisfy { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
        })
}

@MainActor public final class ModelStore: ObservableObject {
    public enum State: Equatable { case builtIn, absent, downloading(Double), ready }

    @Published public private(set) var progress: [String: Double] = [:]
    @Published public private(set) var ready: Set<String> = []
    @Published public var errors: [String: String] = [:]
    /// The built-in cleanup model (one file, CleanupModel): download progress, nil when idle.
    @Published public private(set) var cleanupProgress: Double?
    @Published public private(set) var cleanupReady = false
    @Published public var cleanupError: String?
    private var cleanupTask: Task<Void, Never>?
    public let catalog: [SpeechModel]
    let root: URL
    let backend: ModelBackend
    private var tasks: [String: Task<Void, Never>] = [:]

    public init(root: URL = JotPaths.models, catalog: [SpeechModel] = SpeechCatalog.all, backend: ModelBackend = .fluidAudio) {
        self.root = root; self.catalog = catalog; self.backend = backend
        refresh()
    }

    public func state(_ m: SpeechModel) -> State {
        guard m.mode != nil else { return .builtIn }
        if let p = progress[m.id] { return .downloading(p) }
        return ready.contains(m.id) ? .ready : .absent
    }
    public func isReady(_ mode: SpeechMode) -> Bool { catalog.first { $0.mode == mode }.map { state($0) == .ready } ?? false }
    public func folder(_ m: SpeechModel) -> URL? { m.mode.map { SpeechCatalog.folder($0, root: root) } }

    public func refresh() {
        ready = Set(catalog.filter { m in folder(m).map { complete(m, $0) } ?? false }.map(\.id))
        cleanupReady = CleanupModel.isPresent(root: root)
    }

    /// Downloads the cleanup model to a temporary file, checks its SHA-256 against the published one, then moves it in.
    public func downloadCleanup(then done: (@MainActor () -> Void)? = nil) {
        guard cleanupTask == nil else { return }
        cleanupError = nil; cleanupProgress = 0
        let target = CleanupModel.file(root: root)
        cleanupTask = Task { [weak self] in
            do {
                let file = try await FileDownload.fetch(CleanupModel.url) { p in Task { @MainActor in if self?.cleanupProgress != nil { self?.cleanupProgress = p } } }
                defer { try? FileManager.default.removeItem(at: file) }
                let hash = try await Task.detached { try CleanupModel.sha256(of: file) }.value
                guard hash == CleanupModel.sha256 else { throw URLError(.cannotDecodeContentData, userInfo: [NSLocalizedDescriptionKey: "The download didn't match its published checksum. Try again."]) }
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.moveItem(at: file, to: target)
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled { self?.cleanupError = error.localizedDescription }
            }
            guard let self, !Task.isCancelled else { return }
            self.cleanupTask = nil; self.cleanupProgress = nil; self.refresh()
            if self.cleanupReady { done?() }
        }
    }
    public func cancelCleanup() { cleanupTask?.cancel(); cleanupTask = nil; cleanupProgress = nil }
    public func deleteCleanup() {
        cancelCleanup()
        try? FileManager.default.trashItem(at: CleanupModel.file(root: root), resultingItemURL: nil)
        refresh()
    }

    /// Present by name and close to the published size: a half-finished or truncated download doesn't count.
    func complete(_ m: SpeechModel, _ folder: URL) -> Bool {
        guard let mode = m.mode, backend.present(mode, folder) else { return false }
        return Double(Self.bytes(in: folder)) >= Double(m.bytes) * 0.85
    }

    public func download(_ m: SpeechModel, then done: (@MainActor () -> Void)? = nil) {
        guard let mode = m.mode, let folder = folder(m), tasks[m.id] == nil else { return }
        errors[m.id] = nil; progress[m.id] = 0
        let id = m.id, backend = backend
        tasks[id] = Task { [weak self] in
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try await backend.fetch(mode, folder) { p in Task { @MainActor in if self?.progress[id] != nil { self?.progress[id] = min(1, max(0, p)) } } }
                try Task.checkCancellation()
                guard let self else { return }
                if !self.complete(m, folder) {
                    // Files are there by name but far too small: start clean next time rather than load a broken model.
                    try? FileManager.default.removeItem(at: folder)
                    self.errors[id] = "The download was incomplete. Try again."
                }
            } catch is CancellationError {
            } catch {
                // FluidAudio keeps partial files, so a retry resumes instead of starting over.
                if !Task.isCancelled { self?.errors[id] = error.localizedDescription }
            }
            guard let self, !Task.isCancelled else { return }   // cancel() already reset it; a new download may own the id now
            self.tasks[id] = nil; self.progress[id] = nil; self.refresh()
            if self.ready.contains(id) { done?() }
        }
    }

    public func cancel(_ m: SpeechModel) {
        tasks[m.id]?.cancel(); tasks[m.id] = nil; progress[m.id] = nil
    }

    public func delete(_ m: SpeechModel) {
        cancel(m)
        if let folder = folder(m) { try? FileManager.default.trashItem(at: folder, resultingItemURL: nil) }
        refresh()
    }

    /// Fixed states for the UI preview.
    func preview(ready: Set<String>, progress: [String: Double], cleanup: Bool = false) { self.ready = ready; self.progress = progress; cleanupReady = cleanup }

    public func size(_ m: SpeechModel) -> Int64 { folder(m).map(Self.bytes(in:)) ?? 0 }

    static func bytes(in folder: URL) -> Int64 {
        let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey])
        var total: Int64 = 0
        while let url = walker?.nextObject() as? URL { total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return total
    }

    /// Download, size check, cancel and delete against a fake backend in a temporary folder.
    static func selfCheck(_ check: (String, Bool) -> Void) async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("jot-models-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let model = SpeechModel(id: "test", mode: .ultra, name: "Test", maker: "", summary: "", languages: "", bytes: 10_000, speed: 1, accuracy: 1,
                                badge: nil, source: URL(string: "https://example.com")!, symbol: "bird", hue: 0)
        // Writes `size` bytes in ten steps, pausing so a cancel can land mid-download.
        func fake(size: Int) -> ModelBackend {
            ModelBackend(fetch: { _, folder, progress in
                for step in 1...10 {
                    try await Task.sleep(nanoseconds: 20_000_000)
                    progress(Double(step) / 10)
                }
                try Data(count: size).write(to: folder.appendingPathComponent("model.bin"))
            }, present: { _, folder in FileManager.default.fileExists(atPath: folder.appendingPathComponent("model.bin").path) })
        }
        func wait(_ store: ModelStore) async { while store.progress[model.id] != nil { try? await Task.sleep(nanoseconds: 10_000_000) } }

        let good = ModelStore(root: root, catalog: [model], backend: fake(size: 10_000))
        check("models: nothing downloaded yet", good.state(model) == .absent)
        var finished = false
        good.download(model) { finished = true }
        check("models: shows a download in progress", good.state(model) == .downloading(0))
        await wait(good)
        check("models: a full download is ready and runs the follow-up", good.state(model) == .ready && finished && good.errors.isEmpty)
        good.delete(model)
        check("models: delete removes it", good.state(model) == .absent && !FileManager.default.fileExists(atPath: SpeechCatalog.folder(.ultra, root: root).path))

        let short = ModelStore(root: root, catalog: [model], backend: fake(size: 1_000))
        short.download(model)
        await wait(short)
        check("models: a truncated download fails the size check and is cleared", short.state(model) == .absent && short.errors[model.id] != nil)

        let cancelled = ModelStore(root: root, catalog: [model], backend: fake(size: 10_000))
        cancelled.download(model)
        try? await Task.sleep(nanoseconds: 50_000_000)
        cancelled.cancel(model)
        try? await Task.sleep(nanoseconds: 300_000_000)
        check("models: cancel stops it without an error", cancelled.state(model) == .absent && cancelled.errors.isEmpty)
    }
}

/// One file over HTTPS with progress, saved to a temporary file the caller moves or deletes.
/// shortcut: no resume after an interruption; the download starts over, which is fine for a file this size.
private final class FileDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private init(progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }

    static func fetch(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let delegate = FileDownload(progress: progress)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.downloadTask(with: url)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { c in delegate.continuation = c; task.resume() }
        } onCancel: { task.cancel() }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten written: Int64, totalBytesExpectedToWrite total: Int64) {
        if total > 0 { progress(Double(written) / Double(total)) }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The system deletes `location` when this returns, so move it first.
        let kept = FileManager.default.temporaryDirectory.appendingPathComponent("jot-download-\(UUID().uuidString)")
        guard (downloadTask.response as? HTTPURLResponse)?.statusCode == 200 else {
            continuation?.resume(throwing: URLError(.badServerResponse)); continuation = nil; return
        }
        do { try FileManager.default.moveItem(at: location, to: kept); continuation?.resume(returning: kept) }
        catch { continuation?.resume(throwing: error) }
        continuation = nil
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        continuation?.resume(throwing: (error as? URLError)?.code == .cancelled ? CancellationError() : error); continuation = nil
    }
}
