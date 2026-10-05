import AppKit
import AVFoundation
import CoreML
import FluidAudio

public enum SpeechMode: String, CaseIterable, Identifiable {
    case fast = "160", balanced = "320"
    public var id: String { rawValue }
    public var title: String { self == .fast ? "Realtime · 160 ms" : "Balanced · 320 ms" }
    public var modelName: String { "Parakeet Realtime EOU 120M · \(rawValue) ms" }
    var chunk: StreamingChunkSize { self == .fast ? .ms160 : .ms320 }
}
public actor SpeechEngine {
    private var manager: StreamingEouAsrManager?
    private var loadedMode: SpeechMode?
    public init() {}
    public func load(_ mode: SpeechMode) async throws {
        if loadedMode == mode, manager != nil { return }
        try JotPaths.prepare()
        let config = MLModelConfiguration(); config.computeUnits = .cpuAndNeuralEngine
        let next = StreamingEouAsrManager(configuration: config, chunkSize: mode.chunk)
        try await next.loadModels(to: JotPaths.models)
        manager = next; loadedMode = mode
    }
    public func begin(partial: @escaping @Sendable (String) -> Void) async throws {
        guard let manager else { throw JotError.message("Download and load the model first.") }
        await manager.reset()
        await manager.setPartialCallback(partial)
    }
    public func process(_ buffer: AVAudioPCMBuffer) async throws {
        guard let manager else { throw JotError.message("Model is not loaded.") }
        _ = try await manager.process(audioBuffer: buffer)
    }
    public func finish() async throws -> String {
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
        try await begin(partial: partial)
        let file = try AVAudioFile(forReading: url)
        let start = Date()
        let frames = AVAudioFrameCount(max(1, Int(file.processingFormat.sampleRate * 0.16)))
        while file.framePosition < file.length {
            try Task.checkCancellation()
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames)!
            try file.read(into: buffer)
            if buffer.frameLength > 0 { try await process(buffer) }
        }
        let finalStart = Date()
        let text = try await finish()
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
    public func start(deviceID: AudioDeviceID? = nil) throws -> AsyncStream<AVAudioPCMBuffer> {
        try JotPaths.prepare()
        let e = AVAudioEngine()
        let input = e.inputNode
        if var id = deviceID, let unit = input.audioUnit {
            let result = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size))
            guard result == noErr else { throw JotError.message("Could not select this microphone. Choose System default.") }
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw JotError.message("No microphone is available.") }
        let path = JotPaths.recordings.appendingPathComponent("\(UUID().uuidString).caf")
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
