import AppKit
import AVFoundation
import SwiftUI
import ServiceManagement

enum FloatingIconAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

@MainActor public final class AppModel: ObservableObject {
    public let library = Library()
    let speech = SpeechEngine()
    public let classes = ClassRecorder()
    private let cleanup = LocalCleanup()
    @Published var cleanupEnabled = UserDefaults.standard.object(forKey: "cleanupEnabled") as? Bool ?? true
    @Published var cleanupStatus = "Qwen 3.5 4B · local"
    private var originalTranscript: String?
    private var cleanupResult: CleanupResult?
    private var finishingDestinationCaptured = false
    private let recorder = Recorder()
    private let insertion = TextInsertion()
    private let hotkeys = GlobalHotkeys()
    private var consumer: Task<Void, Never>?
    private var started = Date()
    private var stopped = Date()
    private var timer: Timer?
    private var cancelled = false
    private var noteTarget: UUID?
    private var noteOriginal = ""
    private var noteExpected = ""
    private var noteInsertionPaused = false
    private var currentAudioURL: URL?
    private var session = UUID()
    @Published var state = "Loading model…"
    @Published var ready = false
    @Published var recording = false { didSet { postRecordingState() } }
    @Published var finishing = false { didSet { postRecordingState() } }
    /// Lets other tools (a wake-word listener, a voice assistant) pause while Jot uses the microphone.
    private func postRecordingState() {
        for name in Migration.recordingNotifications {
            DistributedNotificationCenter.default().postNotificationName(name, object: nil, userInfo: ["active": recording || finishing], deliverImmediately: true)
        }
    }
    @Published var busy = false
    @Published var transcript = ""
    @Published var seconds: Double = 0
    @Published var level: Float = 0
    @Published var notice = ""
    @Published var hotkeysReady = false
    @Published var selection: UUID?
    @Published var section = "Notes"
    @Published var search = ""
    @Published var showSettings = false
    @Published var showOverlay = false
    @Published var mode: SpeechMode = SpeechMode(rawValue: UserDefaults.standard.string(forKey: "mode") ?? "160") ?? .fast
    @Published var liveInsertion = UserDefaults.standard.object(forKey: "liveInsertion") as? Bool ?? true
    @Published var keepAudio = UserDefaults.standard.object(forKey: "keepAudio") as? Bool ?? false
    @Published var microphoneID = UInt32(UserDefaults.standard.integer(forKey: "microphoneID"))
    @Published var floatingIconAppearance = FloatingIconAppearance(rawValue: UserDefaults.standard.string(forKey: "floatingIconAppearance") ?? "system") ?? .system {
        didSet { UserDefaults.standard.set(floatingIconAppearance.rawValue, forKey: "floatingIconAppearance") }
    }
    @Published var spaceHold = UserDefaults.standard.object(forKey: "spaceHold") as? Bool ?? false {
        didSet { UserDefaults.standard.set(spaceHold, forKey: "spaceHold") }
    }
    @Published var spaceHoldApps = UserDefaults.standard.string(forKey: "spaceHoldApps") ?? SpaceHold.defaultApps {
        didSet { UserDefaults.standard.set(spaceHoldApps, forKey: "spaceHoldApps") }
    }
    private var holdSession = false
    @Published var modelLoadMS: Double = 0
    @Published var previewStatus = "Apple on-device speech"
    var overlayChanged: (() -> Void)?
    public init() {
        if !UserDefaults.standard.bool(forKey: "ultraMigration") {
            mode = .ultra
            UserDefaults.standard.set("ultra", forKey: "mode")
            UserDefaults.standard.set(true, forKey: "ultraMigration")
        }
        hotkeys.smartPaste = { SmartPaste.perform() }
        hotkeys.toggle = { [weak self] in self?.toggle() }
        hotkeys.cancel = { [weak self] in self?.cancel() }
        hotkeys.isRecording = { [weak self] in self?.recording == true }
        hotkeys.holdToTalk = { [weak self] down in self?.holdToTalk(down) }
        // Only hold back Space when a dictation would really start; otherwise it types normally.
        hotkeys.spaceHoldAllowed = { [weak self] in
            guard let self, self.spaceHold, self.ready, !self.busy, !self.recording, !self.finishing, !self.classes.isActive,
                  AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return false }
            return SpaceHold.allows(NSWorkspace.shared.frontmostApplication?.bundleIdentifier, in: self.spaceHoldApps)
        }
        recorder.onLevel = { [weak self] value in Task { @MainActor in self?.level = value } }
        recorder.onError = { [weak self] text in Task { @MainActor in self?.notice = "Audio backup: \(text)" } }
        selection = library.notes.first?.id
    }
    public func start() { library.recoverInterruptedRecordings(); refreshPermissions(); Task { await loadModel(); if cleanupEnabled { cleanupStatus = await cleanup.warm() ? "Qwen 3.5 4B · ready locally" : "Start Ollama to enable cleanup" } } }
    func refreshPermissions() { hotkeysReady = hotkeys.start() }
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in Task { @MainActor in self?.notice = granted ? "Microphone enabled." : "Enable Jot in Privacy & Security → Microphone." } }
    }
    func persistPreferences() {
        let d = UserDefaults.standard
        d.set(cleanupEnabled, forKey: "cleanupEnabled")
        d.set(mode.rawValue, forKey: "mode"); d.set(liveInsertion, forKey: "liveInsertion"); d.set(keepAudio, forKey: "keepAudio"); d.set(Int(microphoneID), forKey: "microphoneID")
    }
    func loadModel() async {
        guard !recording, !finishing, !busy else { return }
        ready = false; busy = true; state = "Preparing \(mode.title)…"; persistPreferences()
        let start = Date()
        do { try await speech.load(mode); modelLoadMS = Date().timeIntervalSince(start) * 1000; previewStatus = await speech.previewStatus; ready = true; state = "Ready" }
        catch { state = "Model unavailable"; notice = error.localizedDescription }
        busy = false
    }
    func holdToTalk(_ down: Bool) {
        if down { if !recording { toggle(skipCleanup: true) } }
        else if holdSession, recording { stop() }
    }
    func addSpaceHoldApp() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.application]; panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier, !SpaceHold.allows(id, in: spaceHoldApps) else { return }
        spaceHoldApps += (spaceHoldApps.isEmpty || spaceHoldApps.hasSuffix("\n") ? "" : "\n") + id
    }
    /// raw: hold-to-talk sends the transcript as spoken, skipping local cleanup.
    func toggle(note: UUID? = nil, skipCleanup: Bool = false) {
        if recording { stop(); return }
        guard !finishing, !busy else { return }
        guard !classes.isActive else { notice = "Class recording is running. Stop it first, or dictate after class."; return }
        guard ready else { notice = "Load the model in Settings first."; showSettings = true; return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { requestMicrophone(); return }
        insertion.capture()
        noteTarget = note; holdSession = skipCleanup
        noteOriginal = library.notes.first(where: { $0.id == note })?.body ?? ""
        noteExpected = noteOriginal; noteInsertionPaused = false; currentAudioURL = nil
        originalTranscript = nil; cleanupResult = nil; finishingDestinationCaptured = false
        transcript = ""; notice = ""; cancelled = false; seconds = 0; level = 0
        let current = UUID(); session = current
        recording = true; showOverlay = true; state = "Starting…"; overlayChanged?()
        consumer = Task {
            do {
                try await speech.begin { [weak self] text in Task { @MainActor in
                    guard let self, self.session == current, !self.cancelled, self.recording || self.finishing else { return }
                    self.receive(text)
                } }
                guard recording, !cancelled else { recording = false; finishing = false; state = "Ready"; showOverlay = false; overlayChanged?(); return }
                let stream = try recorder.start(deviceID: microphoneID == 0 ? nil : microphoneID)
                currentAudioURL = recorder.url
                started = Date(); state = "Recording"
                timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in Task { @MainActor in
                    guard let self else { return }; self.seconds = Date().timeIntervalSince(self.started)
                } }
                for await buffer in stream { try await speech.process(buffer) }
                let raw = try await speech.finish(recordingURL: currentAudioURL)
                let final = TranscriptTools.applyVocabulary(raw, rules: library.vocabulary)
                originalTranscript = final
                if cleanupEnabled, !skipCleanup, !cancelled, !final.isEmpty {
                    state = "Cleaning up…"; overlayChanged?()
                    cleanupResult = await cleanup.clean(final)
                    cleanupStatus = cleanupResult!.status
                }
                complete(cleanupResult?.text ?? final)
            } catch {
                recorder.stop(); timer?.invalidate(); recording = false; finishing = false; showOverlay = false
                state = "Ready"; notice = "Dictation failed: \(error.localizedDescription). Your recording is in History."
                library.add(Dictation(text: transcript, audioFile: currentAudioURL?.lastPathComponent, duration: seconds, finishMS: 0, model: mode.modelName, destination: insertion.destination, status: "Failed · retry available"))
                overlayChanged?()
            }
        }
    }
    private func receive(_ text: String) {
        guard !finishingDestinationCaptured else { return }
        transcript = TranscriptTools.applyVocabulary(text, rules: library.vocabulary)
        if let id = noteTarget, let i = library.notes.firstIndex(where: { $0.id == id }) {
            guard !noteInsertionPaused, library.notes[i].body == noteExpected else { noteInsertionPaused = true; return }
            noteExpected = noteOriginal + (noteOriginal.isEmpty ? "" : "\n") + transcript
            library.notes[i].body = noteExpected
        } else if liveInsertion, insertion.available { _ = insertion.update(transcript) }
        overlayChanged?()
    }
    func stop() {
        guard recording else { return }
        if !cancelled, noteTarget == nil { insertion.captureFinishDestination() }
        finishingDestinationCaptured = true
        finishing = true; recording = false; state = "Finishing…"; stopped = Date(); timer?.invalidate()
        // Keep a brief physical tail for a key press that overlaps the final phoneme.
        let stoppingSession = session
        Task { try? await Task.sleep(nanoseconds: 160_000_000); if session == stoppingSession { recorder.stop() } }
        overlayChanged?()
    }
    func cancel() { guard recording else { return }; cancelled = true; insertion.cancel(); stop() }
    private func complete(_ text: String) {
        session = UUID()
        recording = false; finishing = false; timer?.invalidate(); level = 0; state = "Ready"
        let ms = Date().timeIntervalSince(stopped) * 1000
        var status = "Saved to history"
        if cancelled {
            if let id = noteTarget, let i = library.notes.firstIndex(where: { $0.id == id }), !noteInsertionPaused, library.notes[i].body == noteExpected { library.notes[i].body = noteOriginal }
            status = "Cancelled · recovered in history"; notice = ""
        } else if text.isEmpty { status = "No speech detected · retry available"; notice = "" }
        else if let id = noteTarget, let i = library.notes.firstIndex(where: { $0.id == id }) {
            if !noteInsertionPaused, library.notes[i].body == noteExpected {
                library.notes[i].body = noteOriginal + (noteOriginal.isEmpty ? "" : "\n") + text
                library.notes[i].updated = Date(); library.save(); status = "Saved to note"
            } else { notice = "Your note changed while recording. Full transcript saved in History." }
        } else if !liveInsertion, insertion.pasteFinal(text) { status = "Paste requested in \(insertion.destination)" }
        else if liveInsertion, insertion.update(text) { status = "Inserted in \(insertion.destination)" }
        else if liveInsertion, !insertion.available, insertion.pasteFinal(text) { status = "Paste requested in \(insertion.destination)" }
        else { notice = insertion.inserted.isEmpty ? "Transcript ready. Copy it below and paste where you want." : "Text focus changed. Full transcript saved; copy it below if needed." }
        let recover = keepAudio || cancelled || text.isEmpty || status == "Saved to history"
        let audio = currentAudioURL?.lastPathComponent
        var entry = Dictation(text: text, audioFile: recover ? audio : nil, duration: seconds, finishMS: ms, model: mode.modelName, destination: noteTarget == nil ? insertion.destination : "Jot note", status: status)
        entry.originalText = originalTranscript
        entry.cleanupMS = cleanupResult?.milliseconds
        entry.cleanupStatus = cleanupResult?.status
        library.add(entry)
        if !recover, let path = currentAudioURL { try? FileManager.default.removeItem(at: path) }
        transcript = text
        showOverlay = false
        overlayChanged?()
    }
    func newNote() { section = "Notes"; selection = library.addNote() }
    func benchmarkFile() {
        guard !busy, !recording, !finishing else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.audio]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        runFile(url, source: url.lastPathComponent, retry: false)
    }
    func retry(_ entry: Dictation) {
        guard let file = entry.audioFile, !busy, !recording, !finishing else { return }
        runFile(JotPaths.recordings.appendingPathComponent(file), source: "Retry of \(entry.date.formatted())", retry: true)
    }
    private func runFile(_ url: URL, source: String, retry: Bool) {
        busy = true; state = retry ? "Retrying…" : "Benchmarking…"
        Task {
            do {
                let result = try await speech.transcribeFile(url, mode: mode, source: source)
                if retry { library.add(Dictation(text: TranscriptTools.applyVocabulary(result.transcript, rules: library.vocabulary), audioFile: url.lastPathComponent, duration: result.audioSeconds, finishMS: result.finalizationMS, model: result.model, destination: "History", status: "Recovered · ready to copy")) }
                else { library.add(result) }
                notice = retry ? "Recovered transcript saved in History." : "Benchmark saved. \(String(format: "%.1f", result.speed))× realtime."
            } catch { notice = error.localizedDescription }
            busy = false; state = "Ready"
        }
    }
}
