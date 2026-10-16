import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics

/// Native transport deliberately has no text-range, AXValue or postcondition API.
@MainActor
protocol LayoutCorrectionTransport: AnyObject {
    var mutationBegan: Bool { get }
    func prepare(pid: pid_t) async throws -> Bool? // true only when AX reports an empty selection
    func copySelection(pid: pid_t, isFresh: () -> Bool) async throws -> String?
    func pasteSelection(_ text: String, pid: pid_t, isFresh: () -> Bool) async throws
    func replay(deleteCount: Int, text: String, pid: pid_t, isFresh: () -> Bool) async throws
    func finish()
    func setTrace(_ trace: CorrectionDiagnosticTrace?)
}

@MainActor
final class NativeLayoutCorrectionTransport: LayoutCorrectionTransport {
    private let pasteboard: NSPasteboard
    private var registerSelfWrite: ((Int) -> Void)?
    private var beginCopyObservation: (() -> Void)?
    private var endCopyObservation: (() -> Void)?
    private var lease: CorrectionClipboardLease?
    private var trace: CorrectionDiagnosticTrace?
    private(set) var mutationBegan = false

    init(pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }

    func configurePasteboard(registerSelfWrite: @escaping (Int) -> Void,
                             beginCopy: @escaping () -> Void, endCopy: @escaping () -> Void) {
        self.registerSelfWrite = registerSelfWrite
        beginCopyObservation = beginCopy; endCopyObservation = endCopy
    }
    func setTrace(_ trace: CorrectionDiagnosticTrace?) { self.trace = trace }

    func prepare(pid: pid_t) async throws -> Bool? {
        mutationBegan = false
        try check(pid: pid, isFresh: { true })
        // A single metadata preflight on the AX worker. No text reads or settable checks.
        let diagnosticTrace = trace
        return try await withCheckedThrowingContinuation { continuation in
            CorrectionAXWorker.queue.async {
                do { continuation.resume(returning: try Self.textFieldMetadata(pid: pid, trace: diagnosticTrace)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    nonisolated static func textFieldMetadata(pid: pid_t, client: any CorrectionAXClient = SystemCorrectionAXClient(),
                                               trace: CorrectionDiagnosticTrace? = nil) throws -> Bool? {
        let app = AXUIElementCreateApplication(pid)
        _ = client.timeout(app, 0.15)
        func attribute(_ element: AXUIElement, _ name: String, _ diagnostic: DiagnosticAXAttribute) throws -> CFTypeRef? {
            let began = DispatchTime.now().uptimeNanoseconds
            let (status, value) = client.copyAttribute(element, name as CFString)
            trace?(.ax, [.success, .attributeUnsupported, .noValue].contains(status) ? .passed : .axFailure,
                DiagnosticDetails(step: .admission, api: .copyAttribute, attribute: diagnostic,
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
        guard pidStatus == .success, elementPID == pid else { throw CorrectionAXError.stale }
        guard let role = try attribute(element, kAXRoleAttribute, .role) as? String else { throw CorrectionAXError.unsupported }
        let subrole = try attribute(element, kAXSubroleAttribute, .subrole) as? String
        guard role != kAXSecureTextFieldSubrole as String, subrole != kAXSecureTextFieldSubrole as String else {
            trace?(.admission, .secureInput); throw CorrectionAXError.unsupported
        }
        // AXEditable is optional for known text roles. Its absence/timeout must
        // not reintroduce a capability prerequisite; an explicit false still refuses.
        let editableValue = (try? attribute(element, "AXEditable", .editable)) as? Bool
        if editableValue == false { throw CorrectionAXError.unsupported }
        let textRoles = [kAXTextFieldRole as String, kAXTextAreaRole as String, kAXComboBoxRole as String, "AXSearchField"]
        guard textRoles.contains(role) || editableValue == true else {
            throw CorrectionAXError.unsupported
        }
        // Missing selected-range support is allowed. Copy supplies the selection.
        // A timeout is also optional here: no text mutation relies on this metadata.
        let (rangeStatus, rangeValue) = client.copyAttribute(element, kAXSelectedTextRangeAttribute as CFString)
        guard rangeStatus == .success, let value = rangeValue, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cfRange, &range), range.location >= 0, range.length >= 0 else { return nil }
        return range.length == 0
    }

    func copySelection(pid: pid_t, isFresh: () -> Bool) async throws -> String? {
        try check(pid: pid, isFresh: isFresh)
        guard let registerSelfWrite, let beginCopyObservation, let endCopyObservation else { throw CorrectionAXError.unavailable }
        let transaction = try CorrectionClipboardLease(pasteboard: pasteboard,
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
        try check(pid: pid, isFresh: isFresh)
        guard let lease else { throw CorrectionAXError.unavailable }
        try lease.write(text)
        trace?(.nativePaste, .started)
        try send(key: CGKeyCode(kVK_ANSI_V), flags: .maskCommand, pid: pid, isFresh: isFresh, mutating: true)
        trace?(.nativePaste, .passed, DiagnosticDetails(dispatched: true, confirmed: false))
        // Let the editor consume the pasteboard; no text re-read or fallback after dispatch.
        try await Task.sleep(nanoseconds: 250_000_000)
    }

    func replay(deleteCount: Int, text: String, pid: pid_t, isFresh: () -> Bool) async throws {
        guard deleteCount > 0, deleteCount <= LayoutCorrectionLimits.maximumTextUTF16Units,
              !text.isEmpty, text.utf16.count <= LayoutCorrectionLimits.maximumTextUTF16Units else { throw CorrectionAXError.limit }
        // Construct every event before deletion so allocation failure cannot strand a deleted word.
        let delete = try events(key: CGKeyCode(kVK_Delete), flags: [])
        let unicodeChunks = Self.unicodeChunks(text)
        guard unicodeChunks.allSatisfy({ $0.utf16.count <= 20 }) else { throw CorrectionAXError.limit }
        let chunks = try unicodeChunks.map { chunk -> [CGEvent] in
            let pair = try events(key: 0, flags: [])
            let units = Array(chunk.utf16)
            units.withUnsafeBufferPointer { buffer in
                for event in pair { event.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress!) }
            }
            return pair
        }
        try check(pid: pid, isFresh: isFresh)
        trace?(.keyReplay, .started)
        for index in 0..<deleteCount {
            try check(pid: pid, isFresh: isFresh)
            mutationBegan = true
            for event in delete { event.postToPid(pid) }
            if index % 16 == 15 { try await Task.sleep(nanoseconds: 2_000_000) }
        }
        try await Task.sleep(nanoseconds: 8_000_000)
        for pair in chunks {
            try check(pid: pid, isFresh: isFresh)
            for event in pair { event.postToPid(pid) }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        trace?(.keyReplay, .passed, DiagnosticDetails(dispatched: true, confirmed: false))
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

    func finish() { lease?.restore(); lease = nil; trace = nil }

    private func check(pid: pid_t, isFresh: () -> Bool) throws {
        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled() else { throw CorrectionAXError.unsupported }
        guard pid > 0, pid != ProcessInfo.processInfo.processIdentifier,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid, isFresh() else { throw CorrectionAXError.stale }
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
        for event in pair { event.postToPid(pid) }
    }
}
