import AppKit
import ApplicationServices

/// Owns only the range created by this dictation. If focus, selection, or text
/// changes independently, stop touching the field and preserve the transcript.
@MainActor public final class TextInsertion {
    private var element: AXUIElement?
    private var fallbackElement: AXUIElement?
    private var originalSelection: CFRange?
    private var pid: pid_t = 0
    private var expected = ""
    private var before = ""
    private var after = ""
    private var selectedOriginal = ""
    private var ownsRange = false
    private var caret = 0
    public private(set) var inserted = ""
    public private(set) var paused = false
    public private(set) var destination = ""
    public private(set) var available = false
    public init() {}
    private func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?; guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }; return result
    }
    private func range(_ element: AXUIElement) -> CFRange? {
        guard let raw = value(element, kAXSelectedTextRangeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var range = CFRange(); guard AXValueGetValue(raw as! AXValue, .cfRange, &range) else { return nil }; return range
    }
    public func capture() {
        element = nil; fallbackElement = nil; originalSelection = nil; inserted = ""; ownsRange = false; paused = false; available = false
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        pid = app.processIdentifier; destination = app.localizedName ?? "App"
        guard pid != getpid(), AXIsProcessTrusted() else { return }
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.2)
        guard let raw = value(root, kAXFocusedUIElementAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return }
        let field = raw as! AXUIElement
        AXUIElementSetMessagingTimeout(field, 0.2)
        if let subrole = value(field, kAXSubroleAttribute) as? String, subrole == kAXSecureTextFieldSubrole { return }
        fallbackElement = field
        expected = value(field, kAXValueAttribute) as? String ?? ""
        originalSelection = range(field)
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(field, kAXValueAttribute as CFString, &settable) == .success, settable.boolValue,
              let text = value(field, kAXValueAttribute) as? String, let selected = range(field),
              selected.location >= 0, selected.location + selected.length <= (text as NSString).length else { return }
        let ns = text as NSString
        selectedOriginal = ns.substring(with: NSRange(location: selected.location, length: selected.length))
        before = ns.substring(to: selected.location); after = ns.substring(from: selected.location + selected.length)
        expected = text; caret = selected.location; element = field; available = true
    }
    private func unchanged(_ field: AXUIElement) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let focused = value(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute),
              CFEqual(focused, field), let text = value(field, kAXValueAttribute) as? String, text == expected,
              let selection = range(field), selection.location == caret,
              (ownsRange ? selection.length == 0 : selection.length == originalSelection?.length) else { return false }
        return true
    }
    @discardableResult public func update(_ text: String) -> Bool {
        guard !paused, let field = element, unchanged(field) else { paused = true; return false }
        guard text != inserted else { return true }
        let replacement = before + text + after
        guard AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, replacement as CFString) == .success else { paused = true; return false }
        caret = (before as NSString).length + (text as NSString).length
        var selection = CFRange(location: caret, length: 0)
        if let value = AXValueCreate(.cfRange, &selection) { _ = AXUIElementSetAttributeValue(field, kAXSelectedTextRangeAttribute as CFString, value) }
        expected = replacement; inserted = text; ownsRange = true
        if (value(field, kAXValueAttribute) as? String) != replacement { paused = true; return false }
        return true
    }
    /// Final-only paste for apps that expose focus but not writable AX text.
    /// Never paste after partial insertion or a focus/selection change.
    public func pasteFinal(_ text: String) -> Bool {
        guard inserted.isEmpty, !text.isEmpty, let field = fallbackElement,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let focused = value(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute), CFEqual(focused, field),
              (value(field, kAXValueAttribute) as? String ?? "") == expected else { return false }
        if let originalSelection, let now = range(field),
           (now.location != originalSelection.location || now.length != originalSelection.length) { return false }
        Self.copy(text)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: down)
            event?.flags = .maskCommand; event?.post(tap: .cghidEventTap)
        }
        return true
    }
    public func cancel() { if available, ownsRange { _ = update(selectedOriginal) } }
    public static func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
}
