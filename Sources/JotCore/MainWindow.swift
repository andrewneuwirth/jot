import SwiftUI
import AppKit
import MacToolsKit

/// The main window: a sidebar on the canvas and the current page on a raised panel (the family's Dispatch shape).
struct RootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var library: Library
    @ObservedObject var classes: ClassRecorder
    var body: some View {
        HStack(spacing: 0) {
            Sidebar(model: model, library: library, classes: classes)
            VStack(spacing: 0) { page }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Look.panel)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: MT.Radius.panel, bottomLeadingRadius: MT.Radius.panel))
                .overlay(UnevenRoundedRectangle(topLeadingRadius: MT.Radius.panel, bottomLeadingRadius: MT.Radius.panel).strokeBorder(Look.line))
                .padding(.vertical, MT.Space.s8)
        }
        .background(Look.canvas)
        .ignoresSafeArea()
        .tint(Look.accent)
        .frame(minWidth: 980, minHeight: 640)
        .overlay(alignment: .bottom) { toast }
        .sheet(isPresented: $model.showOnboarding) { Onboarding(model: model, models: model.models) }
    }

    @ViewBuilder private var page: some View {
        switch model.page {
        case .dictation: DictationPage(model: model, library: library)
        case .notes: NotesPage(model: model, library: library)
        case .classes: RecordingsPage(model: model, classes: classes, calls: false)
        case .calls: RecordingsPage(model: model, classes: classes, calls: true)
        case .models: ModelsPage(model: model, models: model.models)
        case .settings: SettingsPage(model: model, library: library)
        }
    }

    @ViewBuilder private var toast: some View {
        let text = library.error ?? model.notice
        if !text.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: library.error == nil ? "info.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(library.error == nil ? Look.accent : Color.mtBad)
                Text(text).font(.system(size: 12.5)).foregroundStyle(Look.ink).textSelection(.enabled).lineLimit(3)
                if library.error == nil {
                    Button { model.notice = "" } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Look.muted) }
                        .buttonStyle(.plain).accessibilityLabel("Dismiss")
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Capsule().fill(Look.card).shadow(color: .black.opacity(0.12), radius: 10, y: 3))
            .overlay(Capsule().strokeBorder(Look.line))
            .padding(.bottom, 22).padding(.leading, 220)
            .frame(maxWidth: 760)
        }
    }
}

struct Sidebar: View {
    @ObservedObject var model: AppModel
    @ObservedObject var library: Library
    @ObservedObject var classes: ClassRecorder
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Color.clear.frame(height: 30)   // the traffic lights
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8).fill(LinearGradient(colors: [Color(hex: 0x5aa7ff), Look.accent], startPoint: .top, endPoint: .bottom))
                    .frame(width: 30, height: 30)
                    .overlay(Image(systemName: "waveform").font(.system(size: 14, weight: .bold)).foregroundStyle(.white))
                Text("Jot").font(.system(size: 18, weight: .semibold)).foregroundStyle(Look.ink)
            }
            .padding(.horizontal, 10).padding(.bottom, 14)
            .accessibilityHidden(true)

            dictateButton.padding(.bottom, 14)

            group("Write")
            item(.dictation, count: library.history.count)
            item(.notes, count: library.notes.count)
            group("Record")
            item(.classes, count: classes.sessions.filter { !$0.isCall }.count, live: classes.active.map { !$0.isCall } ?? false)
            item(.calls, count: classes.sessions.filter(\.isCall).count, live: classes.active?.isCall ?? false)
            group("Engine")
            item(.models, count: nil)
            Spacer()
            item(.settings, count: nil)
            status.padding(.top, 8)
        }
        .padding(.horizontal, 12).padding(.bottom, 14)
        .frame(width: 220)
    }

    /// Start / finish dictation from the window, the same as the Globe key.
    private var dictateButton: some View {
        let live = model.recording
        return Button { model.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: live ? "stop.fill" : "mic.fill").font(.system(size: 12, weight: .bold))
                Text(live ? "Finish · \(formatDuration(model.seconds))" : (model.finishing ? "Finishing…" : "Dictate")).font(.system(size: 13.5, weight: .semibold)).monospacedDigit()
                Spacer()
                if !live && !model.finishing { Image(systemName: "globe").font(.system(size: 12, weight: .semibold)).opacity(0.75).padding(.trailing, 6) }
            }
            .foregroundStyle(.white)
            .padding(.leading, 14).padding(.trailing, 8).frame(height: 38)
            .background(Capsule().fill(live ? Color.mtBad : Look.accent))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(model.finishing || model.busy)
        .help(live ? "Finish dictation" : "Start dictation (or tap the Globe key anywhere)")
    }

    private func group(_ title: String) -> some View {
        Text(title.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(0.6).foregroundStyle(.tertiary)
            .padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 3)
            .accessibilityAddTraits(.isHeader)
    }

    private func item(_ page: Page, count: Int?, live: Bool = false) -> some View {
        let on = model.page == page
        return Button {
            model.page = page; model.search = ""
            if page == .dictation { model.selection = library.history.first?.id }
            if page == .notes { model.selection = library.notes.first?.id }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: page.symbol).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(on ? Look.accent : Look.muted).frame(width: 18)
                Text(page.title).font(.system(size: 13.5, weight: on ? .semibold : .regular)).foregroundStyle(Look.ink)
                Spacer()
                if live { Circle().fill(Color.mtBad).frame(width: 7, height: 7).accessibilityLabel("Recording") }
                else if let count, count > 0 { Text("\(count)").font(.system(size: 11.5)).foregroundStyle(Look.muted).monospacedDigit() }
            }
            .padding(.horizontal, 10).frame(height: 32)
            .background(RoundedRectangle(cornerRadius: MT.Radius.row).fill(on ? Look.card : .clear)
                .shadow(color: .black.opacity(on ? 0.07 : 0), radius: 3, y: 1))
            .overlay(RoundedRectangle(cornerRadius: MT.Radius.row).strokeBorder(on ? Look.line : .clear))
            .contentShape(RoundedRectangle(cornerRadius: MT.Radius.row))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var status: some View {
        let busy = model.recording || classes.isActive
        let color: Color = busy ? .mtBad : (model.ready ? .mtGood : .mtWarn)
        return HStack(spacing: 8) {
            Circle().fill(color).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(classes.isActive ? "Recording · " + formatClock(classes.elapsed) : model.state).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Look.ink).monospacedDigit()
                Text(SpeechCatalog.model(for: model.mode).name).font(.system(size: 10.5)).foregroundStyle(Look.muted)
            }
            .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .accessibilityElement(children: .combine)
    }
}
