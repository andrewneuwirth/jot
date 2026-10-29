import AppKit
import JotCore

@main struct Main {
    @MainActor static func main() {
        // Headless for other tools: no NSApplication, so no Dock icon, windows or effect on a running Jot.
        if let request = TranscribeCommand.parse(CommandLine.arguments) {
            Task {
                do { let text = try await TranscribeCommand.run(request.get()); print(text); exit(0) }
                catch { fputs("Jot: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            dispatchMain()
        }
        if CommandLine.arguments.contains("--prepare-model") || CommandLine.arguments.contains("--benchmark") {
            Task { await command(); exit(0) }
            dispatchMain()
        }
        launch()
    }
    @MainActor static func command() async {
        let args = CommandLine.arguments
        if args.contains("--prepare-model") || args.contains("--benchmark") {
            let engine = SpeechEngine()
            let mode: SpeechMode = args.contains("--ultra") ? .ultra : (args.contains("--320") ? .balanced : .fast)
            do {
                if let i = args.firstIndex(of: "--benchmark"), args.count > i + 1 {
                    let reference: String? = args.firstIndex(of: "--reference").flatMap { args.count > $0 + 1 ? args[$0 + 1] : nil }
                    let path = URL(fileURLWithPath: args[i + 1])
                    let result = try await engine.transcribeFile(path, mode: mode, source: path.lastPathComponent, reference: reference)
                    if !args.contains("--no-save") { let library = Library(); library.add(result) }
                    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    print(String(data: try encoder.encode(result), encoding: .utf8)!)
                } else { try await engine.load(mode); print("Jot model ready: \(mode.modelName)"); print("Preview: \(await engine.previewStatus)") }
            } catch { fputs("Jot: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
    }
    @MainActor static func launch() {
        let app = NSApplication.shared
        let delegate = JotApplication()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
