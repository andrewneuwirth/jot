import AppKit

/// A separate mouse shortcut leaves ordinary Command-V unchanged.
@MainActor enum SmartPaste {
    static func shouldDelete(editable: Bool, selectionLength: Int) -> Bool { editable && selectionLength > 0 }
    static func perform() {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        var delete = false
        if AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
           let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
            let element = focused as! AXUIElement
            AXUIElementSetMessagingTimeout(element, 0.15)
            func attribute(_ name: String) -> CFTypeRef? {
                var value: CFTypeRef?
                guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
                return value
            }
            var settable = DarwinBoolean(false)
            AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
            var selectedSettable = DarwinBoolean(false)
            AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &selectedSettable)
            let role = attribute(kAXRoleAttribute) as? String ?? ""
            let editable = (settable.boolValue || selectedSettable.boolValue || (attribute("AXEditable") as? Bool == true)) && [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role)
            var length = 0
            if let value = attribute(kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID() {
                var range = CFRange()
                if AXValueGetValue(value as! AXValue, .cfRange, &range) { length = range.length }
            }
            if length == 0 { length = (attribute(kAXSelectedTextAttribute) as? String)?.utf16.count ?? 0 }
            delete = shouldDelete(editable: editable, selectionLength: length)
        }
        let code: CGKeyCode = delete ? 51 : 9
        let flags: CGEventFlags = delete ? [] : .maskCommand
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }
}
