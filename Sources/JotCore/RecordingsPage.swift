import SwiftUI
import AppKit
import MacToolsKit

/// Record Class and Record Call: the same recorder (audio on disk as it goes, live Apple transcript), one tab each.
/// A call also records what the Mac plays, so both sides are in the transcript.
struct RecordingsPage: View {
    @ObservedObject var model: AppModel
    @ObservedObject var classes: ClassRecorder
    let calls: Bool
    @State private var selected: UUID?
    @State private var confirmStop = false
    @State private var confirmDelete: UUID?
    @State private var renaming = ""

    private var kind: String { calls ? "call" : "class" }
    private var sessions: [ClassSession] { classes.sessions.filter { $0.isCall == calls } }
    private var mine: Bool { classes.active.map { $0.isCall == calls } ?? false }
    private var shown: ClassSession? {
        if mine, let a = classes.active { return classes.sessions.first { $0.id == a.id } ?? a }
        return sessions.first { $0.id == selected } ?? sessions.first
    }

    var body: some View {
        PageHeader(title: calls ? "Record Call" : "Record Class", detail: sessions.isEmpty ? nil : "\(sessions.count) saved") { EmptyView() }
        HStack(alignment: .top, spacing: MT.Space.s12) {
            VStack(spacing: MT.Space.s12) { recorder; list }.frame(width: 340)
            transcript
        }
        .padding([.horizontal, .bottom], 22)
        .confirmationDialog("Stop the \(kind) recording?", isPresented: $confirmStop) {
            Button("Stop recording", role: .destructive) { Task { await classes.stop() } }
            Button("Keep recording", role: .cancel) {}
        } message: { Text("Everything so far is already saved. Stopping ends this session.") }
        .alert("Delete this recording and its audio?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button("Cancel", role: .cancel) { confirmDelete = nil }
            Button("Move to Trash", role: .destructive) { if let id = confirmDelete { classes.delete(id) }; confirmDelete = nil }
        }
    }

    private var recorder: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: calls ? "phone.fill" : "graduationcap.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(mine ? Color.mtBad : Look.accent)
                        .frame(width: 36, height: 36).background(Circle().fill((mine ? Color.mtBad : Look.accent).opacity(0.12)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mine ? "Recording" : (calls ? "Both sides of a call" : "A whole lecture")).font(.system(size: 14, weight: .semibold)).foregroundStyle(Look.ink)
                        Text(calls ? "Your mic plus what the Mac plays (FaceTime, Zoom, Meet)." : "Leave it running. Audio is saved as it goes.")
                            .font(.system(size: 11.5)).foregroundStyle(Look.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(alignment: .lastTextBaseline) {
                    Text(formatClock(mine ? classes.elapsed : 0)).font(.system(size: 34, weight: .light, design: .rounded)).monospacedDigit()
                        .foregroundStyle(mine ? Look.ink : Look.muted)
                    Spacer()
                    if mine { LevelBars(level: classes.level) }
                }
                if mine {
                    PrimaryButton(title: "Stop", symbol: "stop.fill", tint: .mtBad) { confirmStop = true }
                } else if let other = classes.active {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("A \(other.isCall ? "call" : "class") recording is running.").font(.system(size: 12)).foregroundStyle(Color.mtWarn)
                        SoftButton(title: "Go to it", symbol: "arrow.right") { model.page = other.isCall ? .calls : .classes }
                    }
                } else {
                    PrimaryButton(title: calls ? "Record call" : "Record class", symbol: "record.circle", tint: .mtBad,
                                  disabled: model.recording || model.finishing) { classes.start(microphoneID: model.microphoneID, includeMacAudio: calls) }
                    if calls {
                        Text("The first time, macOS asks to let Jot record system audio. Tell the other side you're recording.")
                            .font(.system(size: 11)).foregroundStyle(Look.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !classes.notice.isEmpty { Text(classes.notice).font(.system(size: 11.5)).foregroundStyle(Color.mtWarn).fixedSize(horizontal: false, vertical: true) }
            }
        }
    }

    private var list: some View {
        Card(padding: 6) {
            if sessions.isEmpty {
                EmptyState(symbol: calls ? "phone" : "graduationcap", title: "No \(kind) recordings yet", message: "Past recordings and their transcripts show up here.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(sessions) { s in
                            RowButton(selected: shown?.id == s.id, action: { selected = s.id }) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(s.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Look.ink).lineLimit(1)
                                    HStack(spacing: 6) {
                                        Text(formatClock(s.id == classes.active?.id ? classes.elapsed : s.seconds)).monospacedDigit()
                                        Text("·"); Text(s.status).foregroundStyle(s.status == "Recording" ? Color.mtBad : (s.status.hasPrefix("Interrupted") ? Color.mtWarn : Look.muted))
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

    @ViewBuilder private var transcript: some View {
        if let s = shown {
            let live = classes.active?.id == s.id
            let text = live ? classes.liveText : s.transcript
            Card(padding: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        TextField("Title", text: $renaming).textFieldStyle(.plain).font(.system(size: 15, weight: .semibold))
                            .onSubmit { let t = renaming.trimmingCharacters(in: .whitespaces); if !t.isEmpty { classes.rename(s.id, to: t) } }
                            .onAppear { renaming = s.title }.onChange(of: s.id) { _, _ in renaming = s.title }
                        Spacer()
                        if !live {
                            SoftButton(title: "Copy", symbol: "doc.on.doc", disabled: text.isEmpty) { TextInsertion.copy(text) }
                            SoftButton(title: "Save as note", symbol: "note.text.badge.plus", disabled: text.isEmpty) {
                                model.selection = model.library.addNote(body: text, title: s.title); model.page = .notes
                            }
                            Menu {
                                Button("Re-transcribe from audio") { classes.retranscribe(s.id, engine: model.speech, mode: model.mode) }
                                    .disabled(classes.retranscribing || !model.ready || s.segments.isEmpty)
                                Button("Export…") { saveText(text, name: s.title + ".txt") }
                                Button("Show audio in Finder") { NSWorkspace.shared.activateFileViewerSelecting([ClassPaths.directory(s)]) }
                                Divider()
                                Button("Delete…", role: .destructive) { confirmDelete = s.id }
                            } label: { Image(systemName: "ellipsis") }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28)
                        } else {
                            Chip(text: "Live", symbol: "dot.radiowaves.left.and.right", tint: .mtBad)
                        }
                    }
                    .padding(.horizontal, 18).frame(height: 52)
                    Divider().overlay(Look.line)
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(spacing: 6) {
                                    Chip(text: s.started.formatted(date: .abbreviated, time: .shortened), symbol: "calendar")
                                    Chip(text: formatClock(live ? classes.elapsed : s.seconds), symbol: "clock")
                                    Chip(text: "\(s.segments.count) audio file\(s.segments.count == 1 ? "" : "s")", symbol: "waveform")
                                }
                                Text(text.isEmpty ? (live ? "Listening… words appear here as they're spoken." : "No transcript. The audio is saved: use Re-transcribe from audio.") : text)
                                    .font(.system(size: 15)).lineSpacing(5).foregroundStyle(text.isEmpty ? Look.muted : Look.ink)
                                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                if !live, s.liveTranscript != s.transcript, !s.liveTranscript.isEmpty {
                                    DisclosureGroup("Live transcript") {
                                        Text(s.liveTranscript).font(.system(size: 13)).foregroundStyle(Look.muted).textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                                    }
                                    .font(.system(size: 12.5, weight: .medium))
                                }
                                Color.clear.frame(height: 1).id("end")
                            }
                            .padding(22)
                        }
                        .onChange(of: text) { if live { proxy.scrollTo("end") } }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        } else {
            Card {
                EmptyState(symbol: "text.alignleft", title: calls ? "Press Record call when the call starts" : "Press Record class and leave it running",
                           message: "Raw transcript, no cleanup. Re-transcribe later with your selected model for better accuracy.")
            }
            .frame(maxHeight: .infinity)
        }
    }
}

/// Live input level as a few bars.
struct LevelBars: View {
    let level: Float
    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<9, id: \.self) { i in
                let shape = [0.4, 0.7, 1.0, 0.8, 0.55, 0.9, 0.65, 0.85, 0.45][i]
                RoundedRectangle(cornerRadius: 1.5).fill(Color.mtBad.opacity(0.8))
                    .frame(width: 3, height: max(3, CGFloat(level) * 26 * shape))
            }
        }
        .frame(height: 26)
        .accessibilityHidden(true)
    }
}
