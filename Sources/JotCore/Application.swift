import AppKit
import SwiftUI

@MainActor public final class JotApplication: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = AppModel()
    private var window: NSWindow?
    private var pill: NSPanel?
    private var status: NSStatusItem?
    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMenu()
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status?.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Jot")
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Jot", action: #selector(openWindow), keyEquivalent: "")
        menu.addItem(withTitle: "Start / finish dictation", action: #selector(toggle), keyEquivalent: "")
        menu.addItem(.separator()); menu.addItem(withTitle: "Settings…", action: #selector(settings), keyEquivalent: ",")
        menu.addItem(withTitle: "Quit Jot", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }; status?.menu = menu
        model.overlayChanged = { [weak self] in self?.updatePill() }
        model.start(); openWindow()
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            let diagnostic: [String: Any] = ["state": self.model.state, "window": self.window.map { NSStringFromRect($0.frame) } ?? "none", "visible": self.window?.isVisible ?? false, "settings": self.model.showSettings, "shortcuts": self.model.hotkeysReady, "recording": self.model.recording]
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
            w.title = "Jot"; w.titlebarAppearsTransparent = true; w.isReleasedWhenClosed = false; w.delegate = self
            let host = NSHostingView(rootView: MainView(model: model, library: model.library).padding(.top, 24))
            host.sizingOptions = []
            w.contentView = host
            w.minSize = NSSize(width: 1050, height: 650)
            w.setFrameAutosaveName("JotMainWindow"); w.center(); window = w
        }
        NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
    @objc private func settings() { model.showSettings = true; openWindow() }
    @objc private func toggle() { model.toggle() }
    @objc private func quit() {
        if model.recording || model.finishing { model.notice = "Finish or cancel your recording before quitting."; updatePill(); return }
        NSApp.terminate(nil)
    }
    private func updatePill() {
        guard model.showOverlay else { pill?.orderOut(nil); return }
        if pill == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 236, height: 80), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isFloatingPanel = true; p.level = .floating; p.hidesOnDeactivate = false; p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true; p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let host = NSHostingView(rootView: RecordingView(model: model)); host.sizingOptions = []
            p.contentView = host; pill = p
        }
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main {
            pill?.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 236 - 16, y: screen.visibleFrame.minY + 16))
        }
        pill?.orderFrontRegardless()
    }
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openWindow(); return true }
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    public func application(_ application: NSApplication, open urls: [URL]) { if urls.contains(where: { $0.scheme == "jot" && $0.host == "toggle" }) { model.toggle() } }
    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model.recording || model.finishing { model.notice = "Finish recording before quitting."; return .terminateCancel }; return .terminateNow
    }
}
