import AppKit
import ApplicationServices
import Carbon.HIToolbox
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
    var onFinish: (() -> Void)?
    var onDispatchReturn: (() -> Void)?
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
        onDispatchReturn?()
    }
    func finish() async { onFinish?(); finishes += 1 }
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

    func testLayoutSwitchPrecedesClipboardGraceAndLaterInputDoesNotFailCompletedPaste() async {
        for selection in [false, true] {
            let native = FakeNativeCorrection(), ledger = CorrectionInputLedger()
            typed(ledger)
            native.selectionEmpty = !selection; native.copied = selection ? "a" : nil
            var switches = 0
            let coordinator = LayoutCorrectionCoordinator(transport: native, ledger: ledger,
                selectSource: { _ in switches += 1; return true })
            native.onFinish = {
                XCTAssertEqual(switches, 1, "Switch must precede clipboard grace")
                XCTAssertTrue(coordinator.isOperationActive, "No overlapping clipboard leases during grace")
                coordinator.handleTrigger(targetPID: 77, sources: self.sources, currentSourceID: "B", mayRun: true) {
                    if case .denied = $0 {} else { XCTFail("A second correction must wait for restoration") }
                }
                // Real input during grace invalidates cycling, not the dispatched result.
                ledger.invalidate()
                coordinator.invalidateCyclePreservingWordBaseline()
            }
            let result = await trigger(coordinator)
            XCTAssertEqual(result, .completed(sourceID: "B"))
            XCTAssertFalse(coordinator.hasCycle)
            XCTAssertFalse(coordinator.isOperationActive)
            XCTAssertEqual(native.pastes.count + native.replays.count, 1)
            XCTAssertEqual(native.finishes, 1)
        }
    }

    func testStaleDiagnosticsDistinguishInputModifierAndCoordinatorEpochs() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "QipliEpochTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(true, forKey: LocalDiagnostics.preferenceKey)
        defer { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: suite) }
        let logger = LocalDiagnostics(defaults: defaults, directory: root)
        for phase in [DiagnosticStep.admission, .postDispatchValidation] {
            for check in [DiagnosticCheck.inputEpoch, .modifierEpoch, .gateEpoch] {
                let native = FakeNativeCorrection(), ledger = CorrectionInputLedger()
                typed(ledger)
                let coordinator = LayoutCorrectionCoordinator(transport: native, ledger: ledger,
                    selectSource: { _ in XCTFail("Stale operation must never switch"); return true }, diagnostics: logger)
                let invalidate = {
                    switch check {
                    case .inputEpoch: ledger.invalidate()
                    case .modifierEpoch: ledger.noteModifierChange()
                    default: coordinator.invalidateCyclePreservingWordBaseline()
                    }
                }
                if phase == .admission { native.onPrepare = invalidate }
                else { native.onDispatchReturn = invalidate }
                _ = await trigger(coordinator)
                logger.flush()
                let rows = try Data(contentsOf: root.appendingPathComponent("diagnostics-0.jsonl")).split(separator: 10)
                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                let records = try rows.map { try decoder.decode(DiagnosticRecord.self, from: Data($0)) }
                let cause = try XCTUnwrap(records.last { $0.stage == .finished }?.details?.lastFailure)
                XCTAssertEqual(cause.stage, .validation)
                XCTAssertEqual(cause.reason, .stale)
                XCTAssertEqual(cause.step, phase)
                XCTAssertEqual(cause.check, check)
                XCTAssertNotEqual(cause.expected, cause.observed)
                XCTAssertEqual(native.replays.count, phase == .admission ? 0 : 1)
            }
        }
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

    private func nativeTransport(_ board: NSPasteboard, onPaste: @escaping () -> Void = {}) -> NativeLayoutCorrectionTransport {
        let native = NativeLayoutCorrectionTransport(pasteboard: board, axClient: NativeMetadataClient(),
            frontmostPID: { 77 }, postEvent: { event, pid in
                XCTAssertEqual(pid, 77)
                XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData), SyntheticEventMarker.sourceUserData)
                guard event.type == .keyUp else { return }
                switch event.getIntegerValueField(.keyboardEventKeycode) {
                case Int64(kVK_ANSI_C):
                    board.clearContents()
                    XCTAssertTrue(board.setString("synthetic selection", forType: .string))
                case Int64(kVK_ANSI_V): onPaste()
                default: break
                }
            })
        native.configurePasteboard(registerSelfWrite: { _ in }, beginCopy: {}, endCopy: {})
        return native
    }

    private func dispatchNativePaste(_ native: NativeLayoutCorrectionTransport, selection: Bool) async throws {
        _ = try await native.prepare(pid: 77)
        if selection {
            let copied = try await native.copySelection(pid: 77, isFresh: { true })
            XCTAssertEqual(copied, "synthetic selection")
            try await native.pasteSelection("synthetic replacement", pid: 77, isFresh: { true })
        } else {
            try await native.replay(deleteCount: 1, text: "synthetic replacement", pid: 77, isFresh: { true })
        }
    }

    func testNativeSelectionAndWordPasteReturnBeforeGraceAndRestoreOriginalRepresentations() async throws {
        for selection in [false, true] {
            let board = NSPasteboard(name: .init("QipliNativeGraceTests.\(UUID())"))
            defer { board.releaseGlobally() }
            let first = NSPasteboardItem(), second = NSPasteboardItem()
            first.setString("synthetic original", forType: .string)
            first.setData(Data([1, 2, 3]), forType: .init("org.qipli.synthetic-test"))
            second.setString("synthetic second", forType: .string)
            XCTAssertTrue(board.writeObjects([first, second]))
            var returnedFromPaste = false, finished = false
            let returnedBeforeQueuedWork = expectation(description: "dispatch returns without clipboard grace")
            let native = nativeTransport(board) {
                DispatchQueue.main.async {
                    XCTAssertTrue(returnedFromPaste, "Paste must return before yielding for clipboard grace")
                    returnedBeforeQueuedWork.fulfill()
                }
            }
            let held = expectation(description: "temporary clipboard retained while finish is suspended")
            let observeGrace: @MainActor @Sendable () -> Void = {
                XCTAssertFalse(finished)
                XCTAssertEqual(board.string(forType: .string), "synthetic replacement")
                held.fulfill()
            }
            native.setTrace(CorrectionDiagnosticTrace { stage, reason, _ in
                if stage == .clipboardLease && reason == .restoreDeferred {
                    DispatchQueue.main.async(execute: observeGrace)
                }
            })
            try await dispatchNativePaste(native, selection: selection)
            returnedFromPaste = true
            let began = DispatchTime.now().uptimeNanoseconds
            await native.finish()
            finished = true
            XCTAssertGreaterThanOrEqual(DispatchTime.now().uptimeNanoseconds - began, 250_000_000)
            await fulfillment(of: [returnedBeforeQueuedWork, held], timeout: 2)
            let restored = try XCTUnwrap(board.pasteboardItems)
            XCTAssertEqual(restored.count, 2)
            XCTAssertEqual(restored.first?.string(forType: .string), "synthetic original")
            XCTAssertEqual(restored.first?.data(forType: .init("org.qipli.synthetic-test")), Data([1, 2, 3]))
            XCTAssertEqual(restored.last?.string(forType: .string), "synthetic second")
            let restoredCount = board.changeCount
            await native.finish()
            XCTAssertEqual(board.changeCount, restoredCount, "Repeated cleanup must not write again")
        }
    }

    func testNativeFinishCancellationDoesNotShortenGraceOrOverwriteExternalCopy() async throws {
        for cancelBeforeStart in [false, true] {
            for externalCopy in [false, true] {
                let board = NSPasteboard(name: .init("QipliNativeCancellationTests.\(UUID())"))
                defer { board.releaseGlobally() }
                XCTAssertTrue(board.setString("synthetic original", forType: .string))
                let native = nativeTransport(board)
                try await dispatchNativePaste(native, selection: false)
                var finished = false, finishTask: Task<Void, Never>?
                var externalCount: Int?
                let observed = expectation(description: "observe and cancel suspended real finish")
                let observeGrace: @MainActor @Sendable () -> Void = {
                    XCTAssertFalse(finished)
                    XCTAssertEqual(board.string(forType: .string), "synthetic replacement")
                    if !cancelBeforeStart { finishTask?.cancel() }
                    if externalCopy {
                        board.clearContents()
                        XCTAssertTrue(board.setString("synthetic newer copy", forType: .string))
                        externalCount = board.changeCount
                    }
                    observed.fulfill()
                }
                native.setTrace(CorrectionDiagnosticTrace { stage, reason, _ in
                    if stage == .clipboardLease && reason == .restoreDeferred {
                        DispatchQueue.main.async(execute: observeGrace)
                    }
                })
                let completed = expectation(description: "cleanup completed despite cancellation")
                finishTask = Task {
                    let began = DispatchTime.now().uptimeNanoseconds
                    await native.finish()
                    XCTAssertGreaterThanOrEqual(DispatchTime.now().uptimeNanoseconds - began, 250_000_000)
                    finished = true
                    completed.fulfill()
                }
                if cancelBeforeStart { finishTask?.cancel() }
                await fulfillment(of: [observed, completed], timeout: 3)
                XCTAssertTrue(finishTask?.isCancelled == true)
                XCTAssertTrue(finished)
                XCTAssertEqual(board.string(forType: .string), externalCopy ? "synthetic newer copy" : "synthetic original")
                if let externalCount { XCTAssertEqual(board.changeCount, externalCount) }
            }
        }
    }

    func testUnicodeChunksPreserveSurrogatesAndCombiningCharacters() {
        let text = String(repeating: "a😀e\u{301}", count: 30)
        let chunks = NativeLayoutCorrectionTransport.unicodeChunks(text)
        XCTAssertEqual(chunks.joined(), text)
        XCTAssertTrue(chunks.allSatisfy { $0.utf16.count <= 20 })
        XCTAssertTrue(chunks.allSatisfy { !$0.hasPrefix("\u{301}") })
    }
}
