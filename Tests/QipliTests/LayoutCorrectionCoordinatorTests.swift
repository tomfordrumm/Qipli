import ApplicationServices
import XCTest
@testable import Qipli

private final class NativeMetadataClient: CorrectionAXClient, @unchecked Sendable {
    var role = "AXTextArea"
    var subrole: String?
    var subroleStatus: AXError = .attributeUnsupported
    var rangeStatus: AXError = .attributeUnsupported
    var editableStatus: AXError = .attributeUnsupported
    var editable: Bool?
    var elementPID: pid_t = 77
    var focusedElement = AXUIElementCreateApplication(77)
    var requested: [String] = []
    func copyAttribute(_ element: AXUIElement, _ name: CFString) -> (AXError, CFTypeRef?) {
        let name = name as String; requested.append(name)
        switch name {
        case kAXFocusedUIElementAttribute: return (.success, focusedElement)
        case kAXRoleAttribute: return (.success, role as CFString)
        case kAXSubroleAttribute: return (subroleStatus, subrole.map { $0 as CFString })
        case "AXEditable": return editable.map { (.success, $0 as CFBoolean) } ?? (editableStatus, nil)
        case kAXSelectedTextRangeAttribute: return (rangeStatus, nil)
        default: XCTFail("Unexpected metadata read"); return (.failure, nil)
        }
    }
    func parameterNames(_ element: AXUIElement) -> (AXError, CFTypeRef?) { XCTFail(); return (.failure, nil) }
    func stringForRange(_ element: AXUIElement, _ range: AXValue) -> (AXError, CFTypeRef?) { XCTFail(); return (.failure, nil) }
    func pid(_ element: AXUIElement) -> (AXError, pid_t) { (.success, elementPID) }
    func timeout(_ element: AXUIElement, _ seconds: Float) -> AXError { .success }
    func settable(_ element: AXUIElement, _ name: CFString) -> (AXError, Bool) { XCTFail(); return (.failure, false) }
    func setSelection(_ element: AXUIElement, _ range: AXValue) -> AXError { XCTFail(); return .failure }
    func isTrusted() -> Bool { true }
    func isSecureInput() -> Bool { false }
}

@MainActor
private final class FakeNativeCorrection: LayoutCorrectionTransport {
    var mutationBegan = false
    var selectionEmpty: Bool? = true
    var copied: String?
    var prepareError: Error?
    var copyError: Error?
    var onPrepare: (() -> Void)?
    var onCopy: (() -> Void)?
    var onReplay: (() -> Void)?
    var prepared = 0, copies = 0, finishes = 0
    var pastes: [String] = []
    var replays: [(Int, String)] = []
    func setTrace(_ trace: CorrectionDiagnosticTrace?) {}
    func prepare(pid: pid_t) async throws -> Bool? {
        mutationBegan = false; prepared += 1; onPrepare?()
        if let prepareError { throw prepareError }
        return selectionEmpty
    }
    func copySelection(pid: pid_t, isFresh: () -> Bool) async throws -> String? {
        copies += 1; onCopy?()
        if let copyError { throw copyError }
        return copied
    }
    func pasteSelection(_ text: String, pid: pid_t, isFresh: () -> Bool) async throws {
        guard isFresh() else { throw CorrectionAXError.stale }
        mutationBegan = true; pastes.append(text)
    }
    func replay(deleteCount: Int, text: String, pid: pid_t, isFresh: () -> Bool) async throws {
        guard isFresh() else { throw CorrectionAXError.stale }
        mutationBegan = true; replays.append((deleteCount, text)); onReplay?()
        guard isFresh() else { throw CorrectionAXError.stale }
    }
    func finish() { finishes += 1 }
}

@MainActor
final class LayoutCorrectionCoordinatorTests: XCTestCase {
    private let key = CorrectionPhysicalKey(keyCode: 0, level: 0)
    private var sources: [CorrectionSource] {
        let shifted = CorrectionPhysicalKey(keyCode: 0, level: 1)
        return [CorrectionSource(id: "A", name: "A", isCurrent: true, keyMap: [key: "a", shifted: "A"]),
                CorrectionSource(id: "B", name: "B", isCurrent: false, keyMap: [key: "b", shifted: "B"]),
                CorrectionSource(id: "C", name: "C", isCurrent: false, keyMap: [key: "c", shifted: "C"])]
    }
    private func typed(_ ledger: CorrectionInputLedger, spaces: Int = 0, pid: pid_t = 77, source: String = "A") {
        let now = DispatchTime.now().uptimeNanoseconds - 100
        ledger.noteKeyDown(timestamp: now, sourceID: source, targetPID: pid,
            expectedUTF16Units: 1, isSpace: false, isExternal: true, physicalKey: key)
        for _ in 0..<spaces {
            ledger.noteKeyDown(timestamp: now, sourceID: source, targetPID: pid,
                expectedUTF16Units: 1, isSpace: true, isExternal: true)
        }
    }
    private func trigger(_ coordinator: LayoutCorrectionCoordinator, current: String = "A", mayRun: Bool = true) async -> LayoutCorrectionOutcome {
        await withCheckedContinuation { continuation in
            coordinator.handleTrigger(targetPID: 77, sources: sources, currentSourceID: current, mayRun: mayRun) {
                continuation.resume(returning: $0)
            }
        }
    }

    func testNativePreflightAdmitsTextFieldWithoutAXValueRangeOrSettableCapabilities() throws {
        for rangeStatus in [AXError.attributeUnsupported, .cannotComplete] {
            let client = NativeMetadataClient(); client.rangeStatus = rangeStatus; client.editableStatus = rangeStatus
            XCTAssertNil(try NativeLayoutCorrectionTransport.textFieldMetadata(pid: 77, client: client))
            XCTAssertFalse(client.requested.contains(kAXValueAttribute))
            XCTAssertFalse(client.requested.contains(kAXNumberOfCharactersAttribute))
        }
    }

    func testNativePreflightRejectsSecureReadonlyAndTimelineBeforeCopy() {
        for kind in 0..<3 {
            let client = NativeMetadataClient()
            if kind == 0 { client.subrole = kAXSecureTextFieldSubrole; client.subroleStatus = .success }
            if kind == 1 { client.editable = false }
            if kind == 2 { client.role = "AXLayoutArea" }
            XCTAssertThrowsError(try NativeLayoutCorrectionTransport.textFieldMetadata(pid: 77, client: client))
        }
    }

    func testNativeMutationRefusesAnotherFieldWithinSameApplication() throws {
        let client = NativeMetadataClient()
        let admitted = client.focusedElement
        XCTAssertNoThrow(try NativeLayoutCorrectionTransport.validateFocusedElement(admitted, pid: 77, client: client))
        client.focusedElement = AXUIElementCreateSystemWide()
        XCTAssertThrowsError(try NativeLayoutCorrectionTransport.validateFocusedElement(admitted, pid: 77, client: client)) {
            XCTAssertEqual($0 as? CorrectionAXError, .stale)
        }
        XCTAssertFalse(client.requested.contains(kAXValueAttribute))
    }

    func testNativePreflightDoesNotIgnoreFailedPasswordCheckOrWrongPID() {
        let failedSubrole = NativeMetadataClient(); failedSubrole.subroleStatus = .cannotComplete
        XCTAssertThrowsError(try NativeLayoutCorrectionTransport.textFieldMetadata(pid: 77, client: failedSubrole))
        let wrongPID = NativeMetadataClient(); wrongPID.elementPID = 99
        XCTAssertThrowsError(try NativeLayoutCorrectionTransport.textFieldMetadata(pid: 77, client: wrongPID))
    }

    func testWordReplaysKeysAndTrailingSpacesWithoutCopyOrAXText() async {
        for spaces in [0, 1, 3, 8] {
            let native = FakeNativeCorrection(), ledger = CorrectionInputLedger()
            typed(ledger, spaces: spaces)
            let coordinator = LayoutCorrectionCoordinator(transport: native, ledger: ledger, selectSource: { _ in true })
            let result = await trigger(coordinator)
            XCTAssertEqual(result, .completed(sourceID: "B"))
            XCTAssertEqual(native.copies, 0)
            XCTAssertEqual(native.pastes, [])
            XCTAssertEqual(native.replays.first?.0, 1 + spaces)
            XCTAssertEqual(native.replays.first?.1, "b" + String(repeating: " ", count: spaces))
        }
    }

    func testSelectionCopyHasPriorityOverWordWhenRangeUnavailable() async {
        let native = FakeNativeCorrection(), ledger = CorrectionInputLedger()
        native.selectionEmpty = nil; native.copied = "a a"
        typed(ledger)
        let coordinator = LayoutCorrectionCoordinator(transport: native, ledger: ledger, selectSource: { _ in true })
        let result = await trigger(coordinator)
        XCTAssertEqual(result, .completed(sourceID: "B"))
        XCTAssertEqual(native.copies, 1)
        XCTAssertEqual(native.pastes, ["b b"])
        XCTAssertTrue(native.replays.isEmpty)
    }

    func testCopyTimeoutWithKnownOrUnknownSelectionNeverDeletesBufferedWord() async {
        for empty: Bool? in [false, nil] {
            let native = FakeNativeCorrection(), ledger = CorrectionInputLedger()
            native.selectionEmpty = empty
            typed(ledger)
            let coordinator = LayoutCorrectionCoordinator(transport: native, ledger: ledger, selectSource: { _ in true })
            if case .failed = await trigger(coordinator) {} else { XCTFail("Copy timeout must refuse") }
            XCTAssertEqual(native.copies, 1)
            XCTAssertTrue(native.replays.isEmpty)
            XCTAssertTrue(native.pastes.isEmpty)
        }
    }

    func testOldOrPastedWordIsRejectedWithoutMutation() async {
        let native = FakeNativeCorrection()
        let coordinator = LayoutCorrectionCoordinator(transport: native, ledger: CorrectionInputLedger(), selectSource: { _ in true })
        if case .failed = await trigger(coordinator) {} else { XCTFail("Old text admitted") }
        XCTAssertTrue(native.pastes.isEmpty); XCTAssertTrue(native.replays.isEmpty)
    }

    func testSecureOrNontextPreflightFailureNeverCopiesOrDeletes() async {
        let native = FakeNativeCorrection(), ledger = CorrectionInputLedger()
        typed(ledger); native.prepareError = CorrectionAXError.unsupported
        let coordinator = LayoutCorrectionCoordinator(transport: native, ledger: ledger, selectSource: { _ in true })
        _ = await trigger(coordinator)
        XCTAssertEqual(native.copies, 0); XCTAssertTrue(native.replays.isEmpty)
        XCTAssertEqual(native.finishes, 1)
    }

    func testInputDuringPreflightCancelsBeforeCopyOrReplay() async {
        let native = FakeNativeCorrection(), ledger = CorrectionInputLedger()
        typed(ledger); native.onPrepare = { ledger.invalidate() }
        let coordinator = LayoutCorrectionCoordinator(transport: native, ledger: ledger, selectSource: { _ in true })
        _ = await trigger(coordinator)
        XCTAssertEqual(native.copies, 0); XCTAssertTrue(native.replays.isEmpty)
    }

    func testNewCopyOrFocusChangeDuringCopyPreventsPaste() async {
        let native = FakeNativeCorrection(), ledger = CorrectionInputLedger()
        native.selectionEmpty = false; native.copied = "a"; native.onCopy = { ledger.invalidate() }
        let coordinator = LayoutCorrectionCoordinator(transport: native, ledger: ledger, selectSource: { _ in true })
        _ = await trigger(coordinator)
        XCTAssertTrue(native.pastes.isEmpty); XCTAssertTrue(native.replays.isEmpty)
    }

    func testUnsupportedOrOversizedCopyNeverFallsBackToDeletingWord() async {
        for error in [CorrectionAXError.unsupported, .limit, .stale] {
            let native = FakeNativeCorrection(), ledger = CorrectionInputLedger()
            typed(ledger); native.selectionEmpty = nil; native.copyError = error
            let coordinator = LayoutCorrectionCoordinator(transport: native, ledger: ledger, selectSource: { _ in true })
            _ = await trigger(coordinator)
            XCTAssertTrue(native.pastes.isEmpty); XCTAssertTrue(native.replays.isEmpty)
        }
    }

    func testWordCycleUsesOriginalPhysicalKeysAndDoesNotCopy() async {
        let native = FakeNativeCorrection(), ledger = CorrectionInputLedger()
        typed(ledger, spaces: 3)
        let coordinator = LayoutCorrectionCoordinator(transport: native, ledger: ledger, selectSource: { _ in true })
        for current in ["A", "B", "C"] { _ = await trigger(coordinator, current: current) }
        XCTAssertEqual(native.replays.map { $0.1 }, ["b   ", "c   ", "a   "])
        XCTAssertEqual(native.replays.map { $0.0 }, [4, 4, 4])
        XCTAssertEqual(native.copies, 0)
    }

    func testSelectionCycleReplaysTheOriginalSeedAndPreservesSpaces() async {
        let native = FakeNativeCorrection()
        native.selectionEmpty = false; native.copied = "a a"
        let coordinator = LayoutCorrectionCoordinator(transport: native, ledger: CorrectionInputLedger(), selectSource: { _ in true })
        for current in ["A", "B", "C"] { _ = await trigger(coordinator, current: current) }
        XCTAssertEqual(native.pastes, ["b b"])
        XCTAssertEqual(native.replays.map { $0.1 }, ["c c", "a a"])
        XCTAssertEqual(native.copies, 1)
    }

    func testPhysicalKeyMappingAvoidsReverseMappingAmbiguity() async {
        let native = FakeNativeCorrection(), ledger = CorrectionInputLedger()
        typed(ledger)
        let ambiguous = [CorrectionSource(id: "A", name: "A", isCurrent: true,
            keyMap: [key: "a", CorrectionPhysicalKey(keyCode: 1, level: 0): "a"]), sources[1]]
        let coordinator = LayoutCorrectionCoordinator(transport: native, ledger: ledger, selectSource: { _ in true })
        let result = await withCheckedContinuation { continuation in
            coordinator.handleTrigger(targetPID: 77, sources: ambiguous, currentSourceID: "A", mayRun: true) { continuation.resume(returning: $0) }
        }
        XCTAssertEqual(result, .completed(sourceID: "B")); XCTAssertEqual(native.replays.first?.1, "b")
    }

    func testWrongPIDOrSourceDoesNotReplay() async {
        for mismatchPID in [true, false] {
            let native = FakeNativeCorrection(), ledger = CorrectionInputLedger()
            typed(ledger, pid: mismatchPID ? 99 : 77, source: mismatchPID ? "A" : "B")
            let coordinator = LayoutCorrectionCoordinator(transport: native, ledger: ledger, selectSource: { _ in true })
            _ = await trigger(coordinator)
            XCTAssertTrue(native.replays.isEmpty)
        }
    }

    func testPartialReplayIsNeverRetriedAndDoesNotSwitchLayout() async {
        let native = FakeNativeCorrection(), ledger = CorrectionInputLedger()
        typed(ledger); native.onReplay = { ledger.invalidate() }; var switches = 0
        let coordinator = LayoutCorrectionCoordinator(transport: native, ledger: ledger, selectSource: { _ in switches += 1; return true })
        let result = await trigger(coordinator)
        if case let .failed(message) = result { XCTAssertTrue(message.contains("after sending")) } else { XCTFail() }
        XCTAssertEqual(native.replays.count, 1); XCTAssertEqual(switches, 0); XCTAssertFalse(coordinator.hasCycle)
    }

    func testSourceSwitchFailureDoesNotRepeatInput() async {
        let native = FakeNativeCorrection(), ledger = CorrectionInputLedger()
        typed(ledger)
        let coordinator = LayoutCorrectionCoordinator(transport: native, ledger: ledger, selectSource: { _ in false })
        _ = await trigger(coordinator)
        XCTAssertEqual(native.replays.count, 1); XCTAssertFalse(coordinator.hasCycle)
    }

    func testCompetingOwnerDeniesBeforeNativeService() async {
        let native = FakeNativeCorrection()
        let coordinator = LayoutCorrectionCoordinator(transport: native, ledger: CorrectionInputLedger())
        if case .denied = await trigger(coordinator, mayRun: false) {} else { XCTFail() }
        XCTAssertEqual(native.prepared, 0)
    }

    func testCycleIsReleasedAutomaticallyAtIdleTTL() async throws {
        let native = FakeNativeCorrection(), ledger = CorrectionInputLedger()
        typed(ledger)
        let coordinator = LayoutCorrectionCoordinator(transport: native, ledger: ledger, selectSource: { _ in true })
        _ = await trigger(coordinator); XCTAssertTrue(coordinator.hasCycle)
        try await Task.sleep(nanoseconds: 5_100_000_000)
        XCTAssertFalse(coordinator.hasCycle)
    }

    func testUnicodeChunksPreserveSurrogatesAndCombiningCharacters() {
        let text = String(repeating: "a😀e\u{301}", count: 30)
        let chunks = NativeLayoutCorrectionTransport.unicodeChunks(text)
        XCTAssertEqual(chunks.joined(), text)
        XCTAssertTrue(chunks.allSatisfy { $0.utf16.count <= 20 })
        XCTAssertTrue(chunks.allSatisfy { !$0.hasPrefix("\u{301}") })
    }
}
