import SwiftUI
import AppKit
import AVFoundation
import CoreAudio
import ServiceManagement

private let jotBlue = Color(red: 0.20, green: 0.55, blue: 0.98)
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
                                        Text(entry.text.isEmpty ? "Recording to recover" : entry.text).lineLimit(2).font(.body.weight(.medium))
                                        Text(entry.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(model.selection == entry.id ? jotBlue.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 10))
                                }.buttonStyle(.plain)
                            }
                        } else {
                            ForEach(filteredNotes) { note in
                                Button { model.selection = note.id } label: {
                                    VStack(alignment: .leading, spacing: 7) {
                                        HStack { Text(note.title.isEmpty ? "Untitled note" : note.title).font(.body.weight(.semibold)).lineLimit(1); if note.pinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(jotBlue) } }
                                        Text(note.body.isEmpty ? "A little room for a thought." : note.body).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                                        Text(note.updated.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.tertiary)
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(model.selection == note.id ? jotBlue.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 10))
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
                    if !name.isEmpty, !library.folders.contains(name), !["Notes", "Pinned", "Dictation History"].contains(name) { library.folders.append(name); library.save() }
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
            nav("Notes", "doc.text"); nav("Pinned", "pin"); nav("Dictation History", "clock")
            HStack { Text("Folders").foregroundStyle(.secondary); Spacer(); Button { addingFolder = true } label: { Image(systemName: "plus") }.buttonStyle(.plain) }.font(.caption).padding(.horizontal, 14).padding(.top, 24).padding(.bottom, 5)
            ForEach(library.folders, id: \.self) { nav($0, "folder") }
            Spacer()
            Button { model.showSettings = true } label: { Label("Settings", systemImage: "gearshape").frame(maxWidth: .infinity, alignment: .leading).padding(11).background(model.showSettings ? jotBlue.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 9)) }.buttonStyle(.plain)
            HStack { Circle().fill(model.recording ? .red : (model.ready ? .green : .orange)).frame(width: 8, height: 8); Text(model.state).font(.caption).lineLimit(2) }.padding(12)
        }.padding(10).background(.regularMaterial)
    }
    func nav(_ title: String, _ icon: String) -> some View {
        Button { model.section = title; model.showSettings = false; model.search = ""; model.selection = title == "Dictation History" ? library.history.first?.id : library.notes.first(where: { title == "Notes" || (title == "Pinned" && $0.pinned) || $0.folder == title })?.id } label: {
            Label(title, systemImage: icon).frame(maxWidth: .infinity, alignment: .leading).padding(11).background(!model.showSettings && model.section == title ? jotBlue.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 9))
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
    @State private var login = SMAppService.mainApp.status == .enabled
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
                        Text("Supported editable fields update live. If the app does not expose a safe text field, Jot shows a live preview and pastes the finished transcript when focus is unchanged.").font(.caption).foregroundStyle(.secondary)
                    }.padding(10)
                }.padding(16).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                }
                if page == "Privacy" {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Launch Jot at login", isOn: $login).onChange(of: login) { _, enabled in
                            do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch { model.notice = error.localizedDescription; login = SMAppService.mainApp.status == .enabled }
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
                if let error = library.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
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

struct RecordingView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                HStack(spacing: 2) { ForEach(0..<7) { i in
                    RoundedRectangle(cornerRadius: 2).fill(LinearGradient(colors: [Color(red: 0.35, green: 0.72, blue: 1), jotBlue], startPoint: .top, endPoint: .bottom))
                        .frame(width: 3, height: CGFloat(4 + model.level * Float(7 + i * 3)))
                } }.frame(width: 34, height: 22)
                Text(model.recording ? String(format: "%d:%02d", Int(model.seconds) / 60, Int(model.seconds) % 60) : model.state)
                    .font(.system(size: 11, weight: .medium)).monospacedDigit().lineLimit(1)
                Spacer(minLength: 0)
                if model.recording {
                    Button { model.stop() } label: { Image(systemName: "stop.fill").font(.system(size: 9)).frame(width: 24, height: 24).background(LinearGradient(colors: [Color(red: 0.26, green: 0.61, blue: 1), jotBlue], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle()).overlay(Circle().strokeBorder(.white.opacity(0.22), lineWidth: 0.7)).shadow(color: jotBlue.opacity(0.45), radius: 7) }.help("Finish dictation")
                } else if model.finishing { ProgressView().controlSize(.mini) }
                else {
                    if !model.transcript.isEmpty { Button { TextInsertion.copy(model.transcript) } label: { Image(systemName: "doc.on.doc") }.help("Copy transcript") }
                    Button { model.showOverlay = false; model.overlayChanged?() } label: { Image(systemName: "xmark") }.help("Dismiss")
                }
            }.buttonStyle(.plain)
            if model.transcript.isEmpty {
                Text(model.recording ? "Listening" : (model.finishing ? "Finishing" : ""))
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.8))
            } else {
                ScrollView(.vertical) {
                    (Text(model.transcript).foregroundColor(.white.opacity(0.94)) + Text(model.recording ? " ▏" : "").foregroundColor(jotBlue)).font(.system(size: 11))
                        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                }.defaultScrollAnchor(.bottom).frame(height: OverlayLayout.textHeight(model.transcript))
            }
        }.padding(12).frame(width: 228, height: OverlayLayout.height(model.transcript) - 8).foregroundStyle(.white)
            .background(LinearGradient(colors: [Color(red: 0.08, green: 0.12, blue: 0.18), Color(red: 0.045, green: 0.075, blue: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(jotBlue.opacity(0.22))).padding(4)
    }
}
