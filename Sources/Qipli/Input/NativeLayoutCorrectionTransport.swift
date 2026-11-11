import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics

/// Native replacement verifies selection metadata and native Copy before inserting.
@MainActor
protocol LayoutCorrectionTransport: AnyObject {
    var mutationBegan: Bool { get }
    func prepare(pid: pid_t) async throws -> Bool? // true only when AX reports an empty selection
    func copySelection(pid: pid_t, isFresh: () -> Bool) async throws -> String?
    func pasteSelection(_ text: String, pid: pid_t, isFresh: () -> Bool) async throws
    func replay(originalText: String, text: String, pid: pid_t, isFresh: () -> Bool) async throws
    func finish() async
    func setTrace(_ trace: CorrectionDiagnosticTrace?)
}

@MainActor
final class NativeLayoutCorrectionTransport: LayoutCorrectionTransport {
    enum ReplayMethod { case unicode, paste }
    private let replayMethod: ReplayMethod
    private let axClient: any CorrectionAXClient
    private let frontmostPID: () -> pid_t?
    private let postEvent: (CGEvent, pid_t) -> Void
    private struct Focus: @unchecked Sendable {
        let element: AXUIElement
        let selection: CFRange?
        var selectionEmpty: Bool? { selection.map { $0.length == 0 } }
    }
    private var focus: Focus?
    private let pasteboard: NSPasteboard
    private var registerSelfWrite: ((Int) -> Void)?
    private var beginCopyObservation: (() -> Void)?
    private var endCopyObservation: (() -> Void)?
    private var lease: CorrectionClipboardLease?
    private var trace: CorrectionDiagnosticTrace?
    private var pasteDispatched = false
    private(set) var mutationBegan = false

    init(pasteboard: NSPasteboard = .general, replayMethod: ReplayMethod = .paste,
         axClient: any CorrectionAXClient = SystemCorrectionAXClient(),
         frontmostPID: @escaping () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier },
         postEvent: @escaping (CGEvent, pid_t) -> Void = { event, pid in event.postToPid(pid) }) {
        self.pasteboard = pasteboard; self.replayMethod = replayMethod
        self.axClient = axClient; self.frontmostPID = frontmostPID; self.postEvent = postEvent
    }

    func configurePasteboard(registerSelfWrite: @escaping (Int) -> Void,
                             beginCopy: @escaping () -> Void, endCopy: @escaping () -> Void) {
        self.registerSelfWrite = registerSelfWrite
        beginCopyObservation = beginCopy; endCopyObservation = endCopy
    }
    func setTrace(_ trace: CorrectionDiagnosticTrace?) { self.trace = trace }

    func prepare(pid: pid_t) async throws -> Bool? {
        mutationBegan = false
        try check(pid: pid, isFresh: { true }, step: .admission)
        // A single metadata preflight on the AX worker. No text reads or settable checks.
        let diagnosticTrace = trace, client = axClient
        let context: Focus = try await withCheckedThrowingContinuation { continuation in
            CorrectionAXWorker.queue.async {
                do { continuation.resume(returning: try Self.textFieldContext(pid: pid, client: client, trace: diagnosticTrace)) }
                catch { continuation.resume(throwing: error) }
            }
        }
        focus = context
        return context.selectionEmpty
    }

    nonisolated static func textFieldMetadata(pid: pid_t, client: any CorrectionAXClient = SystemCorrectionAXClient(),
                                               trace: CorrectionDiagnosticTrace? = nil) throws -> Bool? {
        try textFieldContext(pid: pid, client: client, trace: trace).selectionEmpty
    }

    nonisolated private static func textFieldContext(pid: pid_t, client: any CorrectionAXClient = SystemCorrectionAXClient(),
                                               trace: CorrectionDiagnosticTrace? = nil, step: DiagnosticStep = .admission) throws -> Focus {
        let app = AXUIElementCreateApplication(pid)
        _ = client.timeout(app, 0.15)
        func attribute(_ element: AXUIElement, _ name: String, _ diagnostic: DiagnosticAXAttribute) throws -> CFTypeRef? {
            let began = DispatchTime.now().uptimeNanoseconds
            let (status, value) = client.copyAttribute(element, name as CFString)
            trace?(.ax, [.success, .attributeUnsupported, .noValue].contains(status) ? .passed : .axFailure,
                DiagnosticDetails(step: step, api: .copyAttribute, attribute: diagnostic,
                    axError: status.rawValue, callMicroseconds: (DispatchTime.now().uptimeNanoseconds &- began) / 1_000))
            if status == .attributeUnsupported || status == .noValue { return nil }
            guard status == .success else { throw CorrectionAXError.unavailable }
            return value
        }
        guard let raw = try attribute(app, kAXFocusedUIElementAttribute, .focusedElement),
              CFGetTypeID(raw) == AXUIElementGetTypeID() else { throw CorrectionAXError.unavailable }
        let element = unsafeBitCast(raw, to: AXUIElement.self)
        _ = client.timeout(element, 0.15)
        let (pidStatus, elementPID) = client.pid(element)
        guard pidStatus == .success, elementPID == pid else {
            trace?(.admission, .stale, DiagnosticDetails(step: step, api: .getPID,
                check: .targetProcess, axError: pidStatus.rawValue, matches: false))
            throw CorrectionAXError.stale
        }
        guard let role = try attribute(element, kAXRoleAttribute, .role) as? String else { throw CorrectionAXError.unsupported }
        let subrole = try attribute(element, kAXSubroleAttribute, .subrole) as? String
        guard role != kAXSecureTextFieldSubrole as String, subrole != kAXSecureTextFieldSubrole as String else {
            trace?(.admission, .secureInput); throw CorrectionAXError.unsupported
        }
        // AXEditable is optional for known text roles. Its absence/timeout must
        // not reintroduce a capability prerequisite; an explicit false still refuses.
        let editableValue = (try? attribute(element, "AXEditable", .editable)) as? Bool
        if editableValue == false {
            trace?(.admission, .unsupported, DiagnosticDetails(step: step, check: .fieldEnabled, matches: false))
            throw CorrectionAXError.unsupported
        }
        let textRoles = [kAXTextFieldRole as String, kAXTextAreaRole as String, kAXComboBoxRole as String, "AXSearchField"]
        guard textRoles.contains(role) || editableValue == true else {
            trace?(.admission, .unsupported, DiagnosticDetails(step: step, check: .roleSupported, matches: false))
            throw CorrectionAXError.unsupported
        }
        // Missing selected-range support is allowed. Copy supplies the selection.
        // A timeout is also optional here: no text mutation relies on this metadata.
        let (rangeStatus, rangeValue) = client.copyAttribute(element, kAXSelectedTextRangeAttribute as CFString)
        guard rangeStatus == .success, let value = rangeValue, CFGetTypeID(value) == AXValueGetTypeID() else { return Focus(element: element, selection: nil) }
        var range = CFRange()
        guard AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cfRange, &range), range.location >= 0, range.length >= 0 else { return Focus(element: element, selection: nil) }
        return Focus(element: element, selection: range)
    }

    func copySelection(pid: pid_t, isFresh: () -> Bool) async throws -> String? {
        try await verifyFocus(pid: pid, isFresh: isFresh)
        try check(pid: pid, isFresh: isFresh)
        guard let registerSelfWrite, let beginCopyObservation, let endCopyObservation else { throw CorrectionAXError.unavailable }
        let transaction = try lease ?? CorrectionClipboardLease(pasteboard: pasteboard,
            registerSelfWrite: registerSelfWrite, trace: trace)
        lease = transaction
        beginCopyObservation()
        defer { endCopyObservation() }
        let emptyCount = try transaction.beginCopy()
        trace?(.nativeCopy, .started)
        try send(key: CGKeyCode(kVK_ANSI_C), flags: .maskCommand, pid: pid, isFresh: isFresh)
        let began = DispatchTime.now().uptimeNanoseconds
        while DispatchTime.now().uptimeNanoseconds - began < 200_000_000 {
            try check(pid: pid, isFresh: isFresh)
            if let text = try transaction.acceptCopy(after: emptyCount) {
                try await verifyFocus(pid: pid, isFresh: isFresh)
                trace?(.nativeCopy, .passed)
                return text
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        trace?(.nativeCopy, .unavailable)
        transaction.restore(); lease = nil
        return nil
    }

    func pasteSelection(_ text: String, pid: pid_t, isFresh: () -> Bool) async throws {
        try await pasteSelection(text, pid: pid, expectedRange: nil, isFresh: isFresh)
    }

    private func pasteSelection(_ text: String, pid: pid_t, expectedRange: CFRange?, isFresh: () -> Bool) async throws {
        let selection = try await verifyFocus(pid: pid, isFresh: isFresh)
        if let expectedRange { try verifySelection(selection, equals: expectedRange) }
        try check(pid: pid, isFresh: isFresh)
        guard let lease else { throw CorrectionAXError.unavailable }
        try lease.write(text)
        trace?(.nativePaste, .started)
        try send(key: CGKeyCode(kVK_ANSI_V), flags: .maskCommand, pid: pid, isFresh: isFresh, mutating: true)
        trace?(.nativePaste, .passed, DiagnosticDetails(dispatched: true, confirmed: false))
        pasteDispatched = true
    }

    func replay(originalText: String, text: String, pid: pid_t, isFresh: () -> Bool) async throws {
        guard !originalText.isEmpty, originalText.utf16.count <= LayoutCorrectionLimits.maximumTextUTF16Units,
              !text.isEmpty, text.utf16.count <= LayoutCorrectionLimits.maximumTextUTF16Units else { throw CorrectionAXError.limit }
        let selectPrevious = try events(key: CGKeyCode(kVK_LeftArrow), flags: .maskShift)
        let chunks: [[CGEvent]]
        if replayMethod == .unicode {
            let unicodeChunks = Self.unicodeChunks(text)
            guard unicodeChunks.allSatisfy({ $0.utf16.count <= 20 }) else { throw CorrectionAXError.limit }
            chunks = try unicodeChunks.map { chunk in
                let pair = try events(key: 0, flags: [])
                let units = Array(chunk.utf16)
                units.withUnsafeBufferPointer { buffer in
                    for event in pair { event.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress!) }
                }
                return pair
            }
        } else { chunks = [] }
        // Preserve the original clipboard once, including across the verification Copy.
        if lease == nil {
            guard let registerSelfWrite else { throw CorrectionAXError.unavailable }
            lease = try CorrectionClipboardLease(pasteboard: pasteboard,
                registerSelfWrite: registerSelfWrite, trace: trace)
        }
        let selection = try await verifyFocus(pid: pid, isFresh: isFresh)
        guard let caret = selection, caret.length == 0,
              caret.location >= originalText.utf16.count else { throw CorrectionAXError.verification }
        let expectedRange = CFRange(location: caret.location - originalText.utf16.count,
                                    length: originalText.utf16.count)
        try check(pid: pid, isFresh: isFresh)
        trace?(.selection, .started, DiagnosticDetails(step: .selectReplacement))
        for _ in originalText {
            try check(pid: pid, isFresh: isFresh)
            guard lease?.isOwned() == true else { throw CorrectionAXError.stale }
            for event in selectPrevious {
                postEvent(event, pid)
                try await Task.sleep(nanoseconds: 1_500_000)
            }
        }
        try await waitForSelection(expectedRange, pid: pid, isFresh: isFresh)
        guard let copied = try await copySelection(pid: pid, isFresh: isFresh) else {
            throw CorrectionAXError.unavailable
        }
        let matches = copied.utf16.elementsEqual(originalText.utf16)
        trace?(.validation, matches ? .passed : .mismatch,
            DiagnosticDetails(step: .selectedText, check: .expectedTextMatches, matches: matches))
        guard matches else { throw CorrectionAXError.verification }
        if replayMethod == .paste {
            try await pasteSelection(text, pid: pid, expectedRange: expectedRange, isFresh: isFresh)
        } else {
            let selection = try await verifyFocus(pid: pid, isFresh: isFresh)
            try verifySelection(selection, equals: expectedRange)
            guard lease?.isOwned() == true else { throw CorrectionAXError.stale }
            for pair in chunks {
                try check(pid: pid, isFresh: isFresh)
                mutationBegan = true
                for event in pair { postEvent(event, pid) }
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            pasteDispatched = true
            trace?(.unicodePaste, .passed, DiagnosticDetails(dispatched: true, confirmed: false))
        }
    }

    private func waitForSelection(_ expected: CFRange, pid: pid_t, isFresh: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(200))
        while true {
            let selection = try await verifyFocus(pid: pid, isFresh: isFresh)
            if selection?.location == expected.location && selection?.length == expected.length ||
                selection == nil || ContinuousClock.now >= deadline {
                try verifySelection(selection, equals: expected)
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private func verifySelection(_ selection: CFRange?, equals expected: CFRange) throws {
        let matches = selection?.location == expected.location && selection?.length == expected.length
        trace?(.validation, matches ? .passed : .mismatch,
            DiagnosticDetails(step: .waitSelection, check: .selectionMatches,
                rangeLocation: expected.location, rangeLength: expected.length,
                selectionLocation: selection?.location, selectionLength: selection?.length, matches: matches))
        guard matches else { throw CorrectionAXError.verification }
    }

    nonisolated static func unicodeChunks(_ text: String) -> [String] {
        var chunks: [String] = [], chunk = ""
        // Preserve composed characters; CoreGraphics frameworks commonly accept short events best.
        for character in text {
            let next = String(character)
            if !chunk.isEmpty, chunk.utf16.count + next.utf16.count > 20 { chunks.append(chunk); chunk = "" }
            chunk += next
        }
        if !chunk.isEmpty { chunks.append(chunk) }
        return chunks
    }

    func finish() async {
        if pasteDispatched {
            trace?(.clipboardLease, .restoreDeferred, DiagnosticDetails(step: .clipboardRestore))
            // The layout is already switched. Keep the lease and operation owner
            // until the editor has had time to consume Paste. Cancellation must
            // not restore the clipboard early.
            await withCheckedContinuation { continuation in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { continuation.resume() }
            }
        }
        lease?.restore(); lease = nil; focus = nil; trace = nil; pasteDispatched = false
    }

    @discardableResult
    private func verifyFocus(pid: pid_t, isFresh: () -> Bool) async throws -> CFRange? {
        try check(pid: pid, isFresh: isFresh)
        guard let expected = focus else { throw CorrectionAXError.stale }
        let diagnosticTrace = trace, client = axClient
        let selection: CFRange? = try await withCheckedThrowingContinuation { continuation in
            CorrectionAXWorker.queue.async {
                do {
                    let selection = try Self.validateFocusedElement(expected.element, pid: pid, client: client, trace: diagnosticTrace)
                    continuation.resume(returning: selection)
                }
                catch { continuation.resume(throwing: error) }
            }
        }
        try check(pid: pid, isFresh: isFresh)
        return selection
    }

    @discardableResult
    nonisolated static func validateFocusedElement(_ expected: AXUIElement, pid: pid_t,
                                                   client: any CorrectionAXClient = SystemCorrectionAXClient(),
                                                   trace: CorrectionDiagnosticTrace? = nil) throws -> CFRange? {
        let current = try textFieldContext(pid: pid, client: client, trace: trace, step: .verifyContext)
        guard CFEqual(expected, current.element) else {
            trace?(.validation, .stale, DiagnosticDetails(step: .verifyContext, check: .elementMatches, matches: false))
            throw CorrectionAXError.stale
        }
        return current.selection
    }

    private func check(pid: pid_t, isFresh: () -> Bool, step: DiagnosticStep = .preDispatchValidation) throws {
        guard axClient.isTrusted() else {
            trace?(.validation, .permissionDenied, DiagnosticDetails(step: step, check: .permission, matches: false))
            throw CorrectionAXError.unsupported
        }
        guard !axClient.isSecureInput() else {
            trace?(.validation, .secureInput, DiagnosticDetails(step: step, check: .secureInput, matches: false))
            throw CorrectionAXError.unsupported
        }
        guard pid > 0, pid != ProcessInfo.processInfo.processIdentifier,
              frontmostPID() == pid else {
            trace?(.validation, .stale, DiagnosticDetails(step: step, check: .targetProcess, matches: false))
            throw CorrectionAXError.stale
        }
        guard isFresh() else { throw CorrectionAXError.stale }
    }
    private func events(key: CGKeyCode, flags: CGEventFlags) throws -> [CGEvent] {
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else { throw CorrectionAXError.unavailable }
        for event in [down, up] {
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: SyntheticEventMarker.sourceUserData)
        }
        return [down, up]
    }
    private func send(key: CGKeyCode, flags: CGEventFlags, pid: pid_t, isFresh: () -> Bool, mutating: Bool = false) throws {
        let pair = try events(key: key, flags: flags)
        try check(pid: pid, isFresh: isFresh)
        if mutating { mutationBegan = true }
        for event in pair { postEvent(event, pid) }
    }
}
