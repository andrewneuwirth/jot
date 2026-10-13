import SwiftUI
import AppKit
import AVFoundation
import CoreAudio
import MacToolsKit

private let jotBlue = Color.mtJot
struct MainView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var library: Library
    @State private var folderName = ""
    @State private var addingFolder = false
    @State private var pendingDelete: UUID?
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 200)
            Divider()
            if model.showSettings { SettingsView(model: model, library: library) }
            else if model.section == "Class" { ClassView(model: model, classes: model.classes) }
            else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("Search \(model.section == "Dictation History" ? "history" : "notes")…", text: $model.search).textFieldStyle(.plain)
                        Button { model.newNote() } label: { Image(systemName: "square.and.pencil") }.buttonStyle(.plain).help("New note") }
                        .padding(16)
                    Text(model.section == "Notes" ? "All Notes" : model.section).font(.title2.bold()).padding(.horizontal, 16).padding(.bottom, 12)
                    ScrollView { LazyVStack(spacing: 5) {
                        if model.section == "Dictation History" {
                            ForEach(library.history.filter { model.search.isEmpty || $0.text.localizedCaseInsensitiveContains(model.search) }) { entry in
                                Button { model.selection = entry.id } label: {
                                    VStack(alignment: .leading, spacing: 7) {
                                        if let original = entry.originalText {
                    DisclosureGroup("Original transcription") {
                        Text(original).textSelection(.enabled)
                        Button("Copy original") { TextInsertion.copy(original) }
                    }
                }
                if let status = entry.cleanupStatus { Text("\(status) · \(Int(entry.cleanupMS ?? 0)) ms cleanup").font(.caption).foregroundStyle(.secondary) }
                Text(entry.text.isEmpty ? "Recording to recover" : entry.text).lineLimit(2).font(.body.weight(.medium))
                                        Text(entry.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(model.selection == entry.id ? jotBlue.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 10)).contentShape(RoundedRectangle(cornerRadius: 10))
                                }.buttonStyle(.plain)
                            }
                        } else {
                            ForEach(filteredNotes) { note in
                                Button { model.selection = note.id } label: {
                                    VStack(alignment: .leading, spacing: 7) {
                                        HStack { Text(note.title.isEmpty ? "Untitled note" : note.title).font(.body.weight(.semibold)).lineLimit(1); if note.pinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(jotBlue) } }
                                        Text(note.body.isEmpty ? "A little room for a thought." : note.body).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                                        Text(note.updated.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.tertiary)
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(model.selection == note.id ? jotBlue.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 10)).contentShape(RoundedRectangle(cornerRadius: 10))
                                }.buttonStyle(.plain)
                            }
                        }
                    }.padding(.horizontal, 8) }
                }.frame(width: 290).background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                Divider()
                detail.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.tint(jotBlue).frame(minWidth: 1050, minHeight: 650)
        .background(Color(nsColor: .textBackgroundColor))
        .sheet(isPresented: $addingFolder) {
            VStack(alignment: .leading, spacing: 20) { Text("New folder").font(.title2.bold()); TextField("Folder name", text: $folderName)
                HStack { Button("Cancel") { addingFolder = false }; Spacer(); Button("Create") {
                    let name = folderName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty, !library.folders.contains(name), !["Notes", "Pinned", "Dictation History", "Class"].contains(name) { library.folders.append(name); library.save() }
                    addingFolder = false; folderName = ""
                }.keyboardShortcut(.defaultAction).disabled(folderName.trimmingCharacters(in: .whitespaces).isEmpty) }
            }.padding(24).frame(width: 320)
        }
        .alert("Delete this note?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete", role: .destructive) { library.notes.removeAll { $0.id == pendingDelete }; library.save(); pendingDelete = nil; model.selection = filteredNotes.first?.id }
        } message: { Text("Export anything you want to keep first.") }
    }
    var filteredNotes: [Note] {
        library.notes.filter { note in
            (model.section == "Notes" || (model.section == "Pinned" && note.pinned) || note.folder == model.section) &&
            (model.search.isEmpty || (note.title + " " + note.body).localizedCaseInsensitiveContains(model.search))
        }.sorted { $0.updated > $1.updated }
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) { Image(systemName: "waveform").font(.system(size: 26, weight: .medium)).foregroundStyle(jotBlue); Text("Jot").font(.title2.weight(.semibold)) }.padding(.vertical, 20).padding(.horizontal, 15)
            nav("Notes", "doc.text"); nav("Pinned", "pin"); nav("Dictation History", "clock"); nav("Class", "graduationcap")
            HStack { Text("Folders").foregroundStyle(.secondary); Spacer(); Button { addingFolder = true } label: { Image(systemName: "plus") }.buttonStyle(.plain) }.font(.caption).padding(.horizontal, 14).padding(.top, 24).padding(.bottom, 5)
            ForEach(library.folders, id: \.self) { nav($0, "folder") }
            Spacer()
            Button { model.showSettings = true } label: { Label("Settings", systemImage: "gearshape").frame(maxWidth: .infinity, alignment: .leading).padding(11).background(model.showSettings ? jotBlue.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: MT.Radius.row)).contentShape(RoundedRectangle(cornerRadius: MT.Radius.row)) }.buttonStyle(.plain)
            HStack { Circle().fill(model.recording || model.classes.isActive ? Color.mtBad : (model.ready ? Color.mtGood : Color.mtWarn)).frame(width: 8, height: 8); Text(model.classes.isActive ? "Class · " + formatClock(model.classes.elapsed) : model.state).font(.caption.monospacedDigit()).lineLimit(2) }.padding(12)
        }.padding(10)
        .glassEffect(.regular, in: .rect(cornerRadius: MT.Radius.section))
        .padding(MT.Space.s8)
    }
    func nav(_ title: String, _ icon: String) -> some View {
        Button { model.section = title; model.showSettings = false; model.search = ""; model.selection = title == "Dictation History" ? library.history.first?.id : library.notes.first(where: { title == "Notes" || (title == "Pinned" && $0.pinned) || $0.folder == title })?.id } label: {
            Label(title, systemImage: icon).frame(maxWidth: .infinity, alignment: .leading).padding(11).background(!model.showSettings && model.section == title ? jotBlue.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: MT.Radius.row)).contentShape(RoundedRectangle(cornerRadius: MT.Radius.row))
        }.buttonStyle(.plain)
    }
    @ViewBuilder var detail: some View {
        if model.section == "Dictation History", let entry = library.history.first(where: { $0.id == model.selection }) {
            ScrollView { VStack(alignment: .leading, spacing: 22) {
                HStack { Text("Dictation").font(.largeTitle.bold()); Spacer(); Button("Copy", systemImage: "doc.on.doc") { TextInsertion.copy(entry.text) }; Button("Save as note", systemImage: "square.and.pencil") { model.selection = library.addNote(body: entry.text, title: String(entry.text.prefix(48))); model.section = "Notes" } }
                Text(entry.date.formatted()).foregroundStyle(.secondary)
                Text(entry.text.isEmpty ? "No transcript yet. Retry the saved recording." : entry.text).textSelection(.enabled).font(.system(size: 18)).lineSpacing(6).frame(maxWidth: .infinity, alignment: .leading)
                Divider()
                Label(entry.status, systemImage: "checkmark.circle").font(.callout)
                Text("\(entry.model)\n\(String(format: "%.1f", entry.duration)) seconds recorded · \(Int(entry.finishMS)) ms to finish").font(.caption).foregroundStyle(.secondary)
                if let name = entry.audioFile {
                    HStack { Button("Retry transcription", systemImage: "arrow.clockwise") { model.retry(entry) }.disabled(model.busy || model.recording || model.finishing)
                        Button("Play recording", systemImage: "play") { NSWorkspace.shared.open(JotPaths.recordings.appendingPathComponent(name)) } }
                }
                Button("Export transcript…") { export(entry.text, name: "Dictation.txt") }
            }.padding(32) }
        } else if let index = library.notes.firstIndex(where: { $0.id == model.selection }) {
            let note = library.notes[index]
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 18) {
                    Button { wrap("**") } label: { Image(systemName: "bold") }.help("Bold (Markdown)")
                    Button { wrap("_") } label: { Image(systemName: "italic") }.help("Italic (Markdown)")
                    Button { appendToNote("\n- [ ] ") } label: { Image(systemName: "checklist") }
                    Spacer()
                    Button { library.notes[index].pinned.toggle(); library.save() } label: { Image(systemName: note.pinned ? "pin.fill" : "pin") }
                    Menu { Button("Export…") { export(note.body, name: "\(note.title).md") }; Button("Delete note", role: .destructive) { pendingDelete = note.id } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 25)
                    Button { model.toggle(note: note.id) } label: { Label(model.recording ? "Finish note" : "Record a note", systemImage: model.recording ? "stop.fill" : "mic") }.buttonStyle(.borderedProminent).disabled(model.finishing || model.busy)
                }.buttonStyle(.plain).padding(20)
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Untitled note", text: noteBinding(index, \.title)).font(.system(size: 28, weight: .bold)).textFieldStyle(.plain)
                    HStack { Text(note.updated.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary); Spacer(); Picker("Folder", selection: noteBinding(index, \.folder)) { ForEach(library.folders, id: \.self) { Text($0) } }.labelsHidden().frame(width: 140) }.font(.caption)
                    TextEditor(text: noteBinding(index, \.body)).font(.system(size: 17)).lineSpacing(5).scrollContentBackground(.hidden)
                }.padding(30)
            }
        } else {
            VStack(spacing: 18) { Image(systemName: "waveform").font(.system(size: 48)).foregroundStyle(jotBlue); Text(model.section == "Dictation History" ? "Your words, kept safe." : "A little room for a thought.").font(.title2.weight(.semibold)); Text(model.section == "Dictation History" ? "Your recent dictations will appear here." : "Write a note, or let your voice do the typing.").foregroundStyle(.secondary); Button("New note", systemImage: "square.and.pencil") { model.newNote() }.buttonStyle(.borderedProminent) }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    func noteBinding(_ index: Int, _ path: WritableKeyPath<Note, String>) -> Binding<String> {
        let id = library.notes[index].id
        return Binding(get: { library.notes.first(where: { $0.id == id })?[keyPath: path] ?? "" }, set: { value in
            guard let i = library.notes.firstIndex(where: { $0.id == id }) else { return }; library.notes[i][keyPath: path] = value; library.notes[i].updated = Date(); library.save()
        })
    }
    func appendToNote(_ text: String) { if let i = library.notes.firstIndex(where: { $0.id == model.selection }) { library.notes[i].body += text; library.save() } }
    func wrap(_ marker: String) {
        guard let text = NSApp.keyWindow?.firstResponder as? NSTextView, text.isEditable else { return }
        let range = text.selectedRange(), selected = (text.string as NSString).substring(with: range)
        text.insertText(marker + selected + marker, replacementRange: range)
    }
    func export(_ text: String, name: String) { let p = NSSavePanel(); p.nameFieldStringValue = name; if p.runModal() == .OK, let url = p.url { do { try text.write(to: url, atomically: true, encoding: .utf8) } catch { model.notice = error.localizedDescription } } }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var library: Library
    @State private var page = "Model"
    @State private var login = LoginItem.isEnabled
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings").font(.largeTitle.bold())
                Text("Your voice. Your Mac. Nothing uploaded.").foregroundStyle(.secondary)
                Picker("Settings page", selection: $page) { ForEach(["Model", "Controls", "Privacy", "Vocabulary", "Benchmarks"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented)
                if page == "Model" {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(model.mode == .ultra ? "Parakeet Ultra" : "NVIDIA Parakeet Realtime EOU 120M", systemImage: "waveform").font(.headline)
                        Text(model.mode == .ultra ? "Final text: Ultra · Live preview: \(model.previewStatus)" : "Selected model · English · Core ML / Apple Neural Engine").font(.callout).foregroundStyle(.secondary)
                        Picker("Speech model", selection: $model.mode) { ForEach(SpeechMode.allCases) { Text($0.title).tag($0) } }.disabled(model.busy || model.recording || model.finishing)
                        Text(model.mode == .ultra ? "Apple supplies live words locally. Ultra transcribes the original audio when you stop; it does not rewrite Apple’s text. Both run on this Mac." : "160 ms prioritizes live response. 320 ms gives the model more context. Chunk size is not end-to-end latency.").font(.caption).foregroundStyle(.secondary)
                        HStack { Label(model.state, systemImage: model.ready ? "checkmark.circle.fill" : "arrow.down.circle"); Spacer(); Button(model.ready ? "Check model" : "Download / retry") { Task { await model.loadModel() } }.disabled(model.busy || model.recording || model.finishing) }
                        Toggle("Clean up dictation locally", isOn: $model.cleanupEnabled)
                            .onChange(of: model.cleanupEnabled) { _, _ in model.persistPreferences() }
                        Text("Cleanup: Qwen 3.5 4B · \(model.cleanupStatus)").font(.caption).foregroundStyle(.secondary)
                        Text("Removes fillers and spoken corrections after transcription. Requires Ollama running on this Mac. Original text stays in History; quoted text is kept verbatim.").font(.caption).foregroundStyle(.secondary)
                        Text("Model cache: \(cacheSize) · Warm load: \(Int(model.modelLoadMS)) ms").font(.caption).foregroundStyle(.secondary)
                        HStack { Link("Model card & license", destination: URL(string: model.mode == .ultra ? "https://huggingface.co/FluidInference/parakeet-ultra-coreml" : "https://huggingface.co/FluidInference/parakeet-realtime-eou-120m-coreml")!); Button("Show model files") { NSWorkspace.shared.open(JotPaths.models) } }.font(.caption)
                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                }.padding(16).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                }
                if page == "Controls" {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack { Label(AXIsProcessTrusted() ? "Accessibility enabled" : "Accessibility needed for shortcuts and live text", systemImage: AXIsProcessTrusted() ? "checkmark.circle" : "exclamationmark.circle"); Spacer(); Button("Enable…") { model.requestAccessibility() }; Button("Refresh") { model.refreshPermissions() } }
                        HStack { Label(AVCaptureDevice.authorizationStatus(for: .audio) == .authorized ? "Microphone enabled" : "Microphone permission needed", systemImage: "mic"); Spacer(); Button("Allow microphone") { model.requestMicrophone() } }
                        Text(model.hotkeysReady ? "Globe and mouse shortcut listener is active." : "After enabling Accessibility, click Refresh or restart Jot.").font(.caption).foregroundStyle(.secondary)
                        Picker("Microphone", selection: $model.microphoneID) { Text("System default").tag(UInt32(0)); ForEach(Microphones.list(), id: \.id) { Text($0.name).tag($0.id) } }.disabled(model.recording || model.finishing)
                        LabeledContent("Globe", value: "Tap to start · tap again to finish")
                        LabeledContent("Rear / bottom mouse button", value: "Dictation · ⌃⌘J")
                        LabeledContent("Front / top mouse button", value: "Paste · ⌘V")
                        LabeledContent("Escape", value: "Cancel recording")
                        Toggle("Show words in the text box as I speak", isOn: $model.liveInsertion)
                        Picker("Floating bubble appearance", selection: $model.floatingIconAppearance) {
                            ForEach(FloatingIconAppearance.allCases) { appearance in
                                Text(appearance.title).tag(appearance)
                            }
                        }.pickerStyle(.segmented)
                        Text("Supported editable fields update live. If the app does not expose a safe text field, Jot shows a live preview and pastes into the text box selected when you stop, provided focus stays there during processing.").font(.caption).foregroundStyle(.secondary)
                    }.padding(10)
                }.padding(16).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                }
                if page == "Privacy" {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Open at Login", isOn: $login).onChange(of: login) { _, enabled in
                            if !LoginItem.set(enabled) { model.notice = "macOS didn't allow Open at Login."; login = LoginItem.isEnabled }
                        }
                        Toggle("Keep successful recordings for replay", isOn: $model.keepAudio)
                        Text("Transcripts stay in local history. Failed and interrupted recordings are retained for recovery. Successful audio is removed unless enabled above. No accounts, analytics, or cloud transcription.").font(.caption).foregroundStyle(.secondary)
                        Button("Show local library") { NSWorkspace.shared.open(JotPaths.root) }
                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                }.padding(16).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                }
                if page == "Vocabulary" {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("One explicit spelling rule per line: spoken phrase = desired spelling. These run locally after recognition; they do not train the model.").font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $library.vocabulary).font(.system(.body, design: .monospaced)).frame(height: 100).border(Color.secondary.opacity(0.2))
                        Text("Example: tar's = Tars").font(.caption).foregroundStyle(.secondary)
                    }.padding(10)
                }.padding(16).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                }
                if page == "Benchmarks" {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack { Text("Measured on this Mac").font(.headline); Spacer(); Button("Benchmark audio file…") { model.benchmarkFile() }.disabled(model.busy || model.recording || model.finishing) }
                        Text(SpeechEngine.hardware()).font(.caption).foregroundStyle(.secondary)
                        if !library.history.isEmpty {
                            let timings = library.history.filter { $0.finishMS > 0 }.map(\.finishMS).sorted()
                            if !timings.isEmpty { LabeledContent("Actual dictation finish delay", value: "\(Int(timings[timings.count / 2])) ms median · \(timings.count) runs") }
                        }
                        Text("File benchmarks run faster than real time and exclude model loading. They measure inference, not live microphone-to-text latency. Accuracy is shown only when a reference transcript was supplied.").font(.caption).foregroundStyle(.secondary)
                        if library.benchmarks.isEmpty { Text("No measurements yet. Choose a recording to run a local benchmark.").foregroundStyle(.secondary) }
                        ForEach(library.benchmarks.prefix(12)) { b in
                            VStack(alignment: .leading, spacing: 7) {
                                HStack { Text(b.model).font(.callout.bold()); Spacer(); Text("\(String(format: "%.1f", b.speed))× realtime").foregroundStyle(jotBlue).font(.headline) }
                                Text("\(b.source) · \(b.date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                                Text("\(String(format: "%.2f", b.audioSeconds)) s audio → \(String(format: "%.3f", b.processingSeconds)) s processing · \(Int(b.finalizationMS)) ms flush").font(.caption)
                                if let wer = b.wordErrorRate { Text("Word error rate: \(String(format: "%.1f", wer * 100))% · this clip only").font(.caption) }
                                DisclosureGroup("Transcript") { Text(b.transcript).textSelection(.enabled).font(.callout).frame(maxWidth: .infinity, alignment: .leading) }
                            }.padding(12).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }.padding(10)
                }.padding(16).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                }
                if !model.notice.isEmpty { Text(model.notice).foregroundStyle(.secondary).textSelection(.enabled) }
                if let error = library.error { Text(error).foregroundStyle(Color.mtBad).textSelection(.enabled) }
                Text("Jot 0.1 · Open-source app · Local inference powered by FluidAudio").font(.caption).foregroundStyle(.tertiary)
            }.padding(32).frame(maxWidth: 900)
        }
        .onChange(of: model.mode) { _, _ in Task { await model.loadModel() } }
        .onChange(of: model.liveInsertion) { _, _ in model.persistPreferences() }
        .onChange(of: model.keepAudio) { _, _ in model.persistPreferences() }
        .onChange(of: model.microphoneID) { _, _ in model.persistPreferences() }
        .onChange(of: library.vocabulary) { _, _ in library.save() }
    }
    var cacheSize: String {
        let enumerator = FileManager.default.enumerator(at: JotPaths.models, includingPropertiesForKeys: [.fileSizeKey])
        var bytes: Int64 = 0
        while let url = enumerator?.nextObject() as? URL { bytes += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

enum Microphones {
    struct Device { var id: AudioDeviceID; var name: String }
    static func list() -> [Device] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / 4)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            var bytes: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &bytes) == noErr, bytes > 0 else { return nil }
            var nameAddress = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var name: CFString = "Microphone" as CFString; var nameSize = UInt32(MemoryLayout<CFString>.size)
            _ = AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &name)
            return Device(id: id, name: name as String)
        }
    }
}

struct RecordingBubble: View {
    @ObservedObject var model: AppModel
    var open: (String) -> Void
    var settings: () -> Void
    var hide: () -> Void
    var drag: (CGSize, Bool) -> Void
    private var expanded: Bool { model.recording || model.finishing }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    private var darkIcon: Bool {
        switch model.floatingIconAppearance {
        case .system: colorScheme == .dark
        case .light: false
        case .dark: true
        }
    }
    private var surfaceColor: Color {
        darkIcon ? Color(red: 0.12, green: 0.13, blue: 0.15) : .white
    }
    var body: some View {
        ZStack {
            if expanded {
                RoundedRectangle(cornerRadius: 18).fill(surfaceColor)
                    .shadow(color: Color(red: 0.16, green: 0.21, blue: 0.29).opacity(0.10), radius: 5, y: 2)
                RecordingView(model: model).environment(\.colorScheme, darkIcon ? .dark : .light).transition(.opacity)
            } else {
                Circle().fill(surfaceColor)
                    .shadow(color: Color(red: 0.16, green: 0.21, blue: 0.29).opacity(0.12), radius: 4, y: 2)
                Image(systemName: "waveform")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(darkIcon ? AnyShapeStyle(.white) : AnyShapeStyle(LinearGradient(colors: [Color(red: 0.25, green: 0.29, blue: 0.35), Color(red: 0.40, green: 0.45, blue: 0.52)], startPoint: .top, endPoint: .bottom)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Circle())
                    .onTapGesture { model.toggle() }
                    .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .global)
                        .onChanged { drag($0.translation, false) }
                        .onEnded { drag($0.translation, true) })
                    .help("Start dictation · drag to move")
                    .accessibilityLabel("Start dictation")
                    .accessibilityAddTraits(.isButton)
                    .transition(.opacity)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(4)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.26), value: expanded)
            .contextMenu {
                Button("Open Jot") { open("Notes") }
                Button("History") { open("Dictation History") }
                Button("Settings…", action: settings)
                Button {
                    model.floatingIconAppearance = .system
                } label: {
                    if model.floatingIconAppearance == .system { Label("System", systemImage: "checkmark") }
                    else { Text("System") }
                }
                Button {
                    model.floatingIconAppearance = .light
                } label: {
                    if model.floatingIconAppearance == .light { Label("Light", systemImage: "checkmark") }
                    else { Text("Light") }
                }
                Button {
                    model.floatingIconAppearance = .dark
                } label: {
                    if model.floatingIconAppearance == .dark { Label("Dark", systemImage: "checkmark") }
                    else { Text("Dark") }
                }
                Divider()
                Button("Hide bubble", action: hide).disabled(expanded)
            }
    }
}

struct RecordingView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                HStack(spacing: 2) { ForEach(0..<7) { i in
                    RoundedRectangle(cornerRadius: 2).fill(LinearGradient(colors: [Color(red: 0.35, green: 0.72, blue: 1), jotBlue], startPoint: .top, endPoint: .bottom))
                        .frame(width: 3, height: CGFloat(4 + model.level * Float(7 + i * 3)))
                } }.frame(width: 34, height: 22)
                Text(model.recording ? String(format: "%d:%02d", Int(model.seconds) / 60, Int(model.seconds) % 60) : "Processing")
                    .font(.system(size: 11, weight: .medium)).monospacedDigit().lineLimit(1)
                Spacer(minLength: 0)
                if model.recording {
                    Button { model.stop() } label: { Image(systemName: "stop.fill").font(.system(size: 9)).foregroundStyle(.white).frame(width: 24, height: 24).background(LinearGradient(colors: [Color(red: 0.26, green: 0.61, blue: 1), jotBlue], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle()).overlay(Circle().strokeBorder(.white.opacity(0.22), lineWidth: 0.7)).shadow(color: jotBlue.opacity(0.45), radius: 7) }.help("Finish dictation")
                } else if model.finishing { ProcessingGlow().frame(width: 24, height: 24) }
                else {
                    if !model.transcript.isEmpty { Button { TextInsertion.copy(model.transcript) } label: { Image(systemName: "doc.on.doc") }.help("Copy transcript") }
                    Button { model.showOverlay = false; model.overlayChanged?() } label: { Image(systemName: "xmark") }.help("Dismiss")
                }
            }.buttonStyle(.plain)
            if model.transcript.isEmpty {
                Text(model.recording ? "Listening" : (model.finishing ? "Finishing" : ""))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                ScrollView(.vertical) {
                    (Text(model.transcript).foregroundColor(.primary) + Text(model.recording ? " ▏" : "").foregroundColor(jotBlue)).font(.system(size: 11))
                        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                }.defaultScrollAnchor(.bottom).frame(height: OverlayLayout.textHeight(model.transcript))
            }
        }.padding(12).frame(width: 228, height: OverlayLayout.height(model.transcript) - 8).foregroundStyle(.primary)
    }
}

private struct ProcessingGlow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let angle = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.1) / 1.1 * 360
            ZStack {
                Circle().fill(jotBlue.opacity(0.12))
                Circle().stroke(jotBlue.opacity(0.18), lineWidth: 2)
                Circle().trim(from: 0.08, to: 0.88)
                    .stroke(AngularGradient(colors: [jotBlue.opacity(0.05), jotBlue, .cyan, .white], center: .center), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(angle))
                    .shadow(color: jotBlue.opacity(0.8), radius: 5)
            }.padding(2)
        }.accessibilityLabel("Processing dictation")
    }
}

struct ClassView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var classes: ClassRecorder
    @State private var selected: UUID?
    @State private var confirmStop = false
    @State private var confirmDelete: UUID?
    var shown: ClassSession? {
        if let a = classes.active { return classes.sessions.first { $0.id == a.id } ?? a }
        return classes.sessions.first { $0.id == selected } ?? classes.sessions.first
    }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Class").font(.title2.bold()).padding(16)
                ScrollView { LazyVStack(spacing: 5) {
                    ForEach(classes.sessions) { s in
                        Button { selected = s.id } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(s.title).font(.body.weight(.semibold)).lineLimit(1)
                                Text("\(formatClock(s.id == classes.active?.id ? classes.elapsed : s.seconds)) · \(s.status)").font(.caption.monospacedDigit()).foregroundStyle(s.status == "Recording" ? .red : .secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            .background(shown?.id == s.id ? jotBlue.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 10)).contentShape(RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 8) }
            }.frame(width: 290).background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
            Divider()
            VStack(alignment: .leading, spacing: 0) { controls; Divider(); transcript }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .confirmationDialog("Stop the class recording?", isPresented: $confirmStop) {
            Button("Stop recording", role: .destructive) { Task { await classes.stop() } }
            Button("Keep recording", role: .cancel) {}
        } message: { Text("Everything so far is already saved. Stopping ends this session.") }
        .alert("Delete this recording and its audio?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button("Cancel", role: .cancel) { confirmDelete = nil }
            Button("Move to Trash", role: .destructive) { if let id = confirmDelete { classes.delete(id) }; confirmDelete = nil }
        }
    }
    var controls: some View {
        VStack(spacing: 14) {
            Text(formatClock(classes.isActive ? classes.elapsed : (shown?.seconds ?? 0))).font(.system(size: 64, weight: .light, design: .rounded).monospacedDigit())
            if classes.isActive {
                HStack(spacing: 10) {
                    Circle().fill(.red).frame(width: 10, height: 10)
                    Text("Recording — saved to disk as it goes").foregroundStyle(.secondary)
                    ProgressView(value: Double(classes.level)).frame(width: 80)
                }.font(.callout)
                Button { confirmStop = true } label: { Label("Stop", systemImage: "stop.fill").frame(width: 140) }.controlSize(.large).buttonStyle(.borderedProminent).tint(.red)
            } else {
                Button { classes.start(microphoneID: model.microphoneID) } label: { Label("Record class", systemImage: "record.circle").frame(width: 160) }.controlSize(.large).buttonStyle(.borderedProminent).tint(.red)
            }
            if !classes.notice.isEmpty { Text(classes.notice).font(.callout).foregroundStyle(Color.mtWarn) }
        }.padding(24).frame(maxWidth: .infinity)
    }
    @ViewBuilder var transcript: some View {
        if let s = shown {
            let text = classes.isActive && classes.active?.id == s.id ? classes.liveText : s.transcript
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(s.title).font(.headline).lineLimit(1)
                    Spacer()
                    if !classes.isActive {
                        Button("Copy", systemImage: "doc.on.doc") { TextInsertion.copy(text) }
                        Button("Export…", systemImage: "square.and.arrow.up") { export(text, name: s.title + ".txt") }
                        Button("Re-transcribe from audio", systemImage: "arrow.clockwise") { classes.retranscribe(s.id, engine: model.speech, mode: model.mode) }.disabled(classes.retranscribing || !model.ready || s.segments.isEmpty)
                        Button("Show audio", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([ClassPaths.directory(s)]) }
                        Button(role: .destructive) { confirmDelete = s.id } label: { Image(systemName: "trash") }
                    }
                }.padding(.horizontal, 20).padding(.vertical, 10)
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(text.isEmpty ? (classes.isActive ? "Listening… words appear here as they are spoken." : "No transcript. The audio is saved — use Re-transcribe from audio.") : text)
                            .textSelection(.enabled).font(.system(size: 17)).lineSpacing(6).frame(maxWidth: .infinity, alignment: .leading).padding(24)
                        Color.clear.frame(height: 1).id("end")
                    }.onChange(of: text) { if classes.isActive { proxy.scrollTo("end") } }
                }
            }
        } else {
            VStack(spacing: 14) { Image(systemName: "graduationcap").font(.system(size: 44)).foregroundStyle(jotBlue); Text("Press Record class and leave it running.").font(.title3.weight(.semibold)); Text("Raw transcript, no cleanup. Audio is written to disk continuously.").foregroundStyle(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    func export(_ text: String, name: String) { let p = NSSavePanel(); p.nameFieldStringValue = name; if p.runModal() == .OK, let url = p.url { do { try text.write(to: url, atomically: true, encoding: .utf8) } catch { classes.notice = error.localizedDescription } } }
}
