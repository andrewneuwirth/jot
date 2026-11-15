import SwiftUI
import AppKit
import CoreAudio
import MacToolsKit

private let jotBlue = Color.mtJot

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
    var open: (Page) -> Void
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
                Button("Open Jot") { open(.dictation) }
                Button("Notes") { open(.notes) }
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
