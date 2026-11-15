import SwiftUI
import AppKit
import MacToolsKit

/// Every speech model Jot can run, downloaded in the app from its official source and run on this Mac.
struct ModelsPage: View {
    @ObservedObject var model: AppModel
    @ObservedObject var models: ModelStore
    var body: some View {
        PageHeader(title: "Models", detail: "\(models.ready.count) on this Mac") {
            SoftButton(title: "Show model files", symbol: "folder") { try? FileManager.default.createDirectory(at: JotPaths.models, withIntermediateDirectories: true); NSWorkspace.shared.open(JotPaths.models) }
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                section("Speech to text", "Runs on the Neural Engine. Nothing you say leaves this Mac.")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(models.catalog) { ModelCard(model: model, models: models, item: $0) }
                }
                section("Cleanup", "Optional. Tidies a dictation after it's transcribed, also on this Mac.").padding(.top, 10)
                CleanupCard(model: model)
                Text("Downloads come from Hugging Face (the models' official Core ML conversions by FluidInference). Each model keeps its own license; see its model card.")
                    .font(.system(size: 11)).foregroundStyle(Look.muted).padding(.top, 4)
            }
            .padding([.horizontal, .bottom], 22)
        }
    }

    private func section(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Look.ink).accessibilityAddTraits(.isHeader)
            Text(detail).font(.system(size: 12)).foregroundStyle(Look.muted)
        }
    }
}

struct ModelCard: View {
    @ObservedObject var model: AppModel
    @ObservedObject var models: ModelStore
    let item: SpeechModel
    @State private var confirmDelete = false

    private var inUse: Bool { item.mode == model.mode }
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    ModelMark(model: item)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Look.ink)
                        Text(item.maker).font(.system(size: 11.5)).foregroundStyle(Look.muted)
                    }
                    Spacer(minLength: 6)
                    if let badge = item.badge { Chip(text: badge, tint: badge == "Recommended" ? Look.accent : nil) }
                }
                Text(item.summary).font(.system(size: 12.5)).foregroundStyle(Look.muted).lineLimit(3, reservesSpace: true)
                HStack(spacing: 14) {
                    Meter(label: "Speed", value: item.speed)
                    Meter(label: "Accuracy", value: item.accuracy)
                    Spacer()
                    Text(item.languages).font(.system(size: 11)).foregroundStyle(Look.muted).lineLimit(1)
                }
                Divider().overlay(Look.line)
                footer.frame(minHeight: 30)
                if let error = models.errors[item.id] {
                    Text(error).font(.system(size: 11)).foregroundStyle(Color.mtBad).lineLimit(2)
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: MT.Radius.card).strokeBorder(inUse ? Look.accent.opacity(0.55) : .clear, lineWidth: 1.5))
        .confirmationDialog("Delete \(item.name)?", isPresented: $confirmDelete) {
            Button("Move to Trash", role: .destructive) { models.delete(item) }
        } message: { Text("You can download it again any time.") }
    }

    @ViewBuilder private var footer: some View {
        switch models.state(item) {
        case .builtIn:
            HStack { StatusPill(ok: true, text: "Ready"); Spacer(); Text("Live preview · classes · calls").font(.system(size: 11)).foregroundStyle(Look.muted) }
        case .absent:
            HStack {
                PrimaryButton(title: "Download", symbol: "arrow.down.circle.fill") { models.download(item) }
                Text(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file)).font(.system(size: 11.5)).foregroundStyle(Look.muted)
                Spacer()
                Link(destination: item.source) { Text("Model card").font(.system(size: 11.5)) }
            }
        case .downloading(let p):
            HStack(spacing: 10) {
                ProgressBar(value: p)
                Text(p > 0 ? "\(Int(p * 100))%" : "Starting…").font(.system(size: 11.5, weight: .medium)).monospacedDigit().foregroundStyle(Look.ink).frame(width: 58, alignment: .trailing)
                SoftButton(title: "Cancel", symbol: "xmark") { models.cancel(item) }
            }
        case .ready:
            HStack(spacing: 8) {
                if inUse {
                    StatusPill(ok: true, text: model.ready ? "In use" : model.state)
                } else {
                    PrimaryButton(title: "Use", symbol: "checkmark", disabled: model.recording || model.finishing || model.busy) { if let m = item.mode { model.use(m) } }
                    StatusPill(ok: true, text: "Downloaded")
                }
                Spacer()
                Menu {
                    Link("Model card", destination: item.source)
                    Button("Show in Finder") { if let f = models.folder(item) { NSWorkspace.shared.activateFileViewerSelecting([f]) } }
                    Divider()
                    Button("Delete…", role: .destructive) { confirmDelete = true }.disabled(inUse)
                } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28)
            }
        }
    }
}

/// Local cleanup through Ollama (Qwen 3.5 4B). Jot never downloads it; Ollama does.
struct CleanupCard: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Card {
            HStack(alignment: .center, spacing: 12) {
                RoundedRectangle(cornerRadius: 11).fill(LinearGradient(colors: [Color(hue: 0.75, saturation: 0.35, brightness: 0.95), Color(hue: 0.72, saturation: 0.6, brightness: 0.7)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 44, height: 44)
                    .overlay(Image(systemName: "sparkles").font(.system(size: 19, weight: .semibold)).foregroundStyle(.white))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Qwen 3.5 4B").font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Look.ink)
                        Chip(text: "via Ollama")
                    }
                    Text(model.cleanupEnabled ? model.cleanupStatus : "Removes ums, stutters and spoken corrections (\"Tuesday, I mean Wednesday\"). Quotes stay verbatim; the original stays in History.")
                        .font(.system(size: 12)).foregroundStyle(Look.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Link(destination: URL(string: "https://ollama.com/library/qwen3.5")!) { Text("Get it with Ollama").font(.system(size: 11.5)) }
                Toggle("Clean up dictation", isOn: $model.cleanupEnabled).labelsHidden().toggleStyle(.switch)
                    .onChange(of: model.cleanupEnabled) { _, _ in model.persistPreferences() }
            }
        }
    }
}
