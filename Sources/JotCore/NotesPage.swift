import SwiftUI
import AppKit
import MacToolsKit

/// Notes: a list with folders and search, and an editor you can also dictate into.
struct NotesPage: View {
    @ObservedObject var model: AppModel
    @ObservedObject var library: Library
    @State private var filter = "All"
    @State private var addingFolder = false
    @State private var folderName = ""
    @State private var pendingDelete: UUID?

    var body: some View {
        PageHeader(title: "Notes", detail: library.notes.isEmpty ? nil : "\(library.notes.count)") {
            SearchPill(text: $model.search, prompt: "Search notes")
            PrimaryButton(title: "New note", symbol: "square.and.pencil") { model.newNote(); filter = "All" }
        }
        HStack(alignment: .top, spacing: MT.Space.s12) {
            list.frame(width: 320)
            editor
        }
        .padding([.horizontal, .bottom], 22)
        .sheet(isPresented: $addingFolder) { folderSheet }
        .alert("Delete this note?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete", role: .destructive) {
                library.notes.removeAll { $0.id == pendingDelete }; library.save(); pendingDelete = nil; model.selection = notes.first?.id
            }
        } message: { Text("Export anything you want to keep first.") }
    }

    private var notes: [Note] {
        library.notes.filter { note in
            (filter == "All" || (filter == "Pinned" && note.pinned) || note.folder == filter) &&
            (model.search.isEmpty || (note.title + " " + note.body).localizedCaseInsensitiveContains(model.search))
        }
        .sorted { ($0.pinned ? 1 : 0, $0.updated) > ($1.pinned ? 1 : 0, $1.updated) }
    }

    private var list: some View {
        Card(padding: 6) {
            VStack(alignment: .leading, spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(["All", "Pinned"] + library.folders, id: \.self) { f in
                            Button { filter = f } label: {
                                Text(f).font(.system(size: 12, weight: .medium)).foregroundStyle(filter == f ? Look.accent : Look.muted)
                                    .padding(.horizontal, 10).frame(height: 26)
                                    .background(Capsule().fill(filter == f ? Look.selected : .clear))
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(filter == f ? .isSelected : [])
                        }
                        IconButton(symbol: "plus", help: "New folder") { addingFolder = true }
                    }
                    .padding(.horizontal, 4).padding(.top, 4)
                }
                if notes.isEmpty {
                    EmptyState(symbol: "note.text", title: model.search.isEmpty ? "No notes here" : "No matches",
                               message: model.search.isEmpty ? "Write one, or save a dictation or a recording as a note." : "Try other words.")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(notes) { note in
                                RowButton(selected: model.selection == note.id, action: { model.selection = note.id }) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 6) {
                                            Text(note.title.isEmpty ? "Untitled note" : note.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Look.ink).lineLimit(1)
                                            if note.pinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(Look.accent).accessibilityLabel("Pinned") }
                                            Spacer(minLength: 4)
                                            Text(note.updated.formatted(.relative(presentation: .named))).font(.system(size: 10.5)).foregroundStyle(.tertiary).lineLimit(1)
                                        }
                                        Text(note.body.isEmpty ? "Empty note" : note.body).font(.system(size: 12)).foregroundStyle(Look.muted).lineLimit(2)
                                    }
                                }
                            }
                        }
                        .padding(2)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder private var editor: some View {
        if let index = library.notes.firstIndex(where: { $0.id == model.selection }) {
            let note = library.notes[index]
            Card(padding: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 2) {
                        IconButton(symbol: "bold", help: "Bold (Markdown)") { wrap("**") }
                        IconButton(symbol: "italic", help: "Italic (Markdown)") { wrap("_") }
                        IconButton(symbol: "list.bullet", help: "Bulleted list") { append("\n- ") }
                        IconButton(symbol: "checklist", help: "Checklist") { append("\n- [ ] ") }
                        Spacer()
                        Picker("Folder", selection: binding(index, \.folder)) { ForEach(library.folders, id: \.self) { Text($0) } }
                            .labelsHidden().frame(width: 120).controlSize(.small)
                        IconButton(symbol: note.pinned ? "pin.fill" : "pin", help: note.pinned ? "Unpin" : "Pin", on: note.pinned) { library.notes[index].pinned.toggle(); library.save() }
                        Menu {
                            Button("Export…") { saveText(note.body, name: "\(note.title).md") }
                            Button("Copy") { TextInsertion.copy(note.body) }
                            Divider()
                            Button("Delete note", role: .destructive) { pendingDelete = note.id }
                        } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28)
                        PrimaryButton(title: model.recording ? "Finish" : "Dictate", symbol: model.recording ? "stop.fill" : "mic.fill",
                                      tint: model.recording ? .mtBad : Look.accent, disabled: model.finishing || model.busy) { model.toggle(note: note.id) }
                            .padding(.leading, 6)
                    }
                    .padding(.horizontal, 14).frame(height: 52)
                    Divider().overlay(Look.line)
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Untitled note", text: binding(index, \.title)).font(.system(size: 24, weight: .bold)).textFieldStyle(.plain)
                        Text("Edited " + note.updated.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 11.5)).foregroundStyle(Look.muted)
                        TextEditor(text: binding(index, \.body)).font(.system(size: 15)).lineSpacing(4).scrollContentBackground(.hidden).padding(.leading, -5)
                    }
                    .padding(.horizontal, 26).padding(.top, 20)
                }
            }
            .frame(maxHeight: .infinity)
        } else {
            Card {
                VStack(spacing: 14) {
                    EmptyState(symbol: "square.and.pencil", title: "A little room for a thought", message: "Write a note, or let your voice do the typing.")
                        .frame(maxHeight: 220)
                    PrimaryButton(title: "New note", symbol: "square.and.pencil") { model.newNote() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var folderSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New folder").font(.title3.bold())
            TextField("Folder name", text: $folderName)
            HStack {
                Button("Cancel") { addingFolder = false }
                Spacer()
                Button("Create") {
                    let name = folderName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty, !library.folders.contains(name), !["All", "Pinned"].contains(name) { library.folders.append(name); library.save(); filter = name }
                    addingFolder = false; folderName = ""
                }
                .keyboardShortcut(.defaultAction).disabled(folderName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24).frame(width: 320)
    }

    private func binding(_ index: Int, _ path: WritableKeyPath<Note, String>) -> Binding<String> {
        let id = library.notes[index].id
        return Binding(get: { library.notes.first(where: { $0.id == id })?[keyPath: path] ?? "" }, set: { value in
            guard let i = library.notes.firstIndex(where: { $0.id == id }) else { return }
            library.notes[i][keyPath: path] = value; library.notes[i].updated = Date(); library.save()
        })
    }
    private func append(_ text: String) { if let i = library.notes.firstIndex(where: { $0.id == model.selection }) { library.notes[i].body += text; library.save() } }
    private func wrap(_ marker: String) {
        guard let text = NSApp.keyWindow?.firstResponder as? NSTextView, text.isEditable else { return }
        let range = text.selectedRange(), selected = (text.string as NSString).substring(with: range)
        text.insertText(marker + selected + marker, replacementRange: range)
    }
}
