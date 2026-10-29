import AppKit
import AVFoundation
import CoreML
import FluidAudio

public enum SpeechMode: String, CaseIterable, Identifiable {
    case ultra = "ultra", fast = "160", balanced = "320"
    public var id: String { rawValue }
    public var title: String { self == .ultra ? "Ultra + Apple live preview" : (self == .fast ? "Realtime · 160 ms" : "Balanced · 320 ms") }
    public var modelName: String { self == .ultra ? "Parakeet Ultra · Apple preview" : "Parakeet Realtime EOU 120M · \(rawValue) ms" }
    var chunk: StreamingChunkSize { self == .fast ? .ms160 : .ms320 }
}
public actor SpeechEngine {
    private var manager: StreamingEouAsrManager?
    private var loadedMode: SpeechMode?
    private var ultra: AsrManager?
    private let apple = ApplePreview()
    public private(set) var previewStatus = "Apple on-device speech"

    public init() {}
    public func load(_ mode: SpeechMode) async throws {
        if loadedMode == mode, manager != nil { return }
        try JotPaths.prepare()
        let config = MLModelConfiguration(); config.computeUnits = .cpuAndNeuralEngine
        if mode == .ultra {
            let models = try await AsrModels.downloadAndLoad(to: JotPaths.models.appendingPathComponent("parakeet-ultra"), configuration: config, version: .ultra)
            let next = AsrManager(config: .default)
            try await next.loadModels(models)
            ultra = next; manager = nil; loadedMode = mode
            do { try await apple.prepare(); previewStatus = "Apple on-device speech" }
            catch { previewStatus = error.localizedDescription }
            return
        }
        ultra = nil
        let next = StreamingEouAsrManager(configuration: config, chunkSize: mode.chunk)
        try await next.loadModels(to: JotPaths.models)
        manager = next; loadedMode = mode
    }
    public func begin(partial: @escaping @Sendable (String) -> Void) async throws {
        if loadedMode == .ultra {
            do { try await apple.begin(partial: partial) }
            catch { previewStatus = error.localizedDescription }
            return
        }
        guard let manager else { throw JotError.message("Download and load the model first.") }
        await manager.reset()
        await manager.setPartialCallback(partial)
    }
    public func process(_ buffer: AVAudioPCMBuffer) async throws {
        if loadedMode == .ultra { await apple.append(buffer); return }
        guard let manager else { throw JotError.message("Model is not loaded.") }
        _ = try await manager.process(audioBuffer: buffer)
    }
    public func finish(recordingURL: URL? = nil) async throws -> String {
        if loadedMode == .ultra {
            await apple.stop()
            guard let ultra, let recordingURL else { throw JotError.message("Original recording is unavailable for Ultra.") }
            var state = TdtDecoderState.make(decoderLayers: await ultra.decoderLayerCount)
            let result = try await ultra.transcribe(recordingURL, decoderState: &state)
            return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let manager else { throw JotError.message("Model is not loaded.") }
        // A short synthetic silence flushes the encoder's right context without
        // waiting for a long real-time silence detector or throwing away audio.
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let tail = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 5120)!
        tail.frameLength = 5120
        memset(tail.floatChannelData![0], 0, Int(tail.frameLength) * MemoryLayout<Float>.size)
        _ = try await manager.process(audioBuffer: tail)
        return try await manager.finish().trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public func transcribeFile(_ url: URL, mode: SpeechMode, source: String, reference: String? = nil,
                               partial: @escaping @Sendable (String) -> Void = { _ in }) async throws -> Benchmark {
        try await load(mode)
        if mode != .ultra { try await begin(partial: partial) }
        let file = try AVAudioFile(forReading: url)
        let start = Date()
        let frames = AVAudioFrameCount(max(1, Int(file.processingFormat.sampleRate * 0.16)))
        while mode != .ultra && file.framePosition < file.length {
            try Task.checkCancellation()
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames)!
            try file.read(into: buffer)
            if buffer.frameLength > 0 { try await process(buffer) }
        }
        let finalStart = Date()
        let text = try await finish(recordingURL: url)
        let elapsed = Date().timeIntervalSince(start)
        let finalMS = Date().timeIntervalSince(finalStart) * 1000
        let duration = Double(file.length) / file.processingFormat.sampleRate
        let wer = reference.map { TranscriptTools.wordErrorRate(reference: $0, hypothesis: text) }
        return Benchmark(model: mode.modelName, source: source, audioSeconds: duration,
                         processingSeconds: elapsed, finalizationMS: finalMS, transcript: text,
                         reference: reference, wordErrorRate: wer, hardware: Self.hardware())
    }
    public nonisolated static func hardware() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var bytes = [CChar](repeating: 0, count: max(1, size))
        sysctlbyname("machdep.cpu.brand_string", &bytes, &size, nil, 0)
        return "\(String(cString: bytes)) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
    }
}
/// `Jot --transcribe <file>` for other local tools: raw Ultra transcript on stdout.
public enum TranscribeCommand {
    /// nil when this is not a transcribe invocation; otherwise the file or a usage error.
    public static func parse(_ arguments: [String]) -> Result<URL, JotError>? {
        guard let i = arguments.firstIndex(of: "--transcribe") else { return nil }
        guard arguments.count > i + 1, !arguments[i + 1].isEmpty, !arguments[i + 1].hasPrefix("--") else {
            return .failure(.message("Usage: Jot --transcribe <path-to-audio-file>"))
        }
        return .success(URL(fileURLWithPath: arguments[i + 1]))
    }
    /// Loads only the cached Ultra weights (never downloads) and skips cleanup and vocabulary.
    public static func run(_ url: URL) async throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else { throw JotError.message("No audio file at \(url.path)") }
        let config = MLModelConfiguration(); config.computeUnits = .cpuAndNeuralEngine
        let models: AsrModels
        do { models = try AsrModels.loadLocal(from: JotPaths.models.appendingPathComponent("parakeet-ultra"), version: .ultra, configuration: config) }
        catch { throw JotError.message("Parakeet Ultra is not on this Mac yet. Open Jot once to download it. (\(error.localizedDescription))") }
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        // AVAudioFile reads wav/aiff/caf/m4a/mp3/flac/Ogg Opus; WebM (bb/Chromium voice notes) is demuxed here.
        let result: ASRResult
        if WebMOpus.isWebM(url) { result = try await manager.transcribe(WebMOpus.decode(url), decoderState: &state) }
        else { result = try await manager.transcribe(url, decoderState: &state) }
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
public enum JotError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

/// Tap writes the recovery file and yields copied buffers into one ordered stream.
/// The consumer drains that stream before finalization; no last-buffer race.
public final class Recorder {
    private var engine: AVAudioEngine?
    private let lock = NSLock()
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var file: AVAudioFile?
    public private(set) var url: URL?
    private var accepting = false
    public var onLevel: ((Float) -> Void)?
    public var onError: ((String) -> Void)?
    public init() {}
    public func start(deviceID: AudioDeviceID? = nil, directory: URL = JotPaths.recordings) throws -> AsyncStream<AVAudioPCMBuffer> {
        try JotPaths.prepare()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let e = AVAudioEngine()
        let input = e.inputNode
        if var id = deviceID, let unit = input.audioUnit {
            let result = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size))
            guard result == noErr else { throw JotError.message("Could not select this microphone. Choose System default.") }
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw JotError.message("No microphone is available.") }
        let path = directory.appendingPathComponent("\(UUID().uuidString).caf")
        file = try AVAudioFile(forWriting: path, settings: format.settings)
        url = path
        let stream = AsyncStream<AVAudioPCMBuffer> { continuation = $0 }
        accepting = true
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.lock.lock(); defer { self.lock.unlock() }
            guard self.accepting else { return }
            do { try self.file?.write(from: buffer) } catch { self.onError?(error.localizedDescription) }
            guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return }
            copy.frameLength = buffer.frameLength
            let from = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            let to = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
            for (src, dst) in zip(from, to) { if let s = src.mData, let d = dst.mData { memcpy(d, s, Int(src.mDataByteSize)) } }
            if let values = buffer.floatChannelData?[0] {
                let count = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<count { sum += values[i] * values[i] }
                self.onLevel?(min(1, sqrt(sum / Float(max(1, count))) * 8))
            }
            self.continuation?.yield(copy)
        }
        do { try e.start(); engine = e } catch {
            input.removeTap(onBus: 0); accepting = false; continuation?.finish(); file = nil; throw error
        }
        return stream
    }
    public func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop(); engine = nil
        lock.lock(); defer { lock.unlock() }
        accepting = false; file = nil; continuation?.finish(); continuation = nil
    }
}
