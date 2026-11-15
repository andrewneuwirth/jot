import SwiftUI
import AppKit

/// `Jot --ui-preview DIR`: every page and walkthrough step as PNGs, light and dark, with made-up data. The window is
/// never ordered on screen, and nothing reads or writes your library, recordings, models or settings.
@MainActor public enum UIPreview {
    public static func run(into folder: String) {
        NSApplication.shared.setActivationPolicy(.prohibited)   // no Dock icon, no menu bar
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("jot-preview-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temp) }
        let library = Library(root: temp)
        let now = Date()
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        var notes = [
            Note(title: "Weekend plan", body: "- Farmers market Saturday morning\n- Call the landlord about the sink\n- [ ] Book the train for Sunday\n\nMaybe a hike if the weather holds.", folder: "Personal"),
            Note(title: "Biology 101 — cell membranes", body: "Phospholipid bilayer: hydrophilic heads face out, tails face in. Proteins float in it like boats (fluid mosaic model).\n\nQuiz Friday covers chapters 3 and 4.", folder: "Study"),
            Note(title: "App ideas", body: "A tiny timer that lives in the menu bar and nags you to stand up.", folder: "Projects"),
            Note(title: "Gift list", body: "Sam: a good notebook. Alex: coffee beans.", folder: "Personal"),
        ]
        notes[0].pinned = true
        for i in notes.indices { notes[i].updated = ago(Double(i) * 190 + 12) }
        library.notes = notes
        func dictation(_ text: String, _ minutes: Double, _ seconds: Double, _ app: String, _ status: String = "Inserted") -> Dictation {
            var d = Dictation(text: text, audioFile: nil, duration: seconds, finishMS: 240 + seconds * 9, model: "Parakeet Ultra · Apple preview", destination: app, status: status + (status == "Inserted" ? " in \(app)" : ""))
            d.date = ago(minutes); return d
        }
        var cleaned = dictation("Can we move the team sync to Thursday at four thirty? I'll send the notes right after.", 4, 7.2, "Mail")
        cleaned.originalText = "Um can we move the team sync to Wednesday, I mean Thursday at four thirty? I'll send the notes right after."
        cleaned.cleanupStatus = "Cleaned locally"; cleaned.cleanupMS = 310
        library.history = [
            cleaned,
            dictation("Thanks for the quick turnaround, this looks great. Let's ship it on Monday.", 22, 5.1, "Messages"),
            dictation("Remind me to pick up the dry cleaning and buy oat milk on the way home.", 75, 4.3, "Notes"),
            dictation("The function returns early when the list is empty, so the total is never written. Move the save below the guard.", 140, 9.8, "Terminal"),
            dictation("", 300, 12.4, "History", "Interrupted · retry available"),
        ]
        func session(_ title: String, call: Bool, hours: Double, seconds: Double, _ text: String) -> ClassSession {
            var s = ClassSession(title: title, isCall: call)
            s.started = ago(hours * 60); s.seconds = seconds; s.transcript = text; s.liveTranscript = text; s.status = "Finished"
            s.segments = ["a.caf", "b.caf"]; return s
        }
        let classes = ClassRecorder(preview: [
            session("Physics 101 · Waves and resonance", call: false, hours: 3, seconds: 4_720,
                    "Okay, so last time we talked about simple harmonic motion. Today we're going to look at what happens when you drive an oscillator at its natural frequency.\n\nThat's resonance. The amplitude grows each cycle because the energy you add arrives exactly in phase with the motion. A classic example is pushing a child on a swing: you push at the top of each arc, never against it.\n\nFor the problem set, remember that damping limits the peak. Without damping the amplitude would grow without bound."),
            session("History 210 · The printing press", call: false, hours: 27, seconds: 3_600, "Movable type changed who could read and what they read…"),
            session("Call · Project kickoff with the design team", call: true, hours: 1, seconds: 1_865,
                    "Thanks everyone for joining. The goal today is to agree on the scope for the first release and who owns what.\n\nI think the onboarding flow is the riskiest part, so let's start there. Sam, can you share the latest mockups?\n\nSure. We cut it down to four screens: welcome, permissions, pick a model, and the shortcut."),
            session("Call · Weekly check-in", call: true, hours: 50, seconds: 1_210, "Quick update on the launch checklist…"),
        ])
        let models = ModelStore(root: temp.appendingPathComponent("Models"))
        models.preview(ready: ["parakeet-ultra", "parakeet-eou-160"], progress: ["parakeet-v3": 0.42])
        let model = AppModel(library: library, classes: classes, models: models)
        model.mode = .ultra; model.ready = true; model.state = "Ready"; model.cleanupStatus = "Qwen 3.5 4B · ready locally"

        var shots: [(String, () -> AnyView, NSSize)] = []
        let window = NSSize(width: 1240, height: 800)
        for page in Page.allCases {
            shots.append(("\(page.rawValue)", {
                model.page = page
                model.selection = page == .notes ? library.notes.first?.id : library.history.first?.id
                return AnyView(RootView(model: model, library: library, classes: classes))
            }, window))
        }
        for step in 0..<5 {
            shots.append(("walkthrough-\(step + 1)", { AnyView(Onboarding(model: model, models: models, step: step)) }, NSSize(width: 640, height: 540)))
        }
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for (name, make, size) in shots {
                // Split views, menus and scroll views need a real window to lay out; it's never ordered on screen.
                let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
                w.appearance = NSAppearance(named: appearance)
                let host = NSHostingView(rootView: make())
                w.contentView = host
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.4))
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
                host.cacheDisplay(in: host.bounds, to: rep)
                let file = URL(fileURLWithPath: folder).appendingPathComponent(name + (appearance == .darkAqua ? "-dark" : "") + ".png")
                try? rep.representation(using: .png, properties: [:])?.write(to: file)
            }
        }
        print("wrote \(shots.count * 2) pictures to \(folder)")
    }
}
