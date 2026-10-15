import ApplicationServices
import XCTest
@testable import Qipli

final class LayoutCorrectionAXAdmissionTests: XCTestCase {
    private func target(selection: CFRange = CFRange(location: 0, length: 1), count: Int = 15000) -> CorrectionAXTarget {
        let pid = ProcessInfo.processInfo.processIdentifier
        return CorrectionAXTarget(pid: pid, element: AXUIElementCreateApplication(pid),
                                  selection: selection, characterCount: count)
    }

    func testOwnProcessIsExcludedWithoutReadingItsFocusedPayload() {
        XCTAssertThrowsError(try LayoutCorrectionAXAdapter().capture(
            pid: ProcessInfo.processInfo.processIdentifier, deadline: CorrectionAXDeadline())) {
            XCTAssertEqual($0 as? CorrectionAXError, .unavailable)
        }
    }

    func testOversizedOrOverflowingRangesAreRejectedBeforeTargetAdmission() {
        let adapter = LayoutCorrectionAXAdapter()
        for range in [CFRange(location: 0, length: 12_289), CFRange(location: -1, length: 6),
                      CFRange(location: Int.max, length: 6), CFRange(location: 14999, length: Int.max)] {
            XCTAssertThrowsError(try adapter.read(target(), range: range, deadline: CorrectionAXDeadline())) {
                XCTAssertEqual($0 as? CorrectionAXError, .limit)
            }
        }
    }

    func testReplacementLimitIsCheckedBeforeAnySelectionMutation() {
        XCTAssertThrowsError(try LayoutCorrectionAXAdapter().replace(target(),
            range: CFRange(location: 0, length: 1), expectedText: "a",
            replacement: String(repeating: "x", count: 12_289), keepSelected: true,
            deadline: CorrectionAXDeadline(), isFresh: { true })) {
            XCTAssertEqual($0 as? CorrectionAXError, .limit)
        }
    }

    func testStaleOperationRefusesBeforeFocusedTargetOrPayloadRequest() {
        XCTAssertThrowsError(try LayoutCorrectionAXAdapter().replace(target(),
            range: CFRange(location: 0, length: 1), expectedText: "a", replacement: "b", keepSelected: true,
            deadline: CorrectionAXDeadline(), isFresh: { false })) {
            XCTAssertEqual($0 as? CorrectionAXError, .stale)
        }
    }

    func testWordRangeAfterCaretIsRejectedBeforeSelectionMutation() {
        XCTAssertThrowsError(try LayoutCorrectionAXAdapter().replace(
            target(selection: CFRange(location: 0, length: 0)),
            range: CFRange(location: 1, length: 1), expectedText: "a", replacement: "b", keepSelected: false,
            deadline: CorrectionAXDeadline(), isFresh: { true })) {
            XCTAssertEqual($0 as? CorrectionAXError, .stale)
        }
    }

    func testOperationDeadlineCannotBeRenewedByAdditionalRequests() {
        let deadline = CorrectionAXDeadline(milliseconds: 0)
        XCTAssertThrowsError(try deadline.check()) { XCTAssertEqual($0 as? CorrectionAXError, .deadline) }
        XCTAssertThrowsError(try deadline.check()) { XCTAssertEqual($0 as? CorrectionAXError, .deadline) }
    }
}

private final class DiagnosticCapture: @unchecked Sendable {
    struct Event: Encodable { let stage: DiagnosticStage; let reason: DiagnosticReason; let details: DiagnosticDetails? }
    private let lock = NSLock()
    private var events: [Event] = []
    var snapshot: [Event] { lock.withLock { events } }
    var trace: CorrectionDiagnosticTrace {
        CorrectionDiagnosticTrace { [self] stage, reason, details in
            lock.withLock { events.append(Event(stage: stage, reason: reason, details: details)) }
        }
    }
}

/// Synthetic responses only. No system Accessibility or user's clipboard access.
private final class DiagnosticAXClient: CorrectionAXClient, @unchecked Sendable {
    let app = AXUIElementCreateApplication(77)
    let field = AXUIElementCreateApplication(78)
    var focusedField: AXUIElement?
    var appPID: pid_t = 77
    var trusted = true
    var secure = false
    var failingAttribute: CFString?
    var attributeError: AXError = .cannotComplete
    var parameterNamesError: AXError = .success
    var attributeDelay: TimeInterval = 0
    var rangeError: AXError = .success
    var rangeResult: CFTypeRef?
    var wrongCountType = false
    var setRangeError: AXError = .success
    var text = "synthetic-private-sentinel"
    var selected = CFRange(location: 0, length: 3)

    func copyAttribute(_ element: AXUIElement, _ name: CFString) -> (AXError, CFTypeRef?) {
        if let failingAttribute, CFEqual(name, failingAttribute) {
            if attributeDelay > 0 { Thread.sleep(forTimeInterval: attributeDelay) }
            return (attributeError, nil)
        }
        switch name as String {
        case kAXFocusedApplicationAttribute: return (.success, app)
        case kAXFocusedUIElementAttribute: return (.success, focusedField ?? field)
        case kAXRoleAttribute: return (.success, kAXTextAreaRole as CFString)
        case kAXSubroleAttribute: return (.noValue, nil)
        case kAXEnabledAttribute: return (.success, kCFBooleanTrue)
        case kAXSelectedTextRangeAttribute:
            var copy = selected
            return (.success, AXValueCreate(.cfRange, &copy))
        case kAXNumberOfCharactersAttribute:
            return (.success, wrongCountType ? "synthetic-invalid-count" as CFString : NSNumber(value: text.utf16.count))
        default: return (.attributeUnsupported, nil)
        }
    }
    func parameterNames(_ element: AXUIElement) -> (AXError, CFTypeRef?) {
        (parameterNamesError, [kAXStringForRangeParameterizedAttribute] as CFArray)
    }
    func stringForRange(_ element: AXUIElement, _ value: AXValue) -> (AXError, CFTypeRef?) {
        if rangeError != .success { return (rangeError, nil) }
        if let rangeResult { return (.success, rangeResult) }
        var range = CFRange()
        AXValueGetValue(value, .cfRange, &range)
        return (.success, (text as NSString).substring(with: NSRange(location: range.location, length: range.length)) as CFString)
    }
    func pid(_ element: AXUIElement) -> (AXError, pid_t) { (.success, appPID) }
    func timeout(_ element: AXUIElement, _ seconds: Float) -> AXError { .success }
    func settable(_ element: AXUIElement, _ name: CFString) -> (AXError, Bool) { (.success, true) }
    func setSelection(_ element: AXUIElement, _ range: AXValue) -> AXError { setRangeError }
    func isTrusted() -> Bool { trusted }
    func isSecureInput() -> Bool { secure }
}

extension LayoutCorrectionAXAdmissionTests {
    private func instrumented(_ client: DiagnosticAXClient, _ capture: DiagnosticCapture) -> LayoutCorrectionAXAdapter {
        let adapter = LayoutCorrectionAXAdapter(client: client)
        adapter.setDiagnosticTrace(capture.trace)
        return adapter
    }
    private func syntheticTarget(_ client: DiagnosticAXClient) -> CorrectionAXTarget {
        CorrectionAXTarget(pid: 77, element: client.field, selection: client.selected, characterCount: client.text.utf16.count)
    }

    func testDiagnosticDistinguishesAXFailureWrongTypeAndLengthMismatch() throws {
        for scenario in 0..<3 {
            let client = DiagnosticAXClient(), capture = DiagnosticCapture()
            switch scenario {
            case 0: client.rangeError = .cannotComplete
            case 1: client.rangeResult = NSNumber(value: 123)
            default: client.rangeResult = "xy" as CFString
            }
            let adapter = instrumented(client, capture)
            XCTAssertThrowsError(try adapter.read(syntheticTarget(client), range: CFRange(location: 0, length: 3), deadline: CorrectionAXDeadline())) {
                XCTAssertEqual($0 as? CorrectionAXError, .unavailable)
            }
            let events = capture.snapshot
            if scenario == 0 {
                let failure = try XCTUnwrap(events.first { $0.reason == .axFailure })
                XCTAssertEqual(failure.details?.api, .copyStringForRange)
                XCTAssertEqual(failure.details?.attribute, .stringForRange)
                XCTAssertEqual(failure.details?.axError, AXError.cannotComplete.rawValue)
                XCTAssertEqual(failure.details?.rangeLength, 3)
                XCTAssertNotNil(failure.details?.callMicroseconds)
                XCTAssertNotNil(failure.details?.remainingMilliseconds)
            } else if scenario == 1 {
                XCTAssertTrue(events.contains { $0.reason == .typeMismatch && $0.details?.api == .copyStringForRange })
                XCTAssertFalse(events.contains { $0.reason == .lengthMismatch })
            } else {
                let failure = try XCTUnwrap(events.first { $0.reason == .lengthMismatch })
                XCTAssertEqual(failure.details?.expected, 3)
                XCTAssertEqual(failure.details?.observed, 2)
                XCTAssertEqual(failure.details?.rangeLocation, 0)
                XCTAssertEqual(failure.details?.rangeLength, 3)
            }
            let encoded = String(decoding: try JSONEncoder().encode(events), as: UTF8.self)
            XCTAssertFalse(encoded.contains(client.text))
            XCTAssertFalse(encoded.contains("xy"))
        }
    }

    func testDiagnosticIdentifiesAttributeAndItsSystemError() throws {
        let client = DiagnosticAXClient(), capture = DiagnosticCapture()
        client.failingAttribute = kAXSelectedTextRangeAttribute as CFString
        client.attributeError = .attributeUnsupported
        XCTAssertThrowsError(try instrumented(client, capture).capture(pid: 77, deadline: CorrectionAXDeadline()))
        let failure = try XCTUnwrap(capture.snapshot.first { $0.reason == .axFailure })
        XCTAssertEqual(failure.details?.api, .copyAttribute)
        XCTAssertEqual(failure.details?.attribute, .selectedRange)
        XCTAssertEqual(failure.details?.axError, AXError.attributeUnsupported.rawValue)
    }

    func testDiagnosticPreservesCapabilityAndOptionalDeadlineOutcomes() throws {
        let client = DiagnosticAXClient(), capture = DiagnosticCapture()
        client.parameterNamesError = .cannotComplete
        let adapter = instrumented(client, capture)
        XCTAssertThrowsError(try adapter.capture(pid: 77, deadline: CorrectionAXDeadline())) {
            XCTAssertEqual($0 as? CorrectionAXError, .unsupported)
        }
        XCTAssertTrue(capture.snapshot.contains { $0.details?.api == .copyParameterizedNames && $0.details?.axError == AXError.cannotComplete.rawValue })
        client.parameterNamesError = .success
        client.failingAttribute = kAXSubroleAttribute as CFString
        client.attributeDelay = 0.02
        XCTAssertThrowsError(try adapter.capture(pid: 77, deadline: CorrectionAXDeadline(milliseconds: 10))) {
            XCTAssertEqual($0 as? CorrectionAXError, .deadline)
        }
        XCTAssertTrue(capture.snapshot.contains { $0.reason == .axFailure && $0.details?.attribute == .subrole })
        XCTAssertTrue(capture.snapshot.contains { $0.reason == .deadline && $0.details?.check == .deadline })
    }

    func testDiagnosticSeparatesPermissionSecureInputAndFocusChanges() throws {
        for scenario in 0..<4 {
            let client = DiagnosticAXClient(), capture = DiagnosticCapture()
            switch scenario {
            case 0: client.trusted = false
            case 1: client.secure = true
            case 2: client.appPID = 99
            default: client.focusedField = AXUIElementCreateApplication(99)
            }
            XCTAssertThrowsError(try instrumented(client, capture).read(syntheticTarget(client),
                range: CFRange(location: 0, length: 3), deadline: CorrectionAXDeadline()))
            let expected: DiagnosticCheck = [.permission, .secureInput, .applicationMatches, .elementMatches][scenario]
            XCTAssertTrue(capture.snapshot.contains { $0.details?.check == expected && $0.details?.matches == false })
            XCTAssertFalse(capture.snapshot.contains { $0.details?.api == .copyStringForRange })
        }
    }

    func testDiagnosticRecordsSuccessfulCaptureStructureAndWrongCountType() throws {
        let client = DiagnosticAXClient(), capture = DiagnosticCapture()
        let adapter = instrumented(client, capture)
        _ = try adapter.capture(pid: 77, deadline: CorrectionAXDeadline())
        XCTAssertTrue(capture.snapshot.contains { $0.details?.role == .textArea })
        XCTAssertTrue(capture.snapshot.contains { $0.details?.characterCount == client.text.utf16.count })
        client.wrongCountType = true
        XCTAssertThrowsError(try adapter.capture(pid: 77, deadline: CorrectionAXDeadline()))
        XCTAssertTrue(capture.snapshot.contains { $0.reason == .typeMismatch && $0.details?.attribute == .characterCount })
    }

    func testDiagnosticSetterFailureIsDistinctAndPrecedesDispatch() async throws {
        let client = DiagnosticAXClient(), capture = DiagnosticCapture()
        client.setRangeError = .cannotComplete
        let adapter = instrumented(client, capture)
        let target = syntheticTarget(client)
        let error: CorrectionAXError? = await Task.detached {
            do {
                _ = try adapter.replace(target, range: client.selected, expectedText: "syn", replacement: "xyz",
                    keepSelected: true, deadline: CorrectionAXDeadline(), isFresh: { true })
                return nil
            } catch { return error as? CorrectionAXError }
        }.value
        XCTAssertEqual(error, .unavailable)
        let failure = try XCTUnwrap(capture.snapshot.first { $0.reason == .axFailure })
        XCTAssertEqual(failure.details?.api, .setSelectedRange)
        XCTAssertEqual(failure.details?.step, .selectReplacement)
        XCTAssertEqual(failure.details?.axError, AXError.cannotComplete.rawValue)
        XCTAssertFalse(capture.snapshot.contains { $0.stage == .nativePaste || $0.stage == .unicodePaste })
    }

    func testDiagnosticDeadlineAndRangeRefusalHaveSpecificChecks() throws {
        let client = DiagnosticAXClient(), capture = DiagnosticCapture()
        let adapter = instrumented(client, capture)
        XCTAssertThrowsError(try adapter.capture(pid: 77, deadline: CorrectionAXDeadline(milliseconds: 0)))
        XCTAssertTrue(capture.snapshot.contains { $0.reason == .deadline && $0.details?.check == .deadline })
        XCTAssertThrowsError(try adapter.read(syntheticTarget(client), range: CFRange(location: 0, length: 12_289), deadline: CorrectionAXDeadline()))
        XCTAssertTrue(capture.snapshot.contains { $0.reason == .mismatch && $0.details?.check == .readLimit })
    }
}
