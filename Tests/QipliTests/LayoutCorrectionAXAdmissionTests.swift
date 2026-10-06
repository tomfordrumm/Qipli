import ApplicationServices
import XCTest
@testable import Qipli

final class LayoutCorrectionAXAdmissionTests: XCTestCase {
    private func target(selection: CFRange = CFRange(location: 0, length: 1), count: Int = 5000) -> CorrectionAXTarget {
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
        for range in [CFRange(location: 0, length: 4097), CFRange(location: -1, length: 6),
                      CFRange(location: Int.max, length: 6), CFRange(location: 4999, length: Int.max)] {
            XCTAssertThrowsError(try adapter.read(target(), range: range, deadline: CorrectionAXDeadline())) {
                XCTAssertEqual($0 as? CorrectionAXError, .limit)
            }
        }
    }

    func testReplacementLimitIsCheckedBeforeAnySelectionMutation() {
        XCTAssertThrowsError(try LayoutCorrectionAXAdapter().replace(target(),
            range: CFRange(location: 0, length: 1), expectedText: "a",
            replacement: String(repeating: "x", count: 4097), keepSelected: true,
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
