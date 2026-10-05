import AVFoundation
import Speech

/// Apple's local SpeechAnalyzer only supplies provisional display text.
/// Ultra independently transcribes the retained microphone audio at stop.
actor ApplePreview {
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var reader: Task<Void, Never>?
    private var format: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var lastText = ""
    private var locale = Locale(identifier: "en-US")

    func prepare() async throws {
        guard SpeechTranscriber.isAvailable,
              let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw JotError.message("Apple on-device English preview is unavailable. Ultra still transcribes when you stop.")
        }
        locale = supported
        let module = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await request.downloadAndInstall()
        }
    }
    func begin(partial: @escaping @Sendable (String) -> Void) async throws {
        await stop()
        lastText = ""
        let module = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw JotError.message("Apple preview has no compatible audio format.")
        }
        self.format = format
        let analyzer = SpeechAnalyzer(modules: [module])
        self.analyzer = analyzer
        let stream = AsyncStream<AnalyzerInput> { input = $0 }
        reader = Task {
            var finalized = ""
            do {
                for try await result in module.results {
                    let text = String(result.text.characters)
                    let display = finalized + text
                    lastText = display
                    partial(display.trimmingCharacters(in: .whitespacesAndNewlines))
                    if result.isFinal { finalized = display }
                }
            } catch { /* Preview is optional; original audio still goes to Ultra. */ }
        }
        try await analyzer.prepareToAnalyze(in: format)
        try await analyzer.start(inputSequence: stream)
    }
    func append(_ buffer: AVAudioPCMBuffer) {
        guard let input, let format else { return }
        if buffer.format == format { input.yield(AnalyzerInput(buffer: buffer)); return }
        if converter == nil { converter = AVAudioConverter(from: buffer.format, to: format) }
        guard let converter else { return }
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true; status.pointee = .haveData; return buffer
        }
        if error == nil, output.frameLength > 0 { input.yield(AnalyzerInput(buffer: output)) }
    }
    func finish() async throws -> String {
        input?.finish(); input = nil
        try await analyzer?.finalizeAndFinishThroughEndOfInput()
        await reader?.value
        return lastText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func stop() async {
        input?.finish(); input = nil
        await analyzer?.cancelAndFinishNow()
        reader?.cancel(); reader = nil; analyzer = nil; converter = nil; format = nil
    }
}
