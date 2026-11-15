import AppKit
import SwiftUI
import QuartzCore

@MainActor public final class JotApplication: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private let model = AppModel()
    private var window: NSWindow?
    private var pill: NSPanel?
    private var status: NSStatusItem?
    /// Read from defaults each time, so the Settings switch, the bubble's Hide and the menu item stay in step.
    private var bubbleVisible: Bool {
        get { UserDefaults.standard.object(forKey: "bubbleVisible") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "bubbleVisible") }
    }
    private var bubbleAnchor: CGPoint?
    private var dragAnchor: CGPoint?
    private var pillExpanded = false
    private let showWalkthrough: Bool
    /// `showWalkthrough`: decided in main before anything writes settings.
    public init(showWalkthrough: Bool) { self.showWalkthrough = showWalkthrough }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMenu()
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status?.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Jot")
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Jot", action: #selector(openWindow), keyEquivalent: "")
        menu.addItem(withTitle: "Show recording bubble", action: #selector(showBubble), keyEquivalent: "")
        menu.addItem(withTitle: "Start / finish dictation", action: #selector(toggle), keyEquivalent: "")
        menu.addItem(.separator()); menu.addItem(withTitle: "Settings…", action: #selector(settings), keyEquivalent: ",")
        menu.addItem(withTitle: "Quit Jot", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }; menu.delegate = self; status?.menu = menu
        model.overlayChanged = { [weak self] in self?.updatePill() }
        model.showOnboarding = showWalkthrough
        model.start(); openWindow(); updatePill()
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            let diagnostic: [String: Any] = ["state": self.model.state, "window": self.window.map { NSStringFromRect($0.frame) } ?? "none", "visible": self.window?.isVisible ?? false, "page": self.model.page.rawValue, "shortcuts": self.model.hotkeysReady, "recording": self.model.recording]
            if let data = try? JSONSerialization.data(withJSONObject: diagnostic, options: .prettyPrinted) { try? data.write(to: JotPaths.root.appendingPathComponent("runtime.json"), options: .atomic) }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.model.refreshPermissions() } }
    }
    private func buildMenu() {
        let menu = NSMenu(); let app = NSMenuItem(); menu.addItem(app)
        let appMenu = NSMenu(); app.submenu = appMenu
        appMenu.addItem(withTitle: "About Jot", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        let settings = appMenu.addItem(withTitle: "Settings…", action: #selector(settings), keyEquivalent: ","); settings.target = self
        appMenu.addItem(.separator()); appMenu.addItem(withTitle: "Hide Jot", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Jot", action: #selector(quit), keyEquivalent: "q").target = self
        let edit = NSMenuItem(); edit.title = "Edit"; menu.addItem(edit)
        let editMenu = NSMenu(title: "Edit"); edit.submenu = editMenu
        for (title, action, key) in [("Undo", "undo:", "z"), ("Redo", "redo:", "Z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] { editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key) }
        NSApp.mainMenu = menu
    }
    @objc private func openWindow() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 800), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = "Jot"; w.titlebarAppearsTransparent = true; w.titleVisibility = .hidden; w.isReleasedWhenClosed = false; w.delegate = self
            let host = NSHostingView(rootView: RootView(model: model, library: model.library, classes: model.classes))
            host.sizingOptions = []
            w.contentView = host
            w.minSize = NSSize(width: 980, height: 640)
            w.setFrameAutosaveName("JotMainWindow"); w.center(); window = w
        }
        NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
    @objc private func settings() { model.page = .settings; openWindow() }
    @objc private func toggle() { model.toggle() }
    /// The status menu names the current shortcut.
    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.items.first { $0.action == #selector(toggle) }?.title = "Start / finish dictation (\(model.shortcut.name))"
    }
    @objc private func quit() {
        if model.classes.isActive { model.page = model.classes.active?.isCall == true ? .calls : .classes; openWindow(); model.classes.notice = "Class recording is running. Stop it in the app before quitting."; return }
        if model.recording || model.finishing { model.notice = "Finish or cancel your recording before quitting."; updatePill(); return }
        NSApp.terminate(nil)
    }
    @objc private func showBubble() { bubbleVisible = true; UserDefaults.standard.set(true, forKey: "bubbleVisible"); updatePill() }
    private func updatePill() {
        let expanded = model.recording || model.finishing
        guard bubbleVisible || expanded else { pill?.orderOut(nil); return }
        if pill == nil {
            let p = RecordingPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isFloatingPanel = true; p.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1); p.hidesOnDeactivate = false; p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false; p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let host = NSHostingView(rootView: RecordingBubble(model: model,
                open: { [weak self] page in self?.model.page = page; self?.model.selection = page == .dictation ? self?.model.library.history.first?.id : self?.model.library.notes.first?.id; self?.openWindow() },
                settings: { [weak self] in self?.settings() },
                hide: { [weak self] in self?.bubbleVisible = false; UserDefaults.standard.set(false, forKey: "bubbleVisible"); self?.updatePill() },
                drag: { [weak self] translation, ended in
                    guard let self, let anchor = self.bubbleAnchor else { return }
                    if self.dragAnchor == nil { self.dragAnchor = anchor }
                    if let origin = self.dragAnchor { self.bubbleAnchor = CGPoint(x: origin.x + translation.width, y: origin.y - translation.height) }
                    self.updatePill()
                    if ended {
                        self.dragAnchor = nil
                        if let point = self.bubbleAnchor { UserDefaults.standard.set(NSStringFromPoint(point), forKey: "bubbleAnchor") }
                    }
                }))
            host.sizingOptions = []; p.contentView = host; pill = p
        }
        if bubbleAnchor == nil {
            if let saved = UserDefaults.standard.string(forKey: "bubbleAnchor") { bubbleAnchor = NSPointFromString(saved) }
            else if let screen = NSScreen.main { bubbleAnchor = CGPoint(x: screen.visibleFrame.maxX - 16, y: screen.visibleFrame.minY + 16) }
        }
        if var anchor = bubbleAnchor, let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: anchor.x - 22, y: anchor.y + 22)) }) ?? NSScreen.main {
            let width: CGFloat = expanded ? 236 : 44
            let height: CGFloat = expanded ? OverlayLayout.height(model.transcript) : 44
            anchor.x = min(screen.visibleFrame.maxX - 8, max(screen.visibleFrame.minX + width + 8, anchor.x))
            anchor.y = min(screen.visibleFrame.maxY - height - 8, max(screen.visibleFrame.minY + 8, anchor.y))
            bubbleAnchor = anchor
            let frame = NSRect(x: anchor.x - width, y: anchor.y, width: width, height: height)
            if pillExpanded != expanded, pill?.isVisible == true, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.26
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    pill?.animator().setFrame(frame, display: true)
                }
            } else { pill?.setFrame(frame, display: true) }
            pillExpanded = expanded
        }
        pill?.orderFrontRegardless()
    }
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openWindow(); return true }
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    public func application(_ application: NSApplication, open urls: [URL]) { if urls.contains(where: { $0.scheme == "jot" && $0.host == "toggle" }) { model.toggle() } }
    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model.classes.isActive { model.classes.notice = "Class recording is running. Stop it before quitting."; return .terminateCancel }
        if model.recording || model.finishing { model.notice = "Finish recording before quitting."; return .terminateCancel }; return .terminateNow
    }
}

private final class RecordingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
