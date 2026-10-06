import ApplicationServices
import XCTest
@testable import Qipli

private final class CorrectionFakeAX: LayoutCorrectionAXAdapting, @unchecked Sendable {
    var text: String
    var target: CorrectionAXTarget
    var captures = 0
    var reads = 0
    var replacements = 0
    var beforeCapture: (() -> Void)?
    var replacedRanges: [CFRange] = []
    init(_ text: String, selection: CFRange) {
        self.text = text
        target = CorrectionAXTarget(pid: 77, element: AXUIElementCreateApplication(77),
                                    selection: selection, characterCount: text.utf16.count)
    }
    func capture(pid: pid_t, deadline: CorrectionAXDeadline) throws -> CorrectionAXTarget {
        captures += 1; beforeCapture?(); return target
    }
    func matches(_ target: CorrectionAXTarget, deadline: CorrectionAXDeadline) throws -> Bool { true }
    func read(_ target: CorrectionAXTarget, range: CFRange, deadline: CorrectionAXDeadline) throws -> String {
        reads += 1
        return (text as NSString).substring(with: NSRange(location: range.location, length: range.length))
    }
    func replace(_ target: CorrectionAXTarget, range: CFRange, expectedText: String, replacement: String,
                 keepSelected: Bool, deadline: CorrectionAXDeadline, isFresh: () -> Bool) throws -> CorrectionAXReplacement {
        guard isFresh(), try read(target, range: range, deadline: deadline) == expectedText else {
            throw CorrectionAXError.stale
        }
        replacements += 1; replacedRanges.append(range)
        text = (text as NSString).replacingCharacters(in: NSRange(location: range.location, length: range.length), with: replacement)
        let next = CFRange(location: range.location, length: replacement.utf16.count)
        let selection = keepSelected ? next : CFRange(location: target.selection.location + next.length - range.length, length: 0)
        self.target = CorrectionAXTarget(pid: target.pid, element: target.element, selection: selection, characterCount: text.utf16.count)
        return CorrectionAXReplacement(target: self.target, range: next)
    }
}
private final class CorrectionFakeProof: CorrectionFreshWordProofProviding, @unchecked Sendable {
    var value: (FreshWordBaseline, FreshWordSample)?
    var onRefresh: (() -> Void)?
    func refreshForTrigger(deadline: CorrectionAXDeadline) { onRefresh?() }
    func invalidate() { value = nil }
    func proof(generation: UInt64, sourceID: String, pid: pid_t, lastInputTimestamp: UInt64)
        -> (FreshWordBaseline, FreshWordSample)? { value }
}

@MainActor
final class LayoutCorrectionCoordinatorTests: XCTestCase {
    func testWordUsesCaretAfterNativeSpaceSettlesDuringMetadataRefresh() async {
        let ax = CorrectionFakeAX("a ", selection: CFRange(location: 2, length: 0))
        let settled = ax.target
        ax.target = CorrectionAXTarget(pid: 77, element: settled.element,
            selection: CFRange(location: 1, length: 0), characterCount: 1)
        let ledger = CorrectionInputLedger()
        let tick = DispatchTime.now().uptimeNanoseconds - 1_000
        ledger.noteKeyDown(timestamp: tick, sourceID: "A", targetPID: 77,
            expectedUTF16Units: 1, isSpace: false, isExternal: true)
        ledger.noteKeyDown(timestamp: tick + 1, sourceID: "A", targetPID: 77,
            expectedUTF16Units: 1, isSpace: true, isExternal: true)
        let proof = CorrectionFakeProof()
        proof.value = (FreshWordBaseline(target: CorrectionAXTarget(pid: 77, element: settled.element,
            selection: CFRange(location: 0, length: 0), characterCount: 0), sampledAt: tick - 1,
            inputGeneration: 0, observerGeneration: 0, sourceID: "A"),
            FreshWordSample(target: settled, sampledAt: tick + 2, observerGeneration: 0,
                inputGeneration: ledger.snapshot().inputGeneration, sourceID: "A"))
        ax.beforeCapture = { if ax.captures >= 2 { ax.target = settled } }
        let coordinator = LayoutCorrectionCoordinator(adapter: ax, ledger: ledger,
            freshWordMonitor: proof, selectSource: { _ in true })
        let result = await trigger(coordinator, current: "A")
        XCTAssertEqual(result, .completed(sourceID: "B"))
        XCTAssertEqual(ax.text, "b ")
        XCTAssertEqual(ax.target.selection.location, 2)
        XCTAssertEqual(ax.replacements, 1)
    }
    func testWordTypedOverAnInitialSelectionPreservesSuffixAndSpaces() async {
        // The new typing replaced the initial "old old" selection at [2, 7].
        // Net document growth is negative, but inserted units and caret growth match.
        for spaces in 0...1 {
            let ax = CorrectionFakeAX("d a" + String(repeating: " ", count: spaces) + " d",
                                      selection: CFRange(location: 3 + spaces, length: 0))
            let ledger = CorrectionInputLedger()
            let tick = DispatchTime.now().uptimeNanoseconds - 1_000
            for index in 0...spaces {
                ledger.noteKeyDown(timestamp: tick + UInt64(index), sourceID: "A", targetPID: 77,
                    expectedUTF16Units: 1, isSpace: index > 0, isExternal: true)
            }
            let proof = CorrectionFakeProof()
            proof.value = (FreshWordBaseline(target: CorrectionAXTarget(pid: 77, element: ax.target.element,
                selection: CFRange(location: 2, length: 7), characterCount: 11), sampledAt: tick - 1,
                inputGeneration: 0, observerGeneration: 0, sourceID: "A"),
                FreshWordSample(target: ax.target, sampledAt: tick + UInt64(spaces + 1), observerGeneration: 1,
                    inputGeneration: ledger.snapshot().inputGeneration, sourceID: "A"))
            let coordinator = LayoutCorrectionCoordinator(adapter: ax, ledger: ledger,
                freshWordMonitor: proof, selectSource: { _ in true })
            let result = await trigger(coordinator, current: "A")
            XCTAssertEqual(result, .completed(sourceID: "B"))
            XCTAssertEqual(ax.text, "d b" + String(repeating: " ", count: spaces) + " d")
            XCTAssertEqual(ax.target.selection.location, 3 + spaces)
            XCTAssertEqual(ax.replacements, 1)
        }
    }

    func testRecentWordWithSpacesConvertsWithoutAnyPreinputAXMonitor() async {
        for spaces in [0, 1, 3] {
            let ax = CorrectionFakeAX("d a" + String(repeating: " ", count: spaces),
                                      selection: CFRange(location: 3 + spaces, length: 0))
            let ledger = CorrectionInputLedger()
            let tick = DispatchTime.now().uptimeNanoseconds - 10_000
            for index in 0...spaces {
                ledger.noteKeyDown(timestamp: tick + UInt64(index), sourceID: "A", targetPID: 77,
                    expectedUTF16Units: 1, isSpace: index > 0, isExternal: true)
            }
            let coordinator = LayoutCorrectionCoordinator(adapter: ax, ledger: ledger, selectSource: { _ in true })
            let result = await trigger(coordinator, current: "A")
            XCTAssertEqual(result, .completed(sourceID: "B"))
            XCTAssertEqual(ax.text, "d b" + String(repeating: " ", count: spaces))
            XCTAssertEqual(ax.target.selection.location, 3 + spaces)
        }
    }

    func testOldOrPastedWordWithoutRecentTypingIsRejectedBeforeReadingText() async {
        let ax = CorrectionFakeAX("a", selection: CFRange(location: 1, length: 0))
        let coordinator = LayoutCorrectionCoordinator(adapter: ax, ledger: CorrectionInputLedger(), selectSource: { _ in true })
        if case .failed = await trigger(coordinator, current: "A") {} else { XCTFail("Old text was admitted") }
        XCTAssertEqual(ax.reads, 0)
        XCTAssertEqual(ax.replacements, 0)
    }

    private var sources: [CorrectionSource] {
        let zero = CorrectionPhysicalKey(keyCode: 0, level: 0)
        let one = CorrectionPhysicalKey(keyCode: 1, level: 0)
        return [CorrectionSource(id: "A", name: "A", isCurrent: true, keyMap: [zero: "a", one: "d"]),
                CorrectionSource(id: "B", name: "B", isCurrent: false, keyMap: [zero: "b", one: "b"]),
                CorrectionSource(id: "C", name: "C", isCurrent: false, keyMap: [zero: "c", one: "e"])]
    }
    private func trigger(_ coordinator: LayoutCorrectionCoordinator, current: String, mayRun: Bool = true)
        async -> LayoutCorrectionOutcome {
        await withCheckedContinuation { continuation in
            coordinator.handleTrigger(targetPID: 77, sources: sources, currentSourceID: current, mayRun: mayRun) {
                continuation.resume(returning: $0)
            }
        }
    }

    func testCycleUsesOriginalSeedAcrossALossyIntermediateSource() async {
        let ax = CorrectionFakeAX("a", selection: CFRange(location: 0, length: 1))
        let coordinator = LayoutCorrectionCoordinator(adapter: ax, ledger: CorrectionInputLedger(),
            freshWordMonitor: CorrectionFakeProof(), selectSource: { _ in true })
        let outcome1 = await trigger(coordinator, current: "A")
        XCTAssertEqual(outcome1, .completed(sourceID: "B"))
        XCTAssertEqual(ax.text, "b")
        let outcome2 = await trigger(coordinator, current: "B")
        XCTAssertEqual(outcome2, .completed(sourceID: "C"))
        XCTAssertEqual(ax.text, "c")
        let outcome3 = await trigger(coordinator, current: "C")
        XCTAssertEqual(outcome3, .completed(sourceID: "A"))
        XCTAssertEqual(ax.text, "a")
        XCTAssertEqual(ax.replacements, 3)
    }

    func testUniqueSelectionOriginDeterminesDestinationBeforeMapping() async {
        let ax = CorrectionFakeAX("a", selection: CFRange(location: 0, length: 1))
        let coordinator = LayoutCorrectionCoordinator(adapter: ax, ledger: CorrectionInputLedger(),
            freshWordMonitor: CorrectionFakeProof(), selectSource: { _ in true })
        let outcome4 = await trigger(coordinator, current: "C")
        XCTAssertEqual(outcome4, .completed(sourceID: "B"))
        XCTAssertEqual(ax.text, "b")
    }

    func testWordCyclePreservesSpacesAndCaretWithoutReusingInputProof() async {
        let ax = CorrectionFakeAX("prefix a   ", selection: CFRange(location: 11, length: 0))
        let ledger = CorrectionInputLedger()
        let tick = DispatchTime.now().uptimeNanoseconds
        for index in 0..<4 {
            ledger.noteKeyDown(timestamp: tick + UInt64(index), sourceID: "A", targetPID: 77,
                expectedUTF16Units: 1, isSpace: index > 0, isExternal: true)
        }
        let proof = CorrectionFakeProof()
        proof.value = (FreshWordBaseline(target: CorrectionAXTarget(pid: 77, element: ax.target.element,
            selection: CFRange(location: 7, length: 0), characterCount: 7), sampledAt: tick - 10,
            inputGeneration: 0, observerGeneration: 0, sourceID: "A"),
            FreshWordSample(target: ax.target, sampledAt: tick + 4, observerGeneration: 1,
                inputGeneration: ledger.snapshot().generation, sourceID: "A"))
        let coordinator = LayoutCorrectionCoordinator(adapter: ax, ledger: ledger,
            freshWordMonitor: proof, selectSource: { _ in true })
        let outcome5 = await trigger(coordinator, current: "A")
        XCTAssertEqual(outcome5, .completed(sourceID: "B"))
        XCTAssertNil(proof.value)
        let outcome6 = await trigger(coordinator, current: "B")
        XCTAssertEqual(outcome6, .completed(sourceID: "C"))
        XCTAssertEqual(ax.text, "prefix c   ")
        XCTAssertEqual(ax.target.selection.location, 11)
        XCTAssertEqual(ax.target.selection.length, 0)
        XCTAssertTrue(ax.replacedRanges.allSatisfy { $0.location == 7 && $0.length == 1 })
    }

    func testInputRaceAfterMetadataCaptureCancelsBeforePayloadRead() async {
        let ax = CorrectionFakeAX("a", selection: CFRange(location: 0, length: 1))
        let ledger = CorrectionInputLedger()
        ax.beforeCapture = { ledger.invalidate() }
        let coordinator = LayoutCorrectionCoordinator(adapter: ax, ledger: ledger,
            freshWordMonitor: CorrectionFakeProof(), selectSource: { _ in true })
        if case .failed = await trigger(coordinator, current: "A") {} else { XCTFail("Race was not rejected") }
        XCTAssertEqual(ax.reads, 0)
        XCTAssertEqual(ax.replacements, 0)
    }

    func testLastWordUsesWholeTypingRunDeltaAfterEarlierWords() async {
        let ax = CorrectionFakeAX("a a   ", selection: CFRange(location: 6, length: 0))
        let ledger = CorrectionInputLedger()
        let tick = DispatchTime.now().uptimeNanoseconds
        for index in 0..<6 {
            ledger.noteKeyDown(timestamp: tick + UInt64(index), sourceID: "A", targetPID: 77,
                expectedUTF16Units: 1, isSpace: index != 0 && index != 2, isExternal: true)
        }
        let proof = CorrectionFakeProof()
        proof.value = (FreshWordBaseline(target: CorrectionAXTarget(pid: 77, element: ax.target.element,
            selection: CFRange(location: 0, length: 0), characterCount: 0), sampledAt: tick - 10,
            inputGeneration: 0, observerGeneration: 0, sourceID: "A"),
            FreshWordSample(target: ax.target, sampledAt: tick + 6, observerGeneration: 1,
                inputGeneration: ledger.snapshot().generation, sourceID: "A"))
        let coordinator = LayoutCorrectionCoordinator(adapter: ax, ledger: ledger,
            freshWordMonitor: proof, selectSource: { _ in true })
        let outcome = await trigger(coordinator, current: "A")
        XCTAssertEqual(outcome, .completed(sourceID: "B"))
        XCTAssertEqual(ax.text, "a b   ")
        XCTAssertEqual(ax.target.selection.location, 6)
    }

    func testFreshLettersAppendedToAnOldTokenAreNotTreatedAsANewWord() async {
        let ax = CorrectionFakeAX("olda", selection: CFRange(location: 4, length: 0))
        let ledger = CorrectionInputLedger()
        let tick = DispatchTime.now().uptimeNanoseconds
        ledger.noteKeyDown(timestamp: tick, sourceID: "A", targetPID: 77,
            expectedUTF16Units: 1, isSpace: false, isExternal: true)
        let proof = CorrectionFakeProof()
        proof.value = (FreshWordBaseline(target: CorrectionAXTarget(pid: 77, element: ax.target.element,
            selection: CFRange(location: 3, length: 0), characterCount: 3), sampledAt: tick - 10,
            inputGeneration: 0, observerGeneration: 0, sourceID: "A"),
            FreshWordSample(target: ax.target, sampledAt: tick + 1, observerGeneration: 1,
                inputGeneration: ledger.snapshot().generation, sourceID: "A"))
        let coordinator = LayoutCorrectionCoordinator(adapter: ax, ledger: ledger,
            freshWordMonitor: proof, selectSource: { _ in true })
        if case .failed = await trigger(coordinator, current: "A") {} else { XCTFail("Old token prefix was accepted") }
        XCTAssertEqual(ax.replacements, 0)
        XCTAssertEqual(ax.text, "olda")
    }

    func testSourceSwitchFailureDoesNotRepeatTheReplacement() async {
        let ax = CorrectionFakeAX("a", selection: CFRange(location: 0, length: 1))
        let coordinator = LayoutCorrectionCoordinator(adapter: ax, ledger: CorrectionInputLedger(),
            freshWordMonitor: CorrectionFakeProof(), selectSource: { _ in false })
        if case let .failed(message) = await trigger(coordinator, current: "A") {
            XCTAssertTrue(message.hasPrefix("Text corrected"))
        } else { XCTFail("Source switch failure was not reported") }
        XCTAssertEqual(ax.text, "b")
        XCTAssertEqual(ax.replacements, 1)
        XCTAssertFalse(coordinator.hasCycle)
    }

    func testCompetingOwnerDeniesBeforeAnyAXRequest() async {
        let ax = CorrectionFakeAX("a", selection: CFRange(location: 0, length: 1))
        let coordinator = LayoutCorrectionCoordinator(adapter: ax, ledger: CorrectionInputLedger(),
            freshWordMonitor: CorrectionFakeProof(), selectSource: { _ in true })
        if case .denied = await trigger(coordinator, current: "A", mayRun: false) {} else { XCTFail("Owner not honored") }
        XCTAssertEqual(ax.captures, 0)
        XCTAssertEqual(ax.replacements, 0)
    }

    func testIdleTTLReleasesCycleWithoutWaitingForAnotherTrigger() async throws {
        let ax = CorrectionFakeAX("a", selection: CFRange(location: 0, length: 1))
        let coordinator = LayoutCorrectionCoordinator(adapter: ax, ledger: CorrectionInputLedger(),
            freshWordMonitor: CorrectionFakeProof(), selectSource: { _ in true })
        _ = await trigger(coordinator, current: "A")
        XCTAssertTrue(coordinator.hasCycle)
        try await Task.sleep(nanoseconds: 5_200_000_000)
        XCTAssertFalse(coordinator.hasCycle)
    }
}
