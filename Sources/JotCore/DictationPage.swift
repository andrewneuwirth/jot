import SwiftUI
import AppKit
import MacToolsKit

/// Dictation: how to start, the settings that change what you get, and everything you've said.
struct DictationPage: View {
    @ObservedObject var model: AppModel
    @ObservedObject var library: Library
    var body: some View {
        PageHeader(title: "Dictation", detail: library.history.isEmpty ? nil : "\(library.history.count) in history") {
            SearchPill(text: $model.search, prompt: "Search history")
        }
        VStack(spacing: MT.Space.s12) {
            hero
            HStack(alignment: .top, spacing: MT.Space.s12) {
                list.frame(width: 340)
                detail
            }
        }
        .padding([.horizontal, .bottom], 22)
    }

    private var entries: [Dictation] {
        library.history.filter { model.search.isEmpty || $0.text.localizedCaseInsensitiveContains(model.search) }
    }

    /// Start button, the shortcut, and the quick settings.
    private var hero: some View {
        Card {
            HStack(alignment: .center, spacing: 18) {
                Button { model.toggle() } label: {
                    ZStack {
                        Circle().fill(model.recording ? Color.mtBad : Look.accent)
                        Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1)
                        Image(systemName: model.recording ? "stop.fill" : "mic.fill").font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                    }
                    .frame(width: 54, height: 54)
                    .shadow(color: (model.recording ? Color.mtBad : Look.accent).opacity(0.35), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .disabled(model.finishing || model.busy)
                .accessibilityLabel(model.recording ? "Finish dictation" : "Start dictation")
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.recording ? "Listening… \(formatDuration(model.seconds))" : (model.finishing ? "Finishing…" : "Talk instead of type, in any app"))
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(Look.ink).monospacedDigit()
                    HStack(spacing: 6) {
                        Keycap(text: "🌐 Globe"); Text("start and finish").font(.system(size: 12)).foregroundStyle(Look.muted)
                        Keycap(text: "esc").padding(.leading, 6); Text("cancel").font(.system(size: 12)).foregroundStyle(Look.muted)
                    }
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 8) {
                    Button { model.page = .models } label: {
                        HStack(spacing: 8) {
                            ModelMark(model: SpeechCatalog.model(for: model.mode), size: 22)
                            Text(SpeechCatalog.model(for: model.mode).name).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Look.ink)
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Look.muted)
                        }
                        .padding(.leading, 4).padding(.trailing, 10).frame(height: 30)
                        .background(Pill().fill(Look.fill))
                    }
                    .buttonStyle(.plain).help("Change the speech model")
                    HStack(spacing: 14) {
                        Toggle("Type as I speak", isOn: $model.liveInsertion)
                        Toggle("Clean up locally", isOn: $model.cleanupEnabled).help("Removes fillers and spoken corrections with a local model in Ollama.")
                    }
                    .toggleStyle(.checkbox).font(.system(size: 12))
                }
            }
        }
        .onChange(of: model.liveInsertion) { _, _ in model.persistPreferences() }
        .onChange(of: model.cleanupEnabled) { _, _ in model.persistPreferences() }
    }

    private var list: some View {
        Card(padding: 6) {
            if entries.isEmpty {
                EmptyState(symbol: "waveform", title: model.search.isEmpty ? "Nothing yet" : "No matches",
                           message: model.search.isEmpty ? "Your dictations land here, so nothing you say is ever lost." : "Try other words.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(entries) { entry in
                            RowButton(selected: model.selection == entry.id, action: { model.selection = entry.id }) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.text.isEmpty ? "Recording to recover" : entry.text)
                                        .font(.system(size: 13, weight: .medium)).foregroundStyle(entry.text.isEmpty ? Look.muted : Look.ink).lineLimit(2)
                                    HStack(spacing: 6) {
                                        Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                        Text("·"); Text(formatDuration(entry.duration))
                                        if !entry.destination.isEmpty { Text("·"); Text(entry.destination).lineLimit(1) }
                                    }
                                    .font(.system(size: 11)).foregroundStyle(Look.muted)
                                }
                            }
                        }
                    }
                    .padding(2)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder private var detail: some View {
        if let entry = library.history.first(where: { $0.id == model.selection }) ?? (model.selection == nil ? entries.first : nil) {
            Card(padding: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        StatusPill(ok: entry.status.hasPrefix("Failed") || entry.status.contains("retry") ? false : true, text: entry.status)
                        Spacer()
                        SoftButton(title: "Copy", symbol: "doc.on.doc") { TextInsertion.copy(entry.text) }.disabled(entry.text.isEmpty)
                        SoftButton(title: "Save as note", symbol: "note.text.badge.plus") {
                            model.selection = library.addNote(body: entry.text, title: String(entry.text.prefix(48))); model.page = .notes
                        }.disabled(entry.text.isEmpty)
                        Menu {
                            if entry.audioFile != nil {
                                Button("Retry transcription") { model.retry(entry) }.disabled(model.busy || model.recording || model.finishing)
                                Button("Play recording") { if let name = entry.audioFile { NSWorkspace.shared.open(JotPaths.recordings.appendingPathComponent(name)) } }
                            }
                            Button("Export…") { saveText(entry.text, name: "Dictation.txt") }
                            Divider()
                            Button("Delete", role: .destructive) { library.removeHistory(entry.id); model.selection = library.history.first?.id }
                        } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28)
                    }
                    .padding(.horizontal, 18).frame(height: 52)
                    Divider().overlay(Look.line)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(entry.text.isEmpty ? "No transcript yet. Retry the saved recording from the menu above." : entry.text)
                                .font(.system(size: 16)).lineSpacing(5).foregroundStyle(entry.text.isEmpty ? Look.muted : Look.ink)
                                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            if let original = entry.originalText, original != entry.text {
                                DisclosureGroup("Before cleanup") {
                                    Text(original).font(.system(size: 13)).foregroundStyle(Look.muted).textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                                }
                                .font(.system(size: 12.5, weight: .medium))
                            }
                            HStack(spacing: 6) {
                                Chip(text: entry.model, symbol: "cpu")
                                Chip(text: formatDuration(entry.duration), symbol: "clock")
                                if entry.finishMS > 0 { Chip(text: "\(Int(entry.finishMS)) ms to finish", symbol: "timer") }
                                if let s = entry.cleanupStatus { Chip(text: s, symbol: "sparkles") }
                            }
                        }
                        .padding(22)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        } else {
            Card { EmptyState(symbol: "text.quote", title: "Pick a dictation", message: "Copy it, save it as a note, or retry a recording that didn't finish.") }
                .frame(maxHeight: .infinity)
        }
    }
}
