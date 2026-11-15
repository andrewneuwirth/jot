import AppKit
import Carbon

final class GlobalHotkeys {
    var smartPaste: (() -> Void)?
    var toggle: (() -> Void)?
    var cancel: (() -> Void)?
    var isRecording: (() -> Bool)?
    var holdToTalk: ((Bool) -> Void)?
    var spaceHoldAllowed: (() -> Bool)?
    var shortcut: (() -> DictationShortcut)?
    /// True while the shortcut recorder listens, so the keys reach it instead of starting a dictation.
    var suspended: (() -> Bool)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var globeDown = false
    private var modifierTap = ModifierTap()
    private var comboDown: Int64?
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
            globeDown = false; comboDown = nil; modifierTap = ModifierTap()
            holdTimer?.cancel()
            if spaceHold.reset() { DispatchQueue.main.async { [weak self] in self?.holdToTalk?(false) } }
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        // Spaces Jot replays itself must not re-enter the hold machine.
        if event.getIntegerValueField(.eventSourceUserData) == Self.synthetic { return Unmanaged.passUnretained(event) }
        if suspended?() == true { return Unmanaged.passUnretained(event) }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let shortcut = self.shortcut?() ?? .globe
        if type == .keyDown { modifierTap.key() }
        if case .combo(let key, let modifiers) = shortcut, code == key {
            if type == .keyDown, event.flags.intersection(DictationShortcut.modifierMask) == modifiers {
                if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 { comboDown = key; DispatchQueue.main.async { [weak self] in self?.toggle?() } }
                return nil
            }
            if type == .keyUp, comboDown == key { comboDown = nil; return nil }
        }
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
        if type == .flagsChanged, case .modifier(let key) = shortcut, let info = DictationShortcut.modifierKeys[code] {
            // Passed through either way: the modifier may be starting a combination.
            let held = event.flags.intersection(DictationShortcut.modifierMask.union(.maskSecondaryFn))
            if modifierTap.flags(code: code, down: event.flags.contains(info.flag), alone: held == info.flag) == key {
                DispatchQueue.main.async { [weak self] in self?.toggle?() }
            }
        }
        if type == .flagsChanged, code == 63, shortcut.isGlobe {
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

/// The start / finish dictation shortcut: a Globe (fn) tap, a lone tap of another modifier (Right ⌘…), or a key
/// combination (⌃⌥Space). Stored in defaults as `globe`, `tap:54` or `combo:49:⌃⌥`; a missing value means Globe.
enum DictationShortcut: Equatable {
    case globe
    case modifier(Int64)
    case combo(key: Int64, modifiers: CGEventFlags)

    static let defaultsKey = "dictationShortcut"
    static let modifierMask: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
    private static let symbols: [(CGEventFlags, String)] = [(.maskControl, "⌃"), (.maskAlternate, "⌥"), (.maskShift, "⇧"), (.maskCommand, "⌘")]
    /// Modifier key codes, their flag and name. Right-hand keys suit a lone tap; left-hand ones get tapped by accident.
    static let modifierKeys: [Int64: (flag: CGEventFlags, name: String)] = [
        54: (.maskCommand, "Right ⌘"), 55: (.maskCommand, "Left ⌘"), 61: (.maskAlternate, "Right ⌥"), 58: (.maskAlternate, "Left ⌥"),
        62: (.maskControl, "Right ⌃"), 59: (.maskControl, "Left ⌃"), 60: (.maskShift, "Right ⇧"), 56: (.maskShift, "Left ⇧"),
        63: (.maskSecondaryFn, "Globe")]
    static let functionKeys: [Int64: String] = [122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20"]
    // shortcut: labels follow US key positions, so other layouts show the US letter; read the live layout with UCKeyTranslate if that confuses people.
    static let keyNames: [Int64: String] = {
        var names: [Int64: String] = [36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "esc", 117: "⌦", 115: "Home", 119: "End",
                                      116: "Page Up", 121: "Page Down", 123: "←", 124: "→", 125: "↓", 126: "↑"]
        let ansi: [Int64: Character] = [0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q",
            13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
            27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";",
            42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 50: "`"]
        for (code, char) in ansi { names[code] = String(char) }
        return names.merging(functionKeys) { a, _ in a }
    }()

    init(stored: String?) {
        let parts = (stored ?? "globe").split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        switch parts.first {
        case "tap" where parts.count == 2:
            if let code = Int64(parts[1]), code != 63, Self.modifierKeys[code] != nil { self = .modifier(code) } else { self = .globe }
        case "combo" where parts.count == 3:
            guard let code = Int64(parts[1]) else { self = .globe; return }
            let flags = Self.symbols.filter { parts[2].contains($0.1) }.reduce(CGEventFlags()) { $0.union($1.0) }
            self = .combo(key: code, modifiers: flags)
        default: self = .globe
        }
    }
    var stored: String {
        switch self {
        case .globe: "globe"
        case .modifier(let code): "tap:\(code)"
        case .combo(let key, let mods): "combo:\(key):\(Self.symbolText(mods))"
        }
    }
    static func symbolText(_ flags: CGEventFlags) -> String { symbols.filter { flags.contains($0.0) }.map(\.1).joined() }

    /// What goes on the keycaps, one string per key.
    var keys: [String] {
        switch self {
        case .globe: ["🌐 Globe"]
        case .modifier(let code): [Self.modifierKeys[code]?.name ?? "Key \(code)"]
        case .combo(let key, let mods): Self.symbols.filter { mods.contains($0.0) }.map(\.1) + [Self.keyNames[key] ?? "Key \(key)"]
        }
    }
    /// The shortcut in a sentence: "Globe", "Right ⌘", "⌃⌥Space".
    var name: String {
        switch self {
        case .globe: "Globe"
        case .combo(let key, let mods): Self.symbolText(mods) + (Self.keyNames[key] ?? "Key \(key)")
        default: keys.joined()
        }
    }
    /// "Tap" for a single key, "Press" for a combination.
    var verb: String { if case .combo = self { "Press" } else { "Tap" } }
    var isGlobe: Bool { self == .globe }

    /// Why this can't be the shortcut, or nil.
    var rejection: String? {
        guard case .combo(let key, let mods) = self else { return nil }
        if mods.intersection([.maskControl, .maskAlternate, .maskCommand]).isEmpty && Self.functionKeys[key] == nil {
            return mods.isEmpty ? "\(name) alone would stop it typing. Add ⌃, ⌥ or ⌘." : "\(name) types a character. Add ⌃, ⌥ or ⌘."
        }
        return nil
    }
    /// Shortcuts macOS or most apps already use: allowed, with a warning.
    var warning: String? {
        if case .modifier(let code) = self, [55, 58, 59, 56].contains(code) { return "Left-hand modifiers get tapped by accident; a right-hand one works better." }
        guard case .combo(let key, let mods) = self else { return nil }
        let taken: [String: String] = ["⌘Space": "Spotlight", "⌃Space": "switching input sources", "⌥⌘Space": "Finder search",
            "⌃⌘Space": "the emoji picker", "⌘Tab": "switching apps", "⌘`": "switching windows", "⌘Q": "quitting apps",
            "⌘W": "closing windows", "⌘H": "hiding apps", "⌘M": "minimising", "⌘C": "Copy", "⌘V": "Paste", "⌘X": "Cut", "⌘Z": "Undo",
            "⌘A": "Select All", "⌘S": "Save", "⌘,": "app settings", "⇧⌘3": "screenshots", "⇧⌘4": "screenshots", "⇧⌘5": "screenshots",
            "⌃⌘Q": "locking the screen"]
        return taken[Self.symbolText(mods) + (Self.keyNames[key] ?? "")].map { "macOS already uses \(name) for \($0); Jot will take it over." }
    }

    static func selfCheck(_ check: (String, Bool) -> Void) {
        check("shortcut: missing or unknown setting means Globe", DictationShortcut(stored: nil) == .globe && DictationShortcut(stored: "nonsense") == .globe)
        let combo = DictationShortcut.combo(key: 49, modifiers: [.maskControl, .maskAlternate])
        check("shortcut: combo round-trips", combo.stored == "combo:49:⌃⌥" && DictationShortcut(stored: combo.stored) == combo && combo.name == "⌃⌥Space")
        check("shortcut: modifier tap round-trips", DictationShortcut(stored: "tap:54") == .modifier(54) && DictationShortcut.modifier(54).stored == "tap:54"
              && DictationShortcut.modifier(54).keys == ["Right ⌘"] && DictationShortcut(stored: "tap:7") == .globe)
        check("shortcut: keycaps in Apple's modifier order", DictationShortcut(stored: "combo:2:⌘⇧").keys == ["⇧", "⌘", "D"])
        check("shortcut: plain letters, Space and ⇧-letters are rejected",
              DictationShortcut.combo(key: 0, modifiers: []).rejection != nil && DictationShortcut.combo(key: 49, modifiers: []).rejection != nil
              && DictationShortcut.combo(key: 0, modifiers: .maskShift).rejection != nil)
        check("shortcut: modified keys, F-keys and Globe are accepted",
              combo.rejection == nil && DictationShortcut.combo(key: 96, modifiers: []).rejection == nil && DictationShortcut.globe.rejection == nil)
        check("shortcut: ⌘Space and ⌘Tab warn, ⌃⌥Space doesn't",
              DictationShortcut.combo(key: 49, modifiers: .maskCommand).warning != nil && DictationShortcut.combo(key: 48, modifiers: .maskCommand).warning != nil
              && combo.warning == nil)
    }
}

/// A lone tap of a modifier key: down with nothing else held, up again within half a second and no key in between.
struct ModifierTap {
    private var pending: Int64?
    private var since = Date.distantPast
    /// A modifier changed. `alone`: it's the only modifier now held. Returns the key code when a tap completes.
    mutating func flags(code: Int64, down: Bool, alone: Bool, now: Date = Date()) -> Int64? {
        if down { pending = alone ? code : nil; since = now; return nil }
        defer { pending = nil }
        return pending == code && now.timeIntervalSince(since) < 0.5 ? code : nil
    }
    /// Any other key was pressed: the modifier was part of a combination.
    mutating func key() { pending = nil }
}
