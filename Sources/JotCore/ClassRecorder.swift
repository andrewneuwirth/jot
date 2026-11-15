import AppKit
import AVFoundation

/// A long lecture recording: raw audio always on disk, live Apple transcript, no cleanup.
/// Audio rotates into segment files so a crash loses at most the last buffer, and the
/// session file is rewritten every few seconds so nothing depends on pressing Stop.
public struct ClassSession: Codable, Identifiable {
    public var id = UUID()
    public var title: String
    public var started = Date()
    public var seconds: Double = 0
    public var segments: [String] = []
    public var transcript = ""
    public var liveTranscript = ""
    public var status = "Recording"
    /// "call" or "class"; sessions saved before the two tabs split have none and are told apart by their title.
    public var kind: String?
    public var folder: String { id.uuidString }
    public var isCall: Bool { kind == "call" || (kind == nil && title.hasPrefix("Call")) }
    public init(title: String, isCall: Bool) { self.title = title; kind = isCall ? "call" : "class" }
}

public enum ClassPaths {
    public static let root = JotPaths.root.appendingPathComponent("Classes")
    public static func directory(_ s: ClassSession) -> URL { root.appendingPathComponent(s.folder) }
    public static func sessionFile(_ s: ClassSession) -> URL { directory(s).appendingPathComponent("session.json") }
    public static func audio(_ s: ClassSession, _ file: String) -> URL { directory(s).appendingPathComponent(file) }
}

@MainActor public final class ClassRecorder: ObservableObject {
    @Published public private(set) var sessions: [ClassSession] = []
    @Published public private(set) var active: ClassSession?
    @Published public private(set) var elapsed: Double = 0
    @Published public private(set) var level: Float = 0
    @Published public var notice = ""
    @Published public private(set) var retranscribing = false

    public var isActive: Bool { active != nil }
    /// Live transcript shown while recording = finished segments + the segment in progress.
    public var liveText: String { join(committed, live) }

    private var committed = ""
    private var live = ""
    private var started = Date()
    private var carried: Double = 0
    private var ticker: Timer?
    private var lastSave = Date.distantPast
    private var lastBuffer = Date()
    private var assertion: NSObjectProtocol?
    private var segment: Segment?
    private var segmentStart = Date()
    private let segmentLength: TimeInterval = 15 * 60
    private var microphoneID: UInt32 = 0
    private var generation = 0
    private var macAudio: SystemAudioTap? // set while recording a call (mic + Mac audio)
    private var inputID: UInt32? { macAudio.map { $0.deviceID } ?? (microphoneID == 0 ? nil : microphoneID) }

    public init() { load() }
    /// Made-up sessions for the UI preview: nothing is read from or written to disk.
    public init(preview: [ClassSession]) { sessions = preview }

    // MARK: Segment = one audio file + one Apple transcription run

    private final class Segment {
        let recorder = Recorder()
        let preview = ApplePreview()
        var task: Task<String, Never>?
        var file: String?
    }

    // MARK: Start / stop

    /// `includeMacAudio`: also record what the Mac plays (both sides of a FaceTime/Zoom call).
    public func start(microphoneID: UInt32, includeMacAudio: Bool = false) {
        guard active == nil else { return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] ok in Task { @MainActor in self?.notice = ok ? "Microphone enabled. Press Record again." : "Enable Jot in Privacy & Security → Microphone." } }
            return
        default: notice = "Enable Jot in Privacy & Security → Microphone."; return
        }
        self.microphoneID = microphoneID
        if includeMacAudio {
            let tap = SystemAudioTap()
            do { _ = try tap.start(microphoneID: microphoneID); macAudio = tap }
            catch { notice = error.localizedDescription; return }
        }
        let f = DateFormatter(); f.dateFormat = "EEE MMM d · h:mm a"
        var session = ClassSession(title: (includeMacAudio ? "Call · " : "Class · ") + f.string(from: Date()), isCall: includeMacAudio)
        do { try FileManager.default.createDirectory(at: ClassPaths.directory(session), withIntermediateDirectories: true) }
        catch { notice = "Could not create the recording folder: \(error.localizedDescription)"; macAudio?.stop(); macAudio = nil; return }
        session.status = "Recording"
        active = session; sessions.insert(session, at: 0)
        committed = ""; live = ""; carried = 0; elapsed = 0; notice = ""; started = Date(); lastBuffer = Date()
        assertion = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled, .automaticTerminationDisabled, .suddenTerminationDisabled], reason: "Recording a class")
        beginSegment()
        saveActive(force: true)
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
    }

    public func stop() async {
        guard var session = active else { return }
        ticker?.invalidate(); ticker = nil
        elapsed = carried + Date().timeIntervalSince(started)
        let finishing = segment; segment = nil
        generation += 1
        active = nil; level = 0
        session.status = "Finishing…"; update(session)
        // Brief tail so the last words are not clipped.
        try? await Task.sleep(nanoseconds: 300_000_000)
        finishing?.recorder.stop()
        macAudio?.stop(); macAudio = nil
        let tail = await finishing?.task?.value ?? ""
        committed = join(committed, tail); live = ""
        session = current(session)
        session.seconds = elapsed; session.transcript = committed; session.liveTranscript = committed
        session.status = "Finished"
        update(session); write(session)
        if let assertion { ProcessInfo.processInfo.endActivity(assertion); self.assertion = nil }
    }

    // MARK: Segments

    private func beginSegment() {
        let seg = Segment()
        segment = seg; segmentStart = Date(); lastBuffer = Date()
        let gen = generation
        guard var session = active else { return }
        let dir = ClassPaths.directory(session)
        do {
            let stream = try seg.recorder.start(deviceID: inputID, directory: dir, mixdown: macAudio != nil)
            seg.file = seg.recorder.url?.lastPathComponent
            if let file = seg.file { session.segments.append(file); active = session; update(session); saveActive(force: true) }
            seg.recorder.onLevel = { [weak self] v in Task { @MainActor in self?.level = v } }
            seg.recorder.onError = { [weak self] text in Task { @MainActor in self?.notice = "Audio backup: \(text)" } }
            seg.task = Task { [weak self] in
                var previewOK = true
                do {
                    try await seg.preview.prepare()
                    try await seg.preview.begin { text in Task { @MainActor in
                        guard let self, self.generation == gen, self.segment === seg else { return }
                        self.live = text
                    } }
                } catch { previewOK = false; await MainActor.run { self?.notice = "Live text unavailable (\(error.localizedDescription)). Audio is still being saved." } }
                for await buffer in stream {
                    await MainActor.run { self?.lastBuffer = Date() }
                    if previewOK { await seg.preview.append(buffer) }
                }
                guard previewOK else { return "" }
                return (try? await seg.preview.finish()) ?? ""
            }
        } catch {
            notice = "Could not start recording: \(error.localizedDescription). Retrying…"
            segment = nil
        }
    }

    /// Close the current segment and open a new one without a gap (new engine starts first).
    private func rotate() {
        guard active != nil else { return }
        let old = segment
        generation += 1
        let oldLive = live
        beginSegment()
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            old?.recorder.stop()
            let text = await old?.task?.value ?? ""
            await MainActor.run {
                guard let self else { return }
                self.committed = self.join(self.committed, text.isEmpty ? oldLive : text)
                if self.segment != nil { self.live = "" }
                self.saveActive(force: true)
            }
        }
    }

    private func tick() {
        guard active != nil else { return }
        elapsed = carried + Date().timeIntervalSince(started)
        // Mic unplugged / route changed / engine stopped: buffers stop arriving. Start a fresh segment.
        if segment == nil || Date().timeIntervalSince(lastBuffer) > 6 {
            notice = "Microphone interrupted — reconnecting…"
            rotate()
        } else if Date().timeIntervalSince(segmentStart) > segmentLength {
            rotate()
        } else if notice.hasPrefix("Microphone interrupted"), Date().timeIntervalSince(lastBuffer) < 2 { notice = "" }
        saveActive(force: false)
    }

    // MARK: Persistence

    private func current(_ fallback: ClassSession) -> ClassSession { sessions.first { $0.id == fallback.id } ?? fallback }
    private func update(_ s: ClassSession) { if let i = sessions.firstIndex(where: { $0.id == s.id }) { sessions[i] = s } }
    private func saveActive(force: Bool) {
        guard var s = active, force || Date().timeIntervalSince(lastSave) > 5 else { return }
        lastSave = Date()
        s = current(s)
        s.seconds = elapsed; s.liveTranscript = liveText; s.transcript = liveText; s.status = "Recording"
        active = s; update(s); write(s)
    }
    private func write(_ s: ClassSession) {
        do {
            let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
            try e.encode(s).write(to: ClassPaths.sessionFile(s), options: .atomic)
        } catch { notice = "Could not save the session: \(error.localizedDescription)" }
    }
    private func load() {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: ClassPaths.root, includingPropertiesForKeys: nil)) ?? []
        var found: [ClassSession] = []
        for d in dirs {
            guard var s = try? JSONDecoder().decode(ClassSession.self, from: Data(contentsOf: d.appendingPathComponent("session.json"))) else { continue }
            if s.status == "Recording" || s.status == "Finishing…" {
                s.status = "Interrupted · audio saved"
                if let seconds = Self.audioSeconds(s) { s.seconds = max(s.seconds, seconds) }
                write(s)
            }
            found.append(s)
        }
        sessions = found.sorted { $0.started > $1.started }
    }
    private static func audioSeconds(_ s: ClassSession) -> Double? {
        let total = s.segments.compactMap { f -> Double? in
            guard let a = try? AVAudioFile(forReading: ClassPaths.audio(s, f)) else { return nil }
            return Double(a.length) / a.processingFormat.sampleRate
        }.reduce(0, +)
        return total > 0 ? total : nil
    }

    public func rename(_ id: UUID, to title: String) {
        guard var s = sessions.first(where: { $0.id == id }) else { return }
        s.title = title; update(s); write(s)
        if active?.id == id { active = s }
    }
    public func delete(_ id: UUID) {
        guard active?.id != id, let s = sessions.first(where: { $0.id == id }) else { return }
        try? FileManager.default.trashItem(at: ClassPaths.directory(s), resultingItemURL: nil)
        sessions.removeAll { $0.id == id }
    }

    // MARK: Re-transcribe from the saved audio (Parakeet Ultra), keeping the live text

    public func retranscribe(_ id: UUID, engine: SpeechEngine, mode: SpeechMode) {
        guard !retranscribing, active == nil, var s = sessions.first(where: { $0.id == id }) else { return }
        retranscribing = true; notice = "Re-transcribing from audio…"
        Task {
            var parts: [String] = []
            do {
                for (i, file) in s.segments.enumerated() {
                    notice = "Re-transcribing part \(i + 1) of \(s.segments.count)…"
                    let url = ClassPaths.audio(s, file)
                    guard FileManager.default.fileExists(atPath: url.path) else { continue }
                    let r = try await engine.transcribeFile(url, mode: mode, source: "Class \(s.title)")
                    parts.append(r.transcript)
                }
                if s.liveTranscript.isEmpty { s.liveTranscript = s.transcript }
                s.transcript = parts.filter { !$0.isEmpty }.joined(separator: "\n\n")
                update(s); write(s); notice = "Re-transcribed. The original live text is kept below."
            } catch { notice = "Re-transcribe failed: \(error.localizedDescription). Your audio is untouched." }
            retranscribing = false
        }
    }

    private func join(_ a: String, _ b: String) -> String {
        let x = a.trimmingCharacters(in: .whitespacesAndNewlines), y = b.trimmingCharacters(in: .whitespacesAndNewlines)
        return x.isEmpty ? y : (y.isEmpty ? x : x + "\n\n" + y)
    }
}

public func formatClock(_ seconds: Double) -> String {
    let t = Int(max(0, seconds)); return String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
}
