import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics

enum CorrectionAXError: Error, Equatable {
    case unavailable, unsupported, stale, limit, deadline, verification
}

struct CorrectionAXDeadline: Sendable {
    private let expires: UInt64
    init(milliseconds: Double = 500) {
        expires = DispatchTime.now().uptimeNanoseconds + UInt64(max(0, milliseconds) * 1_000_000)
    }
    func check() throws {
        guard DispatchTime.now().uptimeNanoseconds < expires else { throw CorrectionAXError.deadline }
    }
    fileprivate func timeout() throws -> Float {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now < expires else { throw CorrectionAXError.deadline }
        return min(0.15, Float(expires - now) / 1_000_000_000)
    }
}

/// Metadata only. No AXValue, selected text, or document payload is retained here.
struct CorrectionAXTarget: @unchecked Sendable {
    let pid: pid_t
    let element: AXUIElement
    let selection: CFRange
    let characterCount: Int
}

struct CorrectionAXReplacement: Sendable {
    let target: CorrectionAXTarget
    let range: CFRange
}

protocol LayoutCorrectionAXAdapting: AnyObject, Sendable {
    func capture(pid: pid_t, deadline: CorrectionAXDeadline) throws -> CorrectionAXTarget
    func matches(_ target: CorrectionAXTarget, deadline: CorrectionAXDeadline) throws -> Bool
    func read(_ target: CorrectionAXTarget, range: CFRange, deadline: CorrectionAXDeadline) throws -> String
    func replace(_ target: CorrectionAXTarget, range: CFRange, expectedText: String, replacement: String,
                 keepSelected: Bool, deadline: CorrectionAXDeadline, isFresh: () -> Bool) throws -> CorrectionAXReplacement
}

/// Owned only on main. Payload never leaves memory, and newer external Copy wins.
@MainActor
final class CorrectionClipboardLease {
    private let pasteboard: NSPasteboard
    private let registerSelfWrite: (Int) -> Void
    private var saved: [NSPasteboardItem]?
    private var ownedCount: Int

    init(text: String, pasteboard: NSPasteboard = .general,
         deadline: CorrectionAXDeadline = CorrectionAXDeadline(),
         registerSelfWrite: @escaping (Int) -> Void) throws {
        let initialCount = pasteboard.changeCount
        let original = pasteboard.pasteboardItems ?? []
        guard original.count <= 64 else { throw CorrectionAXError.limit }
        var snapshot: [NSPasteboardItem] = []
        var bytes = 0, representations = 0
        for item in original {
            let copy = NSPasteboardItem()
            for type in item.types {
                try deadline.check()
                representations += 1
                guard representations <= 256 else { throw CorrectionAXError.limit }
                guard let data = item.data(forType: type) else { throw CorrectionAXError.unavailable }
                guard data.count <= 32 * 1024 * 1024 - bytes else { throw CorrectionAXError.limit }
                bytes += data.count
                guard copy.setData(data, forType: type) else { throw CorrectionAXError.unavailable }
            }
            snapshot.append(copy)
        }
        try deadline.check()
        guard pasteboard.changeCount == initialCount else { throw CorrectionAXError.stale }
        self.pasteboard = pasteboard
        self.registerSelfWrite = registerSelfWrite
        saved = snapshot
        ownedCount = pasteboard.clearContents()
        registerSelfWrite(ownedCount)
        guard pasteboard.setString(text, forType: .string) else {
            restore(); throw CorrectionAXError.unavailable
        }
        ownedCount = pasteboard.changeCount
        registerSelfWrite(ownedCount)
    }

    func isOwned() -> Bool { saved != nil && pasteboard.changeCount == ownedCount }

    func restore() {
        guard let snapshot = saved else { return }
        saved = nil
        guard pasteboard.changeCount == ownedCount else { return }
        registerSelfWrite(pasteboard.clearContents())
        if !snapshot.isEmpty { _ = pasteboard.writeObjects(snapshot) }
        registerSelfWrite(pasteboard.changeCount)
    }

    func finish(dispatched: Bool, confirmed: Bool) {
        if dispatched && !confirmed {
            // A single queued paste may still be consuming the temporary text.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [self] in restore() }
        } else { restore() }
    }
}

/// Caller owns a serial background worker. The event tap never calls this adapter.
final class LayoutCorrectionAXAdapter: LayoutCorrectionAXAdapting {
    @MainActor private var registerPasteboardSelfWrite: ((Int) -> Void)?

    @MainActor
    func configurePasteboard(registerSelfWrite: @escaping (Int) -> Void) {
        registerPasteboardSelfWrite = registerSelfWrite
    }

    func capture(pid: pid_t, deadline: CorrectionAXDeadline) throws -> CorrectionAXTarget {
        try admit(pid)
        let system = AXUIElementCreateSystemWide()
        let application: AXUIElement = try attribute(system, kAXFocusedApplicationAttribute, deadline: deadline)
        guard try processID(application) == pid else { throw CorrectionAXError.stale }
        let element: AXUIElement = try attribute(application, kAXFocusedUIElementAttribute, deadline: deadline)
        guard try processID(element) == pid else { throw CorrectionAXError.stale }
        let role: String = try attribute(element, kAXRoleAttribute, deadline: deadline)
        let subrole: String? = try optionalAttribute(element, kAXSubroleAttribute, deadline: deadline)
        guard [kAXTextAreaRole as String, kAXTextFieldRole as String].contains(role),
              subrole != kAXSecureTextFieldSubrole as String else { throw CorrectionAXError.unsupported }
        let enabled: Bool? = try optionalAttribute(element, kAXEnabledAttribute, deadline: deadline)
        guard enabled != false,
              try isSettable(element, kAXValueAttribute, deadline: deadline),
              try isSettable(element, kAXSelectedTextRangeAttribute, deadline: deadline) else {
            throw CorrectionAXError.unsupported
        }
        try configure(element, deadline)
        var parameters: CFArray?
        guard AXUIElementCopyParameterizedAttributeNames(element, &parameters) == .success,
              let names = parameters as? [String], names.contains(kAXStringForRangeParameterizedAttribute as String)
        else { throw CorrectionAXError.unsupported }
        let range = try selection(element, deadline)
        let count: Int = try attribute(element, kAXNumberOfCharactersAttribute, deadline: deadline)
        guard count >= 0, valid(range, count: count) else { throw CorrectionAXError.stale }
        return CorrectionAXTarget(pid: pid, element: element, selection: range, characterCount: count)
    }

    func matches(_ target: CorrectionAXTarget, deadline: CorrectionAXDeadline) throws -> Bool {
        let current = try capture(pid: target.pid, deadline: deadline)
        return CFEqual(current.element, target.element) && equal(current.selection, target.selection)
            && current.characterCount == target.characterCount
    }

    func read(_ target: CorrectionAXTarget, range: CFRange, deadline: CorrectionAXDeadline) throws -> String {
        guard range.length <= 4096, valid(range, count: target.characterCount) else { throw CorrectionAXError.limit }
        if range.length == 0 { return "" }
        try admit(target.pid)
        let system = AXUIElementCreateSystemWide()
        let app: AXUIElement = try attribute(system, kAXFocusedApplicationAttribute, deadline: deadline)
        guard try processID(app) == target.pid else { throw CorrectionAXError.stale }
        let focused: AXUIElement = try attribute(app, kAXFocusedUIElementAttribute, deadline: deadline)
        guard CFEqual(focused, target.element), try processID(focused) == target.pid else {
            throw CorrectionAXError.stale
        }
        try configure(target.element, deadline)
        var copy = range
        guard let parameter = AXValueCreate(.cfRange, &copy) else { throw CorrectionAXError.unavailable }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(target.element,
            kAXStringForRangeParameterizedAttribute as CFString, parameter, &result) == .success,
            let text = result as? String, text.utf16.count == range.length else { throw CorrectionAXError.unavailable }
        try deadline.check()
        return text
    }

    func replace(
        _ target: CorrectionAXTarget, range: CFRange, expectedText: String, replacement: String,
        keepSelected: Bool, deadline: CorrectionAXDeadline, isFresh: () -> Bool
    ) throws -> CorrectionAXReplacement {
        guard range.length > 0, range.length <= 4096, expectedText.utf16.count == range.length,
              !replacement.isEmpty, replacement.utf16.count <= 4096,
              valid(range, count: target.characterCount) else { throw CorrectionAXError.limit }
        guard keepSelected ? equal(target.selection, range) :
            (target.selection.length == 0 && target.selection.location >= range.location + range.length)
        else { throw CorrectionAXError.stale }
        try validate(target, range: range, text: expectedText, deadline: deadline, isFresh: isFresh)
        // At most 256 context units in total; payload is never the entire AXValue.
        let leftRange = CFRange(location: max(0, range.location - 128), length: min(128, range.location))
        let rightStart = range.location + range.length
        let rightRange = CFRange(location: rightStart, length: min(128, target.characterCount - rightStart))
        let left = try read(target, range: leftRange, deadline: deadline)
        let right = try read(target, range: rightRange, deadline: deadline)
        // Choose one transport before touching the field. An unreadable clipboard
        // must remain untouched; use the already supported native Unicode event.
        // Never retry with another transport after dispatch.
        let lease: CorrectionClipboardLease?
        do {
            lease = try DispatchQueue.main.sync {
                guard let register = self.registerPasteboardSelfWrite else { throw CorrectionAXError.unavailable }
                return try CorrectionClipboardLease(text: replacement, deadline: deadline, registerSelfWrite: register)
            }
        } catch CorrectionAXError.unavailable { lease = nil }
          catch CorrectionAXError.limit { lease = nil }
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: lease == nil ? 0 : CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: lease == nil ? 0 : CGKeyCode(kVK_ANSI_V), keyDown: false)
        else {
            if let lease { DispatchQueue.main.sync { lease.restore() } }
            throw CorrectionAXError.unavailable
        }
        if lease != nil { down.flags = .maskCommand; up.flags = .maskCommand }
        else {
            let units = Array(replacement.utf16)
            units.withUnsafeBufferPointer { buffer in
                down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress!)
                up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress!)
            }
        }
        down.setIntegerValueField(.eventSourceUserData, value: SyntheticEventMarker.sourceUserData)
        up.setIntegerValueField(.eventSourceUserData, value: SyntheticEventMarker.sourceUserData)
        var dispatched = false, confirmed = false
        defer { if let lease { DispatchQueue.main.sync { lease.finish(dispatched: dispatched, confirmed: confirmed) } } }
        try validate(target, range: range, text: expectedText, deadline: deadline, isFresh: isFresh)
        guard try read(target, range: leftRange, deadline: deadline) == left,
              try read(target, range: rightRange, deadline: deadline) == right, isFresh() else {
            throw CorrectionAXError.stale
        }
        try setSelection(range, element: target.element, deadline: deadline)
        // Native AX selection setters may apply asynchronously. Wait for the
        // exact range in the original field, never select again or change focus.
        var selected: CorrectionAXTarget?
        while selected == nil {
            try deadline.check()
            guard isFresh() else { throw CorrectionAXError.stale }
            let current = try capture(pid: target.pid, deadline: deadline)
            guard CFEqual(current.element, target.element), current.characterCount == target.characterCount
                else { throw CorrectionAXError.stale }
            if equal(current.selection, range) { selected = current }
            else { Thread.sleep(forTimeInterval: 0.005) }
        }
        guard let selected, try read(selected, range: range, deadline: deadline) == expectedText,
              isFresh() else { throw CorrectionAXError.stale }
        try admit(target.pid); try deadline.check()
        guard DispatchQueue.main.sync(execute: { lease?.isOwned() ?? true }), isFresh() else { throw CorrectionAXError.stale }
        down.postToPid(target.pid); up.postToPid(target.pid)
        dispatched = true
        let delta = replacement.utf16.count - range.length
        let newRange = CFRange(location: range.location, length: replacement.utf16.count)
        let expectedCaret = range.location + replacement.utf16.count
        var accepted: CorrectionAXTarget?
        // Wait only for acceptance, never re-send the keyboard events.
        while accepted == nil {
            try deadline.check()
            guard isFresh() else { throw CorrectionAXError.stale }
            let current = try capture(pid: target.pid, deadline: deadline)
            guard CFEqual(current.element, target.element) else { throw CorrectionAXError.stale }
            if current.characterCount == target.characterCount + delta,
               equal(current.selection, CFRange(location: expectedCaret, length: 0)),
               try read(current, range: newRange, deadline: deadline) == replacement {
                let shiftedRight = CFRange(location: rightStart + delta, length: rightRange.length)
                guard try read(current, range: leftRange, deadline: deadline) == left,
                      try read(current, range: shiftedRight, deadline: deadline) == right else {
                    throw CorrectionAXError.verification
                }
                accepted = current
            } else {
                Thread.sleep(forTimeInterval: 0.005)
            }
        }
        let finalSelection = keepSelected ? newRange : CFRange(location: target.selection.location + delta, length: 0)
        guard let accepted, isFresh(), try matches(accepted, deadline: deadline) else {
            throw CorrectionAXError.stale
        }
        try setSelection(finalSelection, element: target.element, deadline: deadline)
        var final: CorrectionAXTarget?
        while final == nil {
            try deadline.check()
            guard isFresh() else { throw CorrectionAXError.stale }
            let current = try capture(pid: target.pid, deadline: deadline)
            guard CFEqual(current.element, target.element), current.characterCount == target.characterCount + delta,
                  try read(current, range: newRange, deadline: deadline) == replacement
                else { throw CorrectionAXError.verification }
            if equal(current.selection, finalSelection) { final = current }
            else { Thread.sleep(forTimeInterval: 0.005) }
        }
        guard let final else { throw CorrectionAXError.verification }
        confirmed = true
        return CorrectionAXReplacement(target: final, range: newRange)
    }

    private func validate(_ target: CorrectionAXTarget, range: CFRange, text: String,
                          deadline: CorrectionAXDeadline, isFresh: () -> Bool) throws {
        guard isFresh(), try matches(target, deadline: deadline),
              try read(target, range: range, deadline: deadline) == text, isFresh() else {
            throw CorrectionAXError.stale
        }
    }

    private func admit(_ pid: pid_t) throws {
        guard pid > 0, pid != ProcessInfo.processInfo.processIdentifier,
              AXIsProcessTrusted(), !IsSecureEventInputEnabled() else { throw CorrectionAXError.unavailable }
    }

    private func configure(_ element: AXUIElement, _ deadline: CorrectionAXDeadline) throws {
        let timeout = try deadline.timeout()
        guard AXUIElementSetMessagingTimeout(element, timeout) == .success else { throw CorrectionAXError.unavailable }
    }

    private func attribute<T>(_ element: AXUIElement, _ name: String,
                              deadline: CorrectionAXDeadline) throws -> T {
        try configure(element, deadline)
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success,
              let value = result as? T else { throw CorrectionAXError.unavailable }
        try deadline.check()
        return value
    }

    private func optionalAttribute<T>(_ element: AXUIElement, _ name: String,
                                      deadline: CorrectionAXDeadline) throws -> T? {
        try configure(element, deadline)
        var result: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &result)
        try deadline.check()
        guard error == .success || error == .attributeUnsupported || error == .noValue else {
            throw CorrectionAXError.unavailable
        }
        return result as? T
    }

    private func processID(_ element: AXUIElement) throws -> pid_t {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { throw CorrectionAXError.unavailable }
        return pid
    }

    private func selection(_ element: AXUIElement, _ deadline: CorrectionAXDeadline) throws -> CFRange {
        let value: AXValue = try attribute(element, kAXSelectedTextRangeAttribute, deadline: deadline)
        var range = CFRange()
        guard AXValueGetType(value) == .cfRange, AXValueGetValue(value, .cfRange, &range) else {
            throw CorrectionAXError.unavailable
        }
        return range
    }

    private func isSettable(_ element: AXUIElement, _ name: String,
                            deadline: CorrectionAXDeadline) throws -> Bool {
        try configure(element, deadline)
        var result = DarwinBoolean(false)
        let error = AXUIElementIsAttributeSettable(element, name as CFString, &result)
        try deadline.check()
        guard error == .success else { throw CorrectionAXError.unavailable }
        return result.boolValue
    }

    private func setSelection(_ range: CFRange, element: AXUIElement, deadline: CorrectionAXDeadline) throws {
        try configure(element, deadline)
        var copy = range
        guard let value = AXValueCreate(.cfRange, &copy),
              AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success else {
            throw CorrectionAXError.unavailable
        }
        try deadline.check()
    }

    private func valid(_ range: CFRange, count: Int) -> Bool {
        range.location >= 0 && range.length >= 0 && range.location <= count && range.length <= count - range.location
    }
    private func equal(_ a: CFRange, _ b: CFRange) -> Bool { a.location == b.location && a.length == b.length }
}
