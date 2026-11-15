import SwiftUI
import AppKit
import AVFoundation
import MacToolsKit

struct SettingsPage: View {
    @ObservedObject var model: AppModel
    @AppStorage("bubbleVisible") private var showBubble = true
    @ObservedObject var library: Library
    @State private var login = LoginItem.isEnabled
    var body: some View {
        PageHeader(title: "Settings") {
            SoftButton(title: "Show walkthrough", symbol: "sparkles") { model.showOnboarding = true }
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                group("Permissions", "Granted to Jot in System Settings › Privacy & Security.") {
                    // Re-reads the live state every couple of seconds while the page is open.
                    TimelineView(.periodic(from: .now, by: 2)) { _ in PermissionRows(model: model) }
                }
                group("Shortcuts", nil) {
                    SettingRow(title: "Start and finish dictation", detail: model.shortcut.isGlobe
                               ? "Tap the Globe (fn) key. Set System Settings › Keyboard › “Press 🌐 key to” to Do Nothing."
                               : "\(model.shortcut.verb) \(model.shortcut.name) in any app.") {
                        ShortcutRecorder(model: model)
                    }
                    SettingRow(title: "Cancel", detail: "While recording.") { Keycap(text: "esc") }
                    SettingRow(title: "Hold Space to talk", detail: "In the apps below: hold Space for a moment, release to insert the raw transcript. A tap still types a space.") {
                        Toggle("", isOn: $model.spaceHold).labelsHidden().toggleStyle(.switch)
                    }
                    if model.spaceHold {
                        TextEditor(text: $model.spaceHoldApps).font(.system(size: 12, design: .monospaced)).frame(height: 96)
                            .scrollContentBackground(.hidden).padding(6)
                            .background(RoundedRectangle(cornerRadius: MT.Radius.control).fill(Look.fill))
                        HStack { Text("One bundle ID per line.").font(.system(size: 11)).foregroundStyle(Look.muted); Spacer(); SoftButton(title: "Add app…", symbol: "plus") { model.addSpaceHoldApp() } }
                    }
                }
                group("Dictation", nil) {
                    SettingRow(title: "Microphone", detail: nil) {
                        Picker("", selection: $model.microphoneID) { Text("System default").tag(UInt32(0)); ForEach(Microphones.list(), id: \.id) { Text($0.name).tag($0.id) } }
                            .labelsHidden().frame(width: 220).disabled(model.recording || model.finishing)
                    }
                    SettingRow(title: "Type as I speak", detail: "Words appear in the text box live where the app allows it; otherwise Jot pastes when you stop.") {
                        Toggle("", isOn: $model.liveInsertion).labelsHidden().toggleStyle(.switch)
                    }
                    SettingRow(title: "Floating bubble", detail: "The small button in the corner of the screen. It still appears while you dictate.") {
                        HStack(spacing: 12) {
                            if showBubble {
                                Picker("", selection: $model.floatingIconAppearance) { ForEach(FloatingIconAppearance.allCases) { Text($0.title).tag($0) } }
                                    .labelsHidden().pickerStyle(.segmented).frame(width: 200)
                            }
                            Toggle("Show", isOn: $showBubble).toggleStyle(.switch).labelsHidden()
                                .onChange(of: showBubble) { _, _ in model.overlayChanged?() }
                        }
                    }
                    SettingRow(title: "Spelling rules", detail: "One per line: spoken phrase = spelling. Example: eye phone = iPhone") { EmptyView() }
                    TextEditor(text: $library.vocabulary).font(.system(size: 12, design: .monospaced)).frame(height: 70)
                        .scrollContentBackground(.hidden).padding(6)
                        .background(RoundedRectangle(cornerRadius: MT.Radius.control).fill(Look.fill))
                }
                group("Privacy and storage", "Everything stays on this Mac. No account, analytics or cloud transcription.") {
                    SettingRow(title: "Open at Login", detail: nil) {
                        Toggle("", isOn: $login).labelsHidden().toggleStyle(.switch).onChange(of: login) { _, on in
                            if !LoginItem.set(on) { model.notice = "macOS didn't allow Open at Login."; login = LoginItem.isEnabled }
                        }
                    }
                    SettingRow(title: "Keep audio of successful dictations", detail: "Failed and cancelled recordings are always kept so you can retry them.") {
                        Toggle("", isOn: $model.keepAudio).labelsHidden().toggleStyle(.switch)
                    }
                    SettingRow(title: "Your library", detail: "~/Library/Application Support/Jot: notes, history, recordings and models.") {
                        SoftButton(title: "Show in Finder", symbol: "folder") { NSWorkspace.shared.open(JotPaths.root) }
                    }
                }
                group("Benchmarks", "Measured on this Mac. File benchmarks exclude model loading and aren't live microphone latency.") {
                    SettingRow(title: SpeechEngine.hardware(), detail: medianFinish) {
                        SoftButton(title: "Benchmark a file…", symbol: "speedometer", disabled: model.busy || model.recording || model.finishing) { model.benchmarkFile() }
                    }
                    ForEach(library.benchmarks.prefix(6)) { b in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(b.model).font(.system(size: 12, weight: .medium))
                                Text("\(b.source) · \(String(format: "%.1f", b.audioSeconds)) s audio\(b.wordErrorRate.map { " · WER \(String(format: "%.1f", $0 * 100))%" } ?? "")").font(.system(size: 11)).foregroundStyle(Look.muted)
                            }
                            Spacer()
                            Text("\(String(format: "%.1f", b.speed))× realtime").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Look.accent)
                        }
                    }
                }
                Text("Jot · open source from newi tools · local inference by FluidAudio").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            .padding([.horizontal, .bottom], 22)
            .frame(maxWidth: 820, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: model.liveInsertion) { _, _ in model.persistPreferences() }
        .onChange(of: model.keepAudio) { _, _ in model.persistPreferences() }
        .onChange(of: model.microphoneID) { _, _ in model.persistPreferences() }
        .onChange(of: library.vocabulary) { _, _ in library.save() }
    }

    private var medianFinish: String? {
        let timings = library.history.filter { $0.finishMS > 0 }.map(\.finishMS).sorted()
        return timings.isEmpty ? nil : "Dictation finish delay: \(Int(timings[timings.count / 2])) ms median over \(timings.count) runs"
    }

    private func group<Content: View>(_ title: String, _ detail: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Look.ink).accessibilityAddTraits(.isHeader)
                if let detail { Text(detail).font(.system(size: 12)).foregroundStyle(Look.muted) }
            }
            Card(padding: 14) { VStack(alignment: .leading, spacing: 4) { content() } }
        }
    }
}

/// Microphone, Accessibility and call audio, each with its live state and the button that fixes it.
struct PermissionRows: View {
    @ObservedObject var model: AppModel
    var body: some View {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        let ax = AXIsProcessTrusted()
        VStack(alignment: .leading, spacing: 4) {
            SettingRow(title: "Microphone", detail: "To hear you. Required.") {
                HStack(spacing: 8) {
                    StatusPill(ok: mic == .authorized, text: mic == .authorized ? "Allowed" : "Not yet")
                    if mic != .authorized {
                        SoftButton(title: mic == .notDetermined ? "Allow" : "Open Settings", symbol: "mic") {
                            if mic == .notDetermined { model.requestMicrophone() }
                            else { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!) }
                        }
                    }
                }
            }
            SettingRow(title: "Accessibility", detail: "For the \(model.shortcut.name) shortcut and typing into other apps.") {
                HStack(spacing: 8) {
                    StatusPill(ok: ax, text: ax ? (model.hotkeysReady ? "Allowed" : "Allowed · restart Jot") : "Not yet")
                    if !ax { SoftButton(title: "Open Settings", symbol: "hand.raised") { model.requestAccessibility() } }
                    else if !model.hotkeysReady { SoftButton(title: "Retry", symbol: "arrow.clockwise") { model.refreshPermissions() } }
                }
            }
            SettingRow(title: "System audio", detail: "Only for Record Call. macOS asks the first time you record one.") {
                HStack(spacing: 8) {
                    StatusPill(ok: nil, text: "Asked when needed")
                    SoftButton(title: "Open Settings", symbol: "speaker.wave.2") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!)
                    }
                }
            }
        }
    }
}

/// The dictation shortcut as keycaps. Record listens for the next key combination, or a lone tap of a modifier
/// (fn picks Globe); esc stops listening.
struct ShortcutRecorder: View {
    @ObservedObject var model: AppModel
    @State private var listening = false
    @State private var monitor: Any?
    @State private var tap = ModifierTap()
    @State private var message: String?
    @State private var rejected = false
    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 8) {
                if listening {
                    Text("Press the keys…").font(.system(size: 12, weight: .medium)).foregroundStyle(Look.accent).lineLimit(1).fixedSize()
                    SoftButton(title: "Cancel", symbol: "xmark") { stop() }
                } else {
                    HStack(spacing: 3) { ForEach(model.shortcut.keys, id: \.self) { Keycap(text: $0) } }.fixedSize()
                        .accessibilityElement().accessibilityLabel("Shortcut: \(model.shortcut.name)")
                    SoftButton(title: "Record", symbol: "record.circle") { start() }
                    if !model.shortcut.isGlobe { SoftButton(title: "Use Globe", symbol: "globe") { model.setShortcut(.globe); message = nil } }
                }
            }
            if let message {
                Text(message).font(.system(size: 11)).foregroundStyle(rejected ? Color.mtBad : Color.mtWarn)
                    .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 280, alignment: .trailing)
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        message = nil; tap = ModifierTap(); listening = true; model.recordingShortcut = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in handle(event); return nil }
    }
    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil; listening = false; model.recordingShortcut = false
    }
    private func handle(_ event: NSEvent) {
        let code = Int64(event.keyCode), flags = event.cgEvent?.flags ?? []
        if event.type == .keyDown {
            tap.key()
            let modifiers = flags.intersection(DictationShortcut.modifierMask)
            if code == 53 && modifiers.isEmpty { return stop() }
            offer(.combo(key: code, modifiers: modifiers))
        } else if let info = DictationShortcut.modifierKeys[code] {
            let held = flags.intersection(DictationShortcut.modifierMask.union(.maskSecondaryFn))
            if tap.flags(code: code, down: flags.contains(info.flag), alone: held == info.flag) != nil { offer(code == 63 ? .globe : .modifier(code)) }
        }
    }
    private func offer(_ shortcut: DictationShortcut) {
        if let reason = shortcut.rejection { message = reason; rejected = true; return }   // keep listening
        model.setShortcut(shortcut); message = shortcut.warning; rejected = false; stop()
    }
}
