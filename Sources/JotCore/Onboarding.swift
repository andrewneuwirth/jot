import SwiftUI
import AppKit
import MacToolsKit

/// First-launch walkthrough: welcome, permissions, a model, the shortcut, done. Shown once to new users
/// (no settings, no library) and again from Settings.
struct Onboarding: View {
    @ObservedObject var model: AppModel
    @ObservedObject var models: ModelStore
    @State var step = 0
    private let steps = 5

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: welcome
                case 1: permissions
                case 2: pickModel
                case 3: shortcut
                default: done
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 40).padding(.top, 36)
            Divider().overlay(Look.line)
            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<steps, id: \.self) { i in
                        Capsule().fill(i == step ? Look.accent : Look.line).frame(width: i == step ? 18 : 6, height: 6)
                    }
                }
                .accessibilityElement().accessibilityLabel("Step \(step + 1) of \(steps)")
                Spacer()
                if step > 0 && step < steps - 1 { Button("Back") { step -= 1 }.buttonStyle(.plain).foregroundStyle(Look.muted).padding(.trailing, 10) }
                if step < steps - 1 {
                    PrimaryButton(title: step == 0 ? "Get started" : "Continue", symbol: "arrow.right") { step += 1 }
                } else {
                    PrimaryButton(title: "Start using Jot", symbol: "checkmark") { model.finishOnboarding() }
                }
            }
            .padding(.horizontal, 28).frame(height: 64)
        }
        .frame(width: 640, height: 540)
        .background(Look.panel)
        .tint(Look.accent)
    }

    private func title(_ text: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text).font(.system(size: 24, weight: .bold)).foregroundStyle(Look.ink)
            Text(detail).font(.system(size: 13.5)).foregroundStyle(Look.muted).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 20)
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            RoundedRectangle(cornerRadius: 20).fill(LinearGradient(colors: [Color(hex: 0x5aa7ff), Look.accent], startPoint: .top, endPoint: .bottom))
                .frame(width: 84, height: 84)
                .overlay(Image(systemName: "waveform").font(.system(size: 38, weight: .bold)).foregroundStyle(.white))
                .shadow(color: Look.accent.opacity(0.35), radius: 14, y: 6)
                .padding(.top, 10)
            VStack(spacing: 6) {
                Text("Welcome to Jot").font(.system(size: 28, weight: .bold)).foregroundStyle(Look.ink)
                Text("Talk instead of type. Everything runs on this Mac.").font(.system(size: 14)).foregroundStyle(Look.muted)
            }
            VStack(alignment: .leading, spacing: 14) {
                feature("waveform", "Dictate into any app", "\(model.shortcut.verb) \(model.shortcut.isGlobe ? "the Globe key" : model.shortcut.name), talk, \(model.shortcut.verb.lowercased()) again. Words land where your cursor is.")
                feature("note.text", "Notes", "Write, or dictate straight into a note.")
                feature("graduationcap", "Record classes and calls", "Hours of audio saved as it goes, with a live transcript.")
            }
            .padding(.top, 10)
            .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(Look.accent)
                .frame(width: 34, height: 34).background(RoundedRectangle(cornerRadius: 9).fill(Look.selected))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Look.ink)
                Text(detail).font(.system(size: 12.5)).foregroundStyle(Look.muted)
            }
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("A few permissions", "Jot asks only for what it uses. You can change these any time in Settings.")
            Card(padding: 14) { TimelineView(.periodic(from: .now, by: 1)) { _ in PermissionRows(model: model) } }
        }
    }

    private var pickModel: some View {
        let recommended = SpeechCatalog.model(for: .ultra), small = SpeechCatalog.model(for: .fast)
        return VStack(alignment: .leading, spacing: 12) {
            title("Pick a speech model", "Downloaded once from Hugging Face, then everything is transcribed on this Mac.")
            choice(recommended)
            choice(small)
            Text("More models, including 25 languages, are on the Models page.").font(.system(size: 12)).foregroundStyle(Look.muted)
        }
    }

    private func choice(_ item: SpeechModel) -> some View {
        Card(padding: 14) {
            HStack(spacing: 12) {
                ModelMark(model: item, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Look.ink)
                        if let badge = item.badge { Chip(text: badge, tint: badge == "Recommended" ? Look.accent : nil) }
                    }
                    Text("\(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file)) · \(item.languages)").font(.system(size: 12)).foregroundStyle(Look.muted)
                }
                Spacer()
                switch models.state(item) {
                case .downloading(let p):
                    ProgressBar(value: p).frame(width: 90)
                    Text("\(Int(p * 100))%").font(.system(size: 12, weight: .medium)).monospacedDigit().frame(width: 36)
                case .ready:
                    if item.mode == model.mode { StatusPill(ok: true, text: "Ready") }
                    else { SoftButton(title: "Use", symbol: "checkmark") { if let m = item.mode { model.use(m) } } }
                default:
                    PrimaryButton(title: "Download", symbol: "arrow.down.circle.fill") {
                        models.download(item) { if let m = item.mode { model.use(m) } }
                    }
                }
            }
        }
    }

    private var shortcut: some View {
        let key = model.shortcut, verb = key.verb
        return VStack(alignment: .leading, spacing: 0) {
            title("Your dictation shortcut", "Works in any app once Accessibility is allowed. Globe (fn) is the default; record another if your keyboard has no Globe key.")
            Card {
                HStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Text(key.isGlobe ? "🌐" : key.keys.joined()).font(.system(size: key.isGlobe ? 30 : 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(Look.ink).lineLimit(1).fixedSize()
                            .padding(.horizontal, 14).frame(minWidth: 74, minHeight: 64)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Look.card))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Look.line))
                            .shadow(color: .black.opacity(0.1), radius: 0, y: 2)
                        Text(key.isGlobe ? "Globe / fn" : (verb == "Tap" ? "Tap on its own" : "Press together")).font(.system(size: 11)).foregroundStyle(Look.muted)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Label("\(verb) to start talking", systemImage: "1.circle.fill")
                        Label("\(verb) again to finish: the text is typed for you", systemImage: "2.circle.fill")
                        Label { Text("Press ") + Text("esc").bold() + Text(" to cancel") } icon: { Image(systemName: "xmark.circle.fill") }
                    }
                    .font(.system(size: 13.5)).foregroundStyle(Look.ink)
                    .symbolRenderingMode(.hierarchical)
                }
            }
            Card(padding: 14) { SettingRow(title: "Shortcut", detail: "For example ⌃⌥Space or Right ⌘.") { ShortcutRecorder(model: model) } }
                .padding(.top, 12)
            if key.isGlobe {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lightbulb").foregroundStyle(Color.mtWarn)
                    Text("If tapping Globe opens emoji or Apple's dictation, set System Settings › Keyboard › “Press 🌐 key to” to Do Nothing.")
                        .font(.system(size: 12)).foregroundStyle(Look.muted).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    SoftButton(title: "Keyboard Settings", symbol: "keyboard") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!) }
                }
                .padding(.top, 14)
            }
        }
    }

    private var shortName: String { model.shortcut.isGlobe ? "🌐" : model.shortcut.name }

    private var done: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(Color.mtGood).padding(.top, 30)
            Text("You're set").font(.system(size: 26, weight: .bold)).foregroundStyle(Look.ink)
            Text(models.isReady(model.mode) ? "\(model.shortcut.verb) \(shortName) anywhere and start talking." : "Download a model on the Models page when you're ready, then \(model.shortcut.verb.lowercased()) \(shortName) anywhere.")
                .font(.system(size: 14)).foregroundStyle(Look.muted).multilineTextAlignment(.center).frame(maxWidth: 380)
            HStack(spacing: 8) {
                Chip(text: "Everything stays on this Mac", symbol: "lock.fill")
                Chip(text: "Settings › Show walkthrough to see this again", symbol: "sparkles")
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }
}
