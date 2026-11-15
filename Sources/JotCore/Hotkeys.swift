import AppKit
import Carbon

final class GlobalHotkeys {
    var smartPaste: (() -> Void)?
    var toggle: (() -> Void)?
    var cancel: (() -> Void)?
    var isRecording: (() -> Bool)?
    var holdToTalk: ((Bool) -> Void)?
    var spaceHoldAllowed: (() -> Bool)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var globeDown = false
    private var spaceHold = SpaceHold()
    private var holdTimer: DispatchWorkItem?
    private static let synthetic: Int64 = 0x4A6F74
    @discardableResult func start() -> Bool {
        guard tap == nil else { return true }
        let mask = [CGEventType.flagsChanged, .keyDown, .keyUp].reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let port = CGEvent.tapCreate(tap: .cghidEventTap, place: .tailAppendEventTap, options: .defaultTap, eventsOfInterest: mask,
            callback: { _, type, event, raw in
                guard let raw else { return Unmanaged.passUnretained(event) }
                return Unmanaged<GlobalHotkeys>.fromOpaque(raw).takeUnretainedValue().handle(type, event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        tap = port; source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            globeDown = false
            holdTimer?.cancel()
            if spaceHold.reset() { DispatchQueue.main.async { [weak self] in self?.holdToTalk?(false) } }
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        // Spaces Jot replays itself must not re-enter the hold machine.
        if event.getIntegerValueField(.eventSourceUserData) == Self.synthetic { return Unmanaged.passUnretained(event) }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyDown || type == .keyUp {
            let modified = !event.flags.intersection([.maskControl, .maskCommand, .maskAlternate, .maskShift]).isEmpty
            switch spaceHold.key(space: code == 49, down: type == .keyDown, repeating: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                                 modified: modified, allowed: spaceHoldAllowed?() == true) {
            case .pass: break
            case .swallow: return nil
            case .wait:
                holdTimer?.cancel()
                let work = DispatchWorkItem { [weak self] in if self?.spaceHold.threshold() == true { self?.holdToTalk?(true) } }
                holdTimer = work
                DispatchQueue.main.asyncAfter(deadline: .now() + SpaceHold.delay, execute: work)
                return nil
            case .typeSpace: postSpace([true, false]); return nil
            case .typeSpaceFirst:
                // Fast typing rolled onto the next key: emit the space, then replay the key in order.
                postSpace([true]); event.copy()?.post(tap: .cghidEventTap); return nil
            case .stop: DispatchQueue.main.async { [weak self] in self?.holdToTalk?(false) }; return nil
            }
        }
        if type == .flagsChanged, code == 63 {
            let down = event.flags.contains(.maskSecondaryFn)
            let modifiers = event.flags.intersection([.maskControl, .maskCommand, .maskAlternate, .maskShift])
            if down, !globeDown, modifiers.isEmpty { globeDown = true; DispatchQueue.main.async { [weak self] in self?.toggle?() }; return nil }
            if !down, globeDown { globeDown = false; return nil }
        }
        if type == .keyDown, code == 53, isRecording?() == true {
            DispatchQueue.main.async { [weak self] in self?.cancel?() }; return nil
        }
        return Unmanaged.passUnretained(event)
    }
    private func postSpace(_ downs: [Bool]) {
        for down in downs {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: down)
            event?.flags = []
            event?.setIntegerValueField(.eventSourceUserData, value: Self.synthetic)
            event?.post(tap: .cghidEventTap)
        }
    }
    deinit { if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }; if let tap { CFMachPortInvalidate(tap) } }
}

/// Hold-to-talk on the space bar in allowlisted apps. A press is held back until
/// release (tap → one replayed space) or `delay` (hold → dictation until key-up).
struct SpaceHold {
    enum Phase { case idle, pending, holding }
    enum Action: Equatable { case pass, swallow, wait, typeSpace, typeSpaceFirst, stop }
    static let delay = 0.35
    static let defaultApps = ["com.openai.chat", "com.openai.codex", "com.anthropic.claudefordesktop",
                              "com.apple.Terminal", "com.mitchellh.ghostty", "com.googlecode.iterm2"].joined(separator: "\n")
    private(set) var phase = Phase.idle
    mutating func key(space: Bool, down: Bool, repeating: Bool, modified: Bool, allowed: @autoclosure () -> Bool) -> Action {
        switch phase {
        case .idle:
            guard space, down, !repeating, !modified, allowed() else { return .pass }
            phase = .pending; return .wait
        case .pending:
            guard space else {
                guard down else { return .pass }
                phase = .idle; return .typeSpaceFirst
            }
            if down { return .swallow }
            phase = .idle; return .typeSpace
        case .holding:
            guard space else { return .pass }
            if down { return .swallow }
            phase = .idle; return .stop
        }
    }
    /// The hold delay elapsed. True when dictation should start.
    mutating func threshold() -> Bool {
        guard phase == .pending else { return false }
        phase = .holding; return true
    }
    /// The event tap was reset. True when a running hold must stop.
    mutating func reset() -> Bool {
        defer { phase = .idle }
        return phase == .holding
    }
    static func allows(_ bundleID: String?, in list: String) -> Bool {
        guard let id = bundleID?.lowercased(), !id.isEmpty else { return false }
        return list.split { $0.isNewline || $0 == "," }.contains { $0.trimmingCharacters(in: .whitespaces).lowercased() == id }
    }
}
