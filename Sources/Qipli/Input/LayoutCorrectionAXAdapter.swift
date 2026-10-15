import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics

enum CorrectionAXError: Error, Equatable {
    case unavailable, unsupported, stale, limit, deadline, verification
}

enum LayoutCorrectionLimits {
    static let maximumTextUTF16Units = 12_288
}

struct CorrectionAXDeadline: Sendable {
    private let expires: UInt64
    init(milliseconds: Double = 500) {
        expires = DispatchTime.now().uptimeNanoseconds + UInt64(max(0, milliseconds) * 1_000_000)
    }
    func check() throws {
        guard DispatchTime.now().uptimeNanoseconds < expires else { throw CorrectionAXError.deadline }
    }
    var remainingMilliseconds: UInt64 { (expires > DispatchTime.now().uptimeNanoseconds) ?
        (expires - min(expires, DispatchTime.now().uptimeNanoseconds)) / 1_000_000 : 0 }
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
    func setDiagnosticTrace(_ trace: CorrectionDiagnosticTrace?)
    func capture(pid: pid_t, deadline: CorrectionAXDeadline) throws -> CorrectionAXTarget
    func matches(_ target: CorrectionAXTarget, deadline: CorrectionAXDeadline) throws -> Bool
    func read(_ target: CorrectionAXTarget, range: CFRange, deadline: CorrectionAXDeadline) throws -> String
    func replace(_ target: CorrectionAXTarget, range: CFRange, expectedText: String, replacement: String,
                 keepSelected: Bool, deadline: CorrectionAXDeadline, isFresh: () -> Bool) throws -> CorrectionAXReplacement
}

extension LayoutCorrectionAXAdapting {
    func setDiagnosticTrace(_ trace: CorrectionDiagnosticTrace?) {}
}

/// Owned only on main. Payload never leaves memory, and newer external Copy wins.
@MainActor
final class CorrectionClipboardLease {
    private let pasteboard: NSPasteboard
    private let registerSelfWrite: (Int) -> Void
    private var saved: [NSPasteboardItem]?
    private var ownedCount: Int
    private let trace: CorrectionDiagnosticTrace?

    init(text: String, pasteboard: NSPasteboard = .general,
         deadline: CorrectionAXDeadline = CorrectionAXDeadline(),
         registerSelfWrite: @escaping (Int) -> Void, trace: CorrectionDiagnosticTrace? = nil) throws {
        self.trace = trace
        func check(_ condition: Bool, _ check: DiagnosticCheck, _ error: CorrectionAXError,
                   expected: Int? = nil, observed: Int? = nil) throws {
            trace?(.clipboardLease, condition ? .passed : DiagnosticReason(ax: error),
                DiagnosticDetails(step: .clipboardSnapshot, check: check, expected: expected, observed: observed, matches: condition))
            guard condition else { throw error }
        }
        let initialCount = pasteboard.changeCount
        let original = pasteboard.pasteboardItems ?? []
        try check(original.count <= 64, .clipboardItemLimit, .limit, expected: 64, observed: original.count)
        var snapshot: [NSPasteboardItem] = []
        var bytes = 0, representations = 0
        for item in original {
            let copy = NSPasteboardItem()
            for type in item.types {
                try deadline.check()
                representations += 1
                try check(representations <= 256, .clipboardRepresentationLimit, .limit, expected: 256, observed: representations)
                guard let data = item.data(forType: type) else {
                    try check(false, .clipboardReadable, .unavailable); throw CorrectionAXError.unavailable
                }
                try check(data.count <= 32 * 1024 * 1024 - bytes, .clipboardByteLimit, .limit, expected: 32 * 1024 * 1024 - bytes, observed: data.count)
                bytes += data.count
                try check(copy.setData(data, forType: type), .clipboardCopy, .unavailable)
            }
            snapshot.append(copy)
        }
        try deadline.check()
        try check(pasteboard.changeCount == initialCount, .clipboardUnchanged, .stale, expected: initialCount, observed: pasteboard.changeCount)
        self.pasteboard = pasteboard
        self.registerSelfWrite = registerSelfWrite
        saved = snapshot
        ownedCount = pasteboard.clearContents()
        registerSelfWrite(ownedCount)
        let written = pasteboard.setString(text, forType: .string)
        trace?(.clipboardLease, written ? .passed : .unavailable,
            DiagnosticDetails(step: .clipboardWrite, check: .clipboardWrite, matches: written))
        guard written else { restore(); throw CorrectionAXError.unavailable }
        ownedCount = pasteboard.changeCount
        registerSelfWrite(ownedCount)
    }

    func isOwned() -> Bool { saved != nil && pasteboard.changeCount == ownedCount }

    func restore() {
        guard let snapshot = saved else { return }
        saved = nil
        guard pasteboard.changeCount == ownedCount else {
            trace?(.clipboardLease, .restoreSkipped, DiagnosticDetails(step: .clipboardRestore, check: .clipboardOwned,
                expected: ownedCount, observed: pasteboard.changeCount, matches: false)); return
        }
        registerSelfWrite(pasteboard.clearContents())
        let restored = snapshot.isEmpty || pasteboard.writeObjects(snapshot)
        registerSelfWrite(pasteboard.changeCount)
        trace?(.clipboardLease, restored ? .restored : .failed,
            DiagnosticDetails(step: .clipboardRestore, check: .clipboardRestored, matches: restored))
    }

    func finish(dispatched: Bool, confirmed: Bool) {
        trace?(.clipboardLease, .passed, DiagnosticDetails(step: .clipboardFinish, dispatched: dispatched, confirmed: confirmed))
        if dispatched && !confirmed {
            trace?(.clipboardLease, .restoreDeferred, DiagnosticDetails(step: .clipboardRestore))
            // A single queued paste may still be consuming the temporary text.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [self] in restore() }
        } else { restore() }
    }
}

protocol CorrectionAXClient: Sendable {
    func copyAttribute(_ element: AXUIElement, _ name: CFString) -> (AXError, CFTypeRef?)
    func parameterNames(_ element: AXUIElement) -> (AXError, CFTypeRef?)
    func stringForRange(_ element: AXUIElement, _ range: AXValue) -> (AXError, CFTypeRef?)
    func pid(_ element: AXUIElement) -> (AXError, pid_t)
    func timeout(_ element: AXUIElement, _ seconds: Float) -> AXError
    func settable(_ element: AXUIElement, _ name: CFString) -> (AXError, Bool)
    func setSelection(_ element: AXUIElement, _ range: AXValue) -> AXError
    func isTrusted() -> Bool
    func isSecureInput() -> Bool
}
struct SystemCorrectionAXClient: CorrectionAXClient {
    func copyAttribute(_ element: AXUIElement, _ name: CFString) -> (AXError, CFTypeRef?) {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name, &value)
        return (error, value)
    }
    func parameterNames(_ element: AXUIElement) -> (AXError, CFTypeRef?) {
        var value: CFArray?
        let error = AXUIElementCopyParameterizedAttributeNames(element, &value)
        return (error, value)
    }
    func stringForRange(_ element: AXUIElement, _ range: AXValue) -> (AXError, CFTypeRef?) {
        var value: CFTypeRef?
        let error = AXUIElementCopyParameterizedAttributeValue(element,
            kAXStringForRangeParameterizedAttribute as CFString, range, &value)
        return (error, value)
    }
    func pid(_ element: AXUIElement) -> (AXError, pid_t) {
        var pid: pid_t = 0
        let error = AXUIElementGetPid(element, &pid)
        return (error, pid)
    }
    func timeout(_ element: AXUIElement, _ seconds: Float) -> AXError { AXUIElementSetMessagingTimeout(element, seconds) }
    func settable(_ element: AXUIElement, _ name: CFString) -> (AXError, Bool) {
        var value = DarwinBoolean(false)
        let error = AXUIElementIsAttributeSettable(element, name, &value)
        return (error, value.boolValue)
    }
    func setSelection(_ element: AXUIElement, _ range: AXValue) -> AXError {
        AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, range)
    }
    func isTrusted() -> Bool { AXIsProcessTrusted() }
    func isSecureInput() -> Bool { IsSecureEventInputEnabled() }
}

private final class CorrectionDiagnosticTraceState: @unchecked Sendable {
    let lock = NSLock()
    var trace: CorrectionDiagnosticTrace?
}

/// Caller owns a serial background worker. The event tap never calls this adapter.
final class LayoutCorrectionAXAdapter: LayoutCorrectionAXAdapting, @unchecked Sendable {
    private let diagnosticTraceState = CorrectionDiagnosticTraceState()
    private let client: any CorrectionAXClient
    // Accessed exclusively by the existing serial correction worker.
    private var step: DiagnosticStep?
    init(client: any CorrectionAXClient = SystemCorrectionAXClient()) { self.client = client }

    private func inStep<T>(_ next: DiagnosticStep, _ body: () throws -> T) throws -> T {
        let parent = step
        step = next
        diagnosticTrace?(.checkpoint, .started, DiagnosticDetails(step: next, parentStep: parent))
        defer { step = parent }
        do {
            let result = try body()
            diagnosticTrace?(.checkpoint, .passed, DiagnosticDetails(step: next, parentStep: parent))
            return result
        } catch {
            let reason = (error as? CorrectionAXError).map(DiagnosticReason.init(ax:)) ?? .unexpected
            diagnosticTrace?(.checkpoint, reason, DiagnosticDetails(step: next, parentStep: parent))
            throw error
        }
    }

    private func verify(_ condition: @autoclosure () throws -> Bool, _ check: DiagnosticCheck,
                        _ error: CorrectionAXError = .stale, details: DiagnosticDetails = DiagnosticDetails()) throws {
        let result = try condition()
        var details = details
        details.step = step; details.check = check; details.matches = result
        diagnosticTrace?(.validation, result ? .passed : .mismatch, details)
        guard result else { throw error }
    }

    private func checkDeadline(_ deadline: CorrectionAXDeadline) throws {
        do { try deadline.check() }
        catch {
            diagnosticTrace?(.validation, .deadline,
                DiagnosticDetails(step: step, check: .deadline, remainingMilliseconds: deadline.remainingMilliseconds))
            throw error
        }
    }

    private func call<T>(_ api: DiagnosticAPI, _ attribute: DiagnosticAXAttribute? = nil,
                         deadline: CorrectionAXDeadline? = nil, optional: Bool = false,
                         failure: CorrectionAXError = .unavailable, deadlineFirst: Bool = false,
                         details: DiagnosticDetails = DiagnosticDetails(), _ body: () -> (AXError, T)) throws -> T {
        let began = DispatchTime.now().uptimeNanoseconds
        var evidence = details
        evidence.step = step; evidence.api = api; evidence.attribute = attribute
        evidence.remainingMilliseconds = deadline?.remainingMilliseconds
        diagnosticTrace?(.ax, .started, evidence)
        let (error, value) = body()
        let allowed = error == .success || (optional && (error == .attributeUnsupported || error == .noValue))
        evidence.axError = error.rawValue
        evidence.callMicroseconds = (DispatchTime.now().uptimeNanoseconds &- began) / 1_000
        evidence.remainingMilliseconds = deadline?.remainingMilliseconds
        diagnosticTrace?(.ax, allowed ? .passed : .axFailure, evidence)
        if deadlineFirst, let deadline { try checkDeadline(deadline) }
        guard allowed else { throw failure }
        return value
    }
    private var diagnosticTrace: CorrectionDiagnosticTrace? {
        diagnosticTraceState.lock.withLock { diagnosticTraceState.trace }
    }

    func setDiagnosticTrace(_ trace: CorrectionDiagnosticTrace?) {
        diagnosticTraceState.lock.withLock { diagnosticTraceState.trace = trace }
    }

    @MainActor private var registerPasteboardSelfWrite: ((Int) -> Void)?

    @MainActor
    func configurePasteboard(registerSelfWrite: @escaping (Int) -> Void) {
        registerPasteboardSelfWrite = registerSelfWrite
    }

    func capture(pid: pid_t, deadline: CorrectionAXDeadline) throws -> CorrectionAXTarget {
        return try inStep(.capture) {
            try admit(pid)
            let system = AXUIElementCreateSystemWide()
            let application: AXUIElement = try attribute(system, .focusedApplication, deadline: deadline)
            try verify(try processID(application) == pid, .applicationMatches)
            let element: AXUIElement = try attribute(application, .focusedElement, deadline: deadline)
            try verify(try processID(element) == pid, .targetProcess)
            let role: String = try attribute(element, .role, deadline: deadline)
            let subrole: String? = try optionalAttribute(element, .subrole, deadline: deadline)
            let fieldRole: DiagnosticFieldRole = subrole == kAXSecureTextFieldSubrole as String ? .secureTextField :
                role == kAXTextAreaRole as String ? .textArea : role == kAXTextFieldRole as String ? .textField : .other
            try verify([kAXTextAreaRole as String, kAXTextFieldRole as String].contains(role) &&
                subrole != kAXSecureTextFieldSubrole as String, .roleSupported, .unsupported,
                details: DiagnosticDetails(role: fieldRole))
            let enabled: Bool? = try optionalAttribute(element, .enabled, deadline: deadline)
            try verify(enabled != false, .fieldEnabled, .unsupported)
            try verify(try isSettable(element, .value, deadline: deadline), .valueSettable, .unsupported)
            try verify(try isSettable(element, .selectedRange, deadline: deadline), .selectionSettable, .unsupported)
            try configure(element, deadline)
            let parameters = try call(.copyParameterizedNames, deadline: deadline, failure: .unsupported) { client.parameterNames(element) }
            try verify((parameters as? [String])?.contains(kAXStringForRangeParameterizedAttribute as String) == true,
                .rangeReadSupported, .unsupported)
            let range = try selection(element, deadline)
            let count: Int = try attribute(element, .characterCount, deadline: deadline)
            try verify(count >= 0 && valid(range, count: count), .rangeValid,
                details: DiagnosticDetails(selectionLocation: range.location, selectionLength: range.length, characterCount: count))
            return CorrectionAXTarget(pid: pid, element: element, selection: range, characterCount: count)
        }
    }

    func matches(_ target: CorrectionAXTarget, deadline: CorrectionAXDeadline) throws -> Bool {
        return try inStep(.matches) {
            let current = try capture(pid: target.pid, deadline: deadline)
            let elementMatches = CFEqual(current.element, target.element)
            let selectionMatches = equal(current.selection, target.selection)
            let countMatches = current.characterCount == target.characterCount
            diagnosticTrace?(.validation, elementMatches ? .passed : .mismatch,
                DiagnosticDetails(step: step, check: .elementMatches, matches: elementMatches))
            diagnosticTrace?(.validation, selectionMatches ? .passed : .mismatch,
                DiagnosticDetails(step: step, check: .selectionMatches,
                    rangeLocation: target.selection.location, rangeLength: target.selection.length,
                    selectionLocation: current.selection.location, selectionLength: current.selection.length, matches: selectionMatches))
            diagnosticTrace?(.validation, countMatches ? .passed : .mismatch,
                DiagnosticDetails(step: step, check: .countMatches,
                    expected: target.characterCount, observed: current.characterCount, matches: countMatches))
            return elementMatches && selectionMatches && countMatches
        }
    }

    func read(_ target: CorrectionAXTarget, range: CFRange, deadline: CorrectionAXDeadline) throws -> String {
        return try inStep(.read) {
            try verify(range.length <= LayoutCorrectionLimits.maximumTextUTF16Units && valid(range, count: target.characterCount),
                .readLimit, .limit, details: DiagnosticDetails(rangeLocation: range.location, rangeLength: range.length,
                    characterCount: target.characterCount))
            if range.length == 0 { return "" }
            try admit(target.pid)
            let system = AXUIElementCreateSystemWide()
            let app: AXUIElement = try attribute(system, .focusedApplication, deadline: deadline)
            try verify(try processID(app) == target.pid, .applicationMatches)
            let focused: AXUIElement = try attribute(app, .focusedElement, deadline: deadline)
            try verify(CFEqual(focused, target.element), .elementMatches)
            try verify(try processID(focused) == target.pid, .targetProcess)
            try configure(target.element, deadline)
            var copy = range
            guard let parameter = AXValueCreate(.cfRange, &copy) else {
                diagnosticTrace?(.ax, .unavailable, DiagnosticDetails(step: step, api: .createRange))
                throw CorrectionAXError.unavailable
            }
            let result = try call(.copyStringForRange, .stringForRange, deadline: deadline,
                details: DiagnosticDetails(rangeLocation: range.location, rangeLength: range.length)) {
                client.stringForRange(target.element, parameter)
            }
            guard let text = result as? String else {
                diagnosticTrace?(.validation, .typeMismatch, DiagnosticDetails(step: step, api: .copyStringForRange,
                    attribute: .stringForRange, check: .resultType, expectedType: .string, observedType: Self.valueType(result), rangeLocation: range.location, rangeLength: range.length))
                throw CorrectionAXError.unavailable
            }
            let units = text.utf16.count
            diagnosticTrace?(.validation, units == range.length ? .passed : .lengthMismatch,
                DiagnosticDetails(step: step, api: .copyStringForRange, attribute: .stringForRange, check: .readLength,
                    rangeLocation: range.location, rangeLength: range.length, expected: range.length, observed: units))
            guard units == range.length else { throw CorrectionAXError.unavailable }
            try checkDeadline(deadline)
            return text
        }
    }

    func replace(
        _ target: CorrectionAXTarget, range: CFRange, expectedText: String, replacement: String,
        keepSelected: Bool, deadline: CorrectionAXDeadline, isFresh: () -> Bool
    ) throws -> CorrectionAXReplacement {
        return try inStep(.replacement) {
            try verify(range.length > 0 && range.length <= LayoutCorrectionLimits.maximumTextUTF16Units &&
                expectedText.utf16.count == range.length && !replacement.isEmpty &&
                replacement.utf16.count <= LayoutCorrectionLimits.maximumTextUTF16Units &&
                valid(range, count: target.characterCount), .replacementLimit, .limit,
                details: DiagnosticDetails(rangeLocation: range.location, rangeLength: range.length,
                    characterCount: target.characterCount, expected: expectedText.utf16.count, observed: replacement.utf16.count))
            try verify(keepSelected ? equal(target.selection, range) :
                (target.selection.length == 0 && target.selection.location >= range.location + range.length), .replacementSelection)
            try validate(target, range: range, text: expectedText, deadline: deadline, isFresh: isFresh)
            // Read only the existing bounded context. Diagnostics records comparisons, never its content.
            let leftRange = CFRange(location: max(0, range.location - 128), length: min(128, range.location))
            let rightStart = range.location + range.length
            let rightRange = CFRange(location: rightStart, length: min(128, target.characterCount - rightStart))
            let left = try inStep(.leftContext) { try read(target, range: leftRange, deadline: deadline) }
            let right = try inStep(.rightContext) { try read(target, range: rightRange, deadline: deadline) }
            // Select transport once before mutation. Never retry after dispatch.
            let lease: CorrectionClipboardLease?
            diagnosticTrace?(.clipboardLease, .started)
            do {
                lease = try DispatchQueue.main.sync {
                    guard let register = self.registerPasteboardSelfWrite else {
                        self.diagnosticTrace?(.clipboardLease, .unavailable, DiagnosticDetails(check: .clipboardRegistration))
                        throw CorrectionAXError.unavailable
                    }
                    return try CorrectionClipboardLease(text: replacement, deadline: deadline,
                        registerSelfWrite: register, trace: self.diagnosticTrace)
                }
                diagnosticTrace?(.clipboardLease, .passed)
            } catch CorrectionAXError.unavailable {
                diagnosticTrace?(.clipboardLease, .unavailable); lease = nil
            } catch CorrectionAXError.limit {
                diagnosticTrace?(.clipboardLease, .limit); lease = nil
            }
            guard let source = CGEventSource(stateID: .privateState),
                  let down = CGEvent(keyboardEventSource: source, virtualKey: lease == nil ? 0 : CGKeyCode(kVK_ANSI_V), keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: lease == nil ? 0 : CGKeyCode(kVK_ANSI_V), keyDown: false)
            else {
                diagnosticTrace?(.validation, .unavailable, DiagnosticDetails(check: .eventCreation))
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
            defer {
                diagnosticTrace?(.checkpoint, .passed, DiagnosticDetails(step: .completion, dispatched: dispatched, confirmed: confirmed))
                if let lease { DispatchQueue.main.sync { lease.finish(dispatched: dispatched, confirmed: confirmed) } }
            }
            try inStep(.preDispatchValidation) {
                try validate(target, range: range, text: expectedText, deadline: deadline, isFresh: isFresh)
                try verify(try read(target, range: leftRange, deadline: deadline) == left, .leftContextMatches)
                try verify(try read(target, range: rightRange, deadline: deadline) == right, .rightContextMatches)
                try verify(isFresh(), .operationFresh)
            }
            try inStep(.selectReplacement) { try setSelection(range, element: target.element, deadline: deadline) }
            var selected: CorrectionAXTarget?
            try inStep(.waitSelection) {
                var iteration = 0
                while selected == nil {
                    try checkDeadline(deadline)
                    try verify(isFresh(), .operationFresh)
                    let current = try capture(pid: target.pid, deadline: deadline)
                    try verify(CFEqual(current.element, target.element), .elementMatches)
                    try verify(current.characterCount == target.characterCount, .countMatches)
                    iteration += 1
                    let matches = equal(current.selection, range)
                    diagnosticTrace?(.validation, matches ? .passed : .mismatch,
                        DiagnosticDetails(step: .waitSelection, check: .selectionMatches,
                            rangeLocation: range.location, rangeLength: range.length,
                            selectionLocation: current.selection.location, selectionLength: current.selection.length, iteration: iteration))
                    if matches { selected = current }
                    else { Thread.sleep(forTimeInterval: 0.005) }
                }
            }
            guard let selected else { throw CorrectionAXError.stale }
            try inStep(.selectedText) {
                try verify(try read(selected, range: range, deadline: deadline) == expectedText, .expectedTextMatches)
                try verify(isFresh(), .operationFresh)
            }
            try admit(target.pid); try checkDeadline(deadline)
            try verify(DispatchQueue.main.sync(execute: { lease?.isOwned() ?? true }), .clipboardOwned)
            try verify(isFresh(), .operationFresh)
            diagnosticTrace?(lease == nil ? .unicodePaste : .nativePaste, .started, DiagnosticDetails(dispatched: false))
            down.postToPid(target.pid); up.postToPid(target.pid)
            dispatched = true
            diagnosticTrace?(lease == nil ? .unicodePaste : .nativePaste, .passed, DiagnosticDetails(dispatched: true))
            let delta = replacement.utf16.count - range.length
            let newRange = CFRange(location: range.location, length: replacement.utf16.count)
            let expectedCaret = range.location + replacement.utf16.count
            diagnosticTrace?(.postcondition, .started)
            var accepted: CorrectionAXTarget?
            try inStep(.waitPaste) {
                var iteration = 0
                // Wait for acceptance; never re-send events.
                while accepted == nil {
                    try checkDeadline(deadline)
                    try verify(isFresh(), .operationFresh)
                    let current = try capture(pid: target.pid, deadline: deadline)
                    try verify(CFEqual(current.element, target.element), .elementMatches)
                    iteration += 1
                    let countMatches = current.characterCount == target.characterCount + delta
                    diagnosticTrace?(.validation, countMatches ? .passed : .mismatch,
                        DiagnosticDetails(step: .waitPaste, check: .pasteCount, expected: target.characterCount + delta,
                            observed: current.characterCount, iteration: iteration))
                    let caretMatches = equal(current.selection, CFRange(location: expectedCaret, length: 0))
                    diagnosticTrace?(.validation, caretMatches ? .passed : .mismatch,
                        DiagnosticDetails(step: .waitPaste, check: .pasteCaret,
                            selectionLocation: current.selection.location, selectionLength: current.selection.length,
                            expected: expectedCaret, iteration: iteration))
                    // Preserve short-circuiting: no additional payload reads for diagnostics.
                    var textMatches = false
                    if countMatches && caretMatches {
                        textMatches = try read(current, range: newRange, deadline: deadline) == replacement
                        diagnosticTrace?(.validation, textMatches ? .passed : .mismatch,
                            DiagnosticDetails(step: .waitPaste, check: .pasteText, matches: textMatches, iteration: iteration))
                    }
                    if countMatches && caretMatches && textMatches {
                        let shiftedRight = CFRange(location: rightStart + delta, length: rightRange.length)
                        try inStep(.verifyContext) {
                            try verify(try read(current, range: leftRange, deadline: deadline) == left, .leftContextMatches, .verification)
                            try verify(try read(current, range: shiftedRight, deadline: deadline) == right, .rightContextMatches, .verification)
                        }
                        accepted = current
                    } else { Thread.sleep(forTimeInterval: 0.005) }
                }
            }
            let finalSelection = keepSelected ? newRange : CFRange(location: target.selection.location + delta, length: 0)
            guard let accepted else { throw CorrectionAXError.stale }
            try verify(isFresh(), .operationFresh)
            try verify(try matches(accepted, deadline: deadline), .finalTarget)
            try inStep(.finalSelection) { try setSelection(finalSelection, element: target.element, deadline: deadline) }
            var final: CorrectionAXTarget?
            try inStep(.waitFinalSelection) {
                var iteration = 0
                while final == nil {
                    try checkDeadline(deadline)
                    try verify(isFresh(), .operationFresh)
                    let current = try capture(pid: target.pid, deadline: deadline)
                    try verify(CFEqual(current.element, target.element), .elementMatches, .verification)
                    try verify(current.characterCount == target.characterCount + delta, .countMatches, .verification)
                    try verify(try read(current, range: newRange, deadline: deadline) == replacement, .finalText, .verification)
                    iteration += 1
                    let matches = equal(current.selection, finalSelection)
                    diagnosticTrace?(.validation, matches ? .passed : .mismatch,
                        DiagnosticDetails(step: .waitFinalSelection, check: .finalRange,
                            rangeLocation: finalSelection.location, rangeLength: finalSelection.length,
                            selectionLocation: current.selection.location, selectionLength: current.selection.length, iteration: iteration))
                    if matches { final = current }
                    else { Thread.sleep(forTimeInterval: 0.005) }
                }
            }
            guard let final else { throw CorrectionAXError.verification }
            diagnosticTrace?(.postcondition, .passed)
            confirmed = true
            return CorrectionAXReplacement(target: final, range: newRange)
        }
    }

    private func validate(_ target: CorrectionAXTarget, range: CFRange, text: String,
                          deadline: CorrectionAXDeadline, isFresh: () -> Bool) throws {
        try inStep(.validate) {
            try verify(isFresh(), .operationFresh)
            try verify(try matches(target, deadline: deadline), .finalTarget)
            try verify(try read(target, range: range, deadline: deadline) == text, .expectedTextMatches)
            try verify(isFresh(), .operationFresh)
        }
    }

    private func admit(_ pid: pid_t) throws {
        try verify(pid > 0 && pid != ProcessInfo.processInfo.processIdentifier, .targetProcess, .unavailable)
        let trusted = client.isTrusted()
        diagnosticTrace?(.admission, trusted ? .passed : .permissionDenied, DiagnosticDetails(step: step, check: .permission, matches: trusted))
        guard trusted else { throw CorrectionAXError.unavailable }
        let secure = client.isSecureInput()
        diagnosticTrace?(.admission, secure ? .secureInput : .passed, DiagnosticDetails(step: step, check: .secureInput, matches: !secure))
        guard !secure else { throw CorrectionAXError.unavailable }
    }

    private func configure(_ element: AXUIElement, _ deadline: CorrectionAXDeadline) throws {
        try checkDeadline(deadline)
        let timeout = try deadline.timeout()
        _ = try call(.setMessagingTimeout, deadline: deadline) { (client.timeout(element, timeout), ()) }
    }

    private func attribute<T>(_ element: AXUIElement, _ name: DiagnosticAXAttribute,
                              deadline: CorrectionAXDeadline) throws -> T {
        try configure(element, deadline)
        let result = try call(.copyAttribute, name, deadline: deadline) { client.copyAttribute(element, name.axName) }
        guard Self.valueType(result) == name.expectedType, let value = result as? T else {
            diagnosticTrace?(.validation, .typeMismatch, DiagnosticDetails(step: step, api: .copyAttribute, attribute: name,
                check: .resultType, expectedType: name.expectedType, observedType: Self.valueType(result)))
            throw CorrectionAXError.unavailable
        }
        try checkDeadline(deadline)
        return value
    }

    private func optionalAttribute<T>(_ element: AXUIElement, _ name: DiagnosticAXAttribute,
                                      deadline: CorrectionAXDeadline) throws -> T? {
        try configure(element, deadline)
        let result = try call(.copyAttribute, name, deadline: deadline, optional: true, deadlineFirst: true) { client.copyAttribute(element, name.axName) }
        try checkDeadline(deadline)
        // Missing optional attributes are legitimate, but a present wrong type is evidence.
        if result != nil && !(result is T) {
            diagnosticTrace?(.validation, .typeMismatch, DiagnosticDetails(step: step, api: .copyAttribute, attribute: name, check: .resultType,
                    expectedType: name.expectedType, observedType: Self.valueType(result)))
        }
        return result as? T
    }

    private func processID(_ element: AXUIElement) throws -> pid_t {
        try call(.getPID) { client.pid(element) }
    }

    private func selection(_ element: AXUIElement, _ deadline: CorrectionAXDeadline) throws -> CFRange {
        let value: AXValue = try attribute(element, .selectedRange, deadline: deadline)
        var range = CFRange()
        try verify(AXValueGetType(value) == .cfRange, .rangeType, .unavailable)
        try verify(AXValueGetValue(value, .cfRange, &range), .rangeDecode, .unavailable)
        return range
    }

    private func isSettable(_ element: AXUIElement, _ name: DiagnosticAXAttribute,
                            deadline: CorrectionAXDeadline) throws -> Bool {
        try configure(element, deadline)
        let result = try call(.isAttributeSettable, name, deadline: deadline) { client.settable(element, name.axName) }
        try checkDeadline(deadline)
        return result
    }

    private func setSelection(_ range: CFRange, element: AXUIElement, deadline: CorrectionAXDeadline) throws {
        try configure(element, deadline)
        var copy = range
        guard let value = AXValueCreate(.cfRange, &copy) else {
            diagnosticTrace?(.ax, .unavailable, DiagnosticDetails(step: step, api: .createRange, attribute: .selectedRange))
            throw CorrectionAXError.unavailable
        }
        _ = try call(.setSelectedRange, .selectedRange, deadline: deadline,
            details: DiagnosticDetails(rangeLocation: range.location, rangeLength: range.length)) { (client.setSelection(element, value), ()) }
        try checkDeadline(deadline)
    }

    private static func valueType(_ value: CFTypeRef?) -> DiagnosticValueType {
        guard let value else { return .missing }
        switch CFGetTypeID(value) {
        case CFStringGetTypeID(): return .string
        case CFBooleanGetTypeID(): return .boolean
        case CFNumberGetTypeID(): return .number
        case CFArrayGetTypeID(): return .array
        case AXUIElementGetTypeID(): return .axElement
        case AXValueGetTypeID(): return .axValue
        case CFDataGetTypeID(): return .data
        default: return .other
        }
    }

    private func valid(_ range: CFRange, count: Int) -> Bool {
        range.location >= 0 && range.length >= 0 && range.location <= count && range.length <= count - range.location
    }
    private func equal(_ a: CFRange, _ b: CFRange) -> Bool { a.location == b.location && a.length == b.length }
}

private extension DiagnosticAXAttribute {
    var expectedType: DiagnosticValueType {
        switch self {
        case .focusedApplication, .focusedElement: .axElement
        case .role, .subrole, .value, .stringForRange: .string
        case .enabled: .boolean
        case .selectedRange: .axValue
        case .characterCount: .number
        }
    }
    var axName: CFString {
        switch self {
        case .focusedApplication: kAXFocusedApplicationAttribute as CFString
        case .focusedElement: kAXFocusedUIElementAttribute as CFString
        case .role: kAXRoleAttribute as CFString
        case .subrole: kAXSubroleAttribute as CFString
        case .enabled: kAXEnabledAttribute as CFString
        case .value: kAXValueAttribute as CFString
        case .selectedRange: kAXSelectedTextRangeAttribute as CFString
        case .characterCount: kAXNumberOfCharactersAttribute as CFString
        case .stringForRange: kAXStringForRangeParameterizedAttribute as CFString
        }
    }
}
