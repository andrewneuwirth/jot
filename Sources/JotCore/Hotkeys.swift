import AppKit
import Carbon

final class GlobalHotkeys {
    var smartPaste: (() -> Void)?
    var toggle: (() -> Void)?
    var cancel: (() -> Void)?
    var isRecording: (() -> Bool)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var globeDown = false
    private var swallowedJ = false
    private var swallowedV = false
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
            globeDown = false; swallowedJ = false; swallowedV = false
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .flagsChanged, code == 63 {
            let down = event.flags.contains(.maskSecondaryFn)
            let modifiers = event.flags.intersection([.maskControl, .maskCommand, .maskAlternate, .maskShift])
            if down, !globeDown, modifiers.isEmpty { globeDown = true; DispatchQueue.main.async { [weak self] in self?.toggle?() }; return nil }
            if !down, globeDown { globeDown = false; return nil }
        }
        if code == 9 {
            if type == .keyUp, swallowedV {
                swallowedV = false
                DispatchQueue.main.async { [weak self] in self?.smartPaste?() }
                return nil
            }
            if type == .keyDown, event.flags.intersection([.maskControl, .maskCommand, .maskAlternate, .maskShift]) == [.maskControl, .maskCommand] {
                swallowedV = true
                return nil
            }
        }
        if code == 38 {
            if type == .keyUp, swallowedJ { swallowedJ = false; return nil }
            if type == .keyDown, event.flags.intersection([.maskControl, .maskCommand, .maskAlternate, .maskShift]) == [.maskControl, .maskCommand] {
                if !swallowedJ { swallowedJ = true; DispatchQueue.main.async { [weak self] in self?.toggle?() } }
                return nil
            }
        }
        if type == .keyDown, code == 53, isRecording?() == true {
            DispatchQueue.main.async { [weak self] in self?.cancel?() }; return nil
        }
        return Unmanaged.passUnretained(event)
    }
    deinit { if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }; if let tap { CFMachPortInvalidate(tap) } }
}
