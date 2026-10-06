import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import XCTest
@testable import Qipli

final class LayoutCorrectionModelTests: XCTestCase {
    private func source(_ id: String, _ entries: [(UInt16, UInt8, String)]) -> CorrectionSource {
        CorrectionSource(id: id, name: id, isCurrent: false, keyMap: Dictionary(
            uniqueKeysWithValues: entries.map {
                (CorrectionPhysicalKey(keyCode: $0.0, level: $0.1), $0.2)
            }
        ))
    }

    func testMapperPreservesUnmappedUnicodeButRefusesCharactersOwnedByForeignSource() throws {
        let a = source("A", [(0, 0, "g"), (1, 0, "h"), (2, 0, "b")])
        let b = source("B", [(0, 0, "п"), (1, 0, "р"), (2, 0, "и")])
        let mapped = try LayoutCorrectionMapper.map("ghb🙂\ne\u{301}", from: [a, b],
            activeSourceID: "A", to: "B")
        XCTAssertEqual(mapped.text, "при🙂\ne\u{301}")

        XCTAssertThrowsError(try LayoutCorrectionMapper.map("ghbп", from: [a, b],
            activeSourceID: "A", to: "B"))

        let shared = source("C", [(0, 0, "g"), (1, 0, "h"), (2, 0, "b")])
        XCTAssertThrowsError(try LayoutCorrectionMapper.origin(for: "ghb",
            from: [a, shared], activeSourceID: "missing"))
    }

    func testShiftAndCapsCandidatesMustHaveIdenticalDestinationOutput() throws {
        let sourceA = source("A", [(0, 0, "a"), (0, 1, "A")])
        let destination = source("B", [(0, 0, "ф"), (0, 1, "Ф")])
        XCTAssertEqual(try LayoutCorrectionMapper.map("A", from: [sourceA, destination],
            activeSourceID: "A", to: "B").text, "Ф")

        let collision = source("B", [(0, 0, "я"), (0, 1, "Я")])
        let collisionOrigin = source("A", [(0, 0, "a"), (0, 1, "a")])
        XCTAssertThrowsError(try LayoutCorrectionMapper.map("a", from: [collisionOrigin, collision],
            activeSourceID: "A", to: "B"))
    }

    func testClassifierDoesNotCountCommandPasteAndTreatsAlternateAsCompositionUncertain() {
        let layout = source("A", [(9, 0, "a")])
        let classifier = CorrectionInputClassifier()
        classifier.install(source: layout, targetPID: 42)

        let paste = classifier.metadata(keyCode: 9, flags: .maskCommand)
        XCTAssertNil(paste.units)
        XCTAssertFalse(paste.uncertain)
        let alternate = classifier.metadata(keyCode: 9, flags: .maskAlternate)
        XCTAssertNil(alternate.units)
        XCTAssertTrue(alternate.uncertain)
        let rightOption = classifier.metadata(keyCode: 9, flags: .maskAlternate)
        XCTAssertEqual(alternate.uncertain, rightOption.uncertain)
        let optionArrow = classifier.metadata(keyCode: Int64(kVK_LeftArrow), flags: .maskAlternate)
        XCTAssertNil(optionArrow.units)
        XCTAssertFalse(optionArrow.uncertain)
        let commandOptionShortcut = classifier.metadata(keyCode: 9, flags: [.maskCommand, .maskAlternate])
        XCTAssertFalse(commandOptionShortcut.uncertain)
        let plain = classifier.metadata(keyCode: 9, flags: [])
        XCTAssertEqual(plain.units, 1)
    }

    func testLedgerCapsTrailingSpacesAtEightAndModifierEpochPreservesCounts() {
        let ledger = CorrectionInputLedger()
        for index in 0..<9 {
            ledger.noteKeyDown(timestamp: UInt64(index + 1), sourceID: "A", targetPID: 42,
                expectedUTF16Units: 1, isSpace: true, isExternal: true)
        }
        XCTAssertEqual(ledger.snapshot().trailingSpaces, 8)
        XCTAssertTrue(ledger.isBlocked())
        ledger.reset()
        ledger.noteKeyDown(timestamp: 20, sourceID: "A", targetPID: 42,
            expectedUTF16Units: 1, isSpace: false, isExternal: true)
        let before = ledger.snapshot()
        ledger.noteModifierChange()
        let after = ledger.snapshot()
        XCTAssertEqual(after.totalUTF16Units, before.totalUTF16Units)
        XCTAssertEqual(after.wordUTF16Units, before.wordUTF16Units)
        XCTAssertEqual(after.inputGeneration, before.inputGeneration)
        XCTAssertGreaterThan(after.generation, before.generation)
        ledger.noteKeyDown(timestamp: 21, sourceID: "A", targetPID: 42,
            expectedUTF16Units: 1, isSpace: false, isExternal: true)
        XCTAssertGreaterThan(ledger.snapshot().inputGeneration, after.inputGeneration)
    }

    func testWordResetDoesNotClearCompositionUncertainty() {
        let ledger = CorrectionInputLedger()
        ledger.markCompositionUncertain()
        ledger.resetWordMetadata()
        XCTAssertTrue(ledger.isCompositionUncertain())
        ledger.reset()
        XCTAssertFalse(ledger.isCompositionUncertain())
    }

    func testStandaloneLeftOptionTriggersExactlyOnceOnRelease() {
        var gesture = CorrectionTriggerGesture()
        XCTAssertFalse(gesture.flagsChanged(keyCode: Int64(kVK_Option), flags: .maskAlternate,
            trigger: .leftOption, enabled: true))
        XCTAssertTrue(gesture.leftOptionHeld)
        XCTAssertTrue(gesture.flagsChanged(keyCode: Int64(kVK_Option), flags: [],
            trigger: .leftOption, enabled: true))
        XCTAssertFalse(gesture.flagsChanged(keyCode: Int64(kVK_Option), flags: [],
            trigger: .leftOption, enabled: true))
    }

    func testDelayedNativeSpaceKeepsPreinputBaselineButCaretNavigationDoesNot() {
        let pid: pid_t = 42
        let element = AXUIElementCreateApplication(pid)
        func target(_ caret: Int, _ count: Int) -> CorrectionAXTarget {
            CorrectionAXTarget(pid: pid, element: element,
                               selection: CFRange(location: caret, length: 0), characterCount: count)
        }
        let baseline = FreshWordBaseline(target: target(0, 0), sampledAt: 1,
            inputGeneration: 0, observerGeneration: 0, sourceID: "A")
        let ledger = CorrectionInputLedger()
        for time in 1...7 {
            ledger.noteKeyDown(timestamp: UInt64(time), sourceID: "A", targetPID: pid,
                expectedUTF16Units: 1, isSpace: time == 7, isExternal: true)
        }
        let metadata = ledger.snapshot()
        // The tap saw Space, but AX initially still showed six characters.
        XCTAssertTrue(CorrectionWordProgress.preservesBaseline(baseline, previous: target(6, 6),
            current: target(7, 7), metadata: metadata))
        XCTAssertFalse(CorrectionWordProgress.preservesBaseline(baseline, previous: target(7, 7),
            current: target(6, 7), metadata: metadata))
        XCTAssertFalse(CorrectionWordProgress.preservesBaseline(baseline, previous: target(6, 6),
            current: target(8, 8), metadata: metadata))
        XCTAssertFalse(CorrectionWordProgress.preservesBaseline(nil, previous: target(6, 6),
            current: target(7, 7), metadata: metadata))
    }

    func testTypedSelectionReplacementKeepsBaselineThroughPendingAndAppliedAXUpdates() {
        let pid: pid_t = 42
        let element = AXUIElementCreateApplication(pid)
        func target(_ location: Int, _ length: Int, _ count: Int) -> CorrectionAXTarget {
            CorrectionAXTarget(pid: pid, element: element,
                selection: CFRange(location: location, length: length), characterCount: count)
        }
        let initial = target(2, 7, 11)
        let baseline = FreshWordBaseline(target: initial, sampledAt: 1, inputGeneration: 0,
            observerGeneration: 0, sourceID: "A")
        let ledger = CorrectionInputLedger()
        ledger.noteKeyDown(timestamp: 2, sourceID: "A", targetPID: pid,
            expectedUTF16Units: 1, isSpace: false, isExternal: true)
        XCTAssertTrue(CorrectionWordProgress.preservesBaseline(baseline, previous: initial,
            current: initial, metadata: ledger.snapshot()))
        let applied = target(3, 0, 5)
        XCTAssertTrue(CorrectionWordProgress.preservesBaseline(baseline, previous: initial,
            current: applied, metadata: ledger.snapshot()))
        // A selection/caret change or more growth than the tap observed remains unsafe.
        XCTAssertFalse(CorrectionWordProgress.preservesBaseline(baseline, previous: applied,
            current: target(2, 1, 5), metadata: ledger.snapshot()))
        XCTAssertFalse(CorrectionWordProgress.preservesBaseline(baseline, previous: applied,
            current: target(2, 0, 5), metadata: ledger.snapshot()))
        XCTAssertFalse(CorrectionWordProgress.preservesBaseline(baseline, previous: applied,
            current: target(4, 0, 6), metadata: ledger.snapshot()))
    }

    @MainActor
    func testInputResetClearsMetadataImmediatelyAndDeferredCallbackPreservesNewAttempt() async {
        let adapter = CGEventTapAdapter()
        let monitor = CorrectionFreshWordMonitor(adapter: LayoutCorrectionAXAdapter(),
            metadataProvider: { adapter.correctionLedger.snapshot() })
        adapter.correctionFreshWordMonitor = monitor
        let callback = expectation(description: "coalesced cycle invalidation")
        var callbacks = 0
        adapter.onCorrectionInputInvalidation = {
            callbacks += 1
            // Later typing has already attempted to establish a new baseline.
            // The queued callback must not clear its metadata status again.
            XCTAssertEqual(monitor.diagnostics().baseline, .notificationsUnavailable)
            callback.fulfill()
        }
        adapter.scheduleCorrectionInvalidation(preserveWordBaseline: false)
        XCTAssertEqual(monitor.diagnostics().baseline, .inputReset)
        XCTAssertEqual(callbacks, 0)
        _ = monitor.beginInput(generation: 0, timestamp: 1, pid: 77)
        adapter.scheduleCorrectionInvalidation(preserveWordBaseline: true)
        await fulfillment(of: [callback], timeout: 1)
        XCTAssertEqual(callbacks, 1)
        XCTAssertEqual(monitor.diagnostics().baseline, .notificationsUnavailable)
    }

    func testOptionChordKeyMouseAndPreheldRightOptionCancelGesture() {
        var key = CorrectionTriggerGesture()
        _ = key.flagsChanged(keyCode: Int64(kVK_Option), flags: .maskAlternate,
            trigger: .leftOption, enabled: true)
        XCTAssertTrue(key.keyDown())
        key.keyUp()
        XCTAssertFalse(key.flagsChanged(keyCode: Int64(kVK_Option), flags: [],
            trigger: .leftOption, enabled: true))

        var mouse = CorrectionTriggerGesture()
        _ = mouse.flagsChanged(keyCode: Int64(kVK_Option), flags: .maskAlternate,
            trigger: .leftOption, enabled: true)
        mouse.mouseDown()
        XCTAssertFalse(mouse.flagsChanged(keyCode: Int64(kVK_Option), flags: [],
            trigger: .leftOption, enabled: true))

        var rightFirst = CorrectionTriggerGesture()
        _ = rightFirst.flagsChanged(keyCode: Int64(kVK_RightOption), flags: .maskAlternate,
            trigger: .leftOption, enabled: true)
        XCTAssertFalse(rightFirst.flagsChanged(keyCode: Int64(kVK_Option), flags: .maskAlternate,
            trigger: .leftOption, enabled: true))
        XCTAssertFalse(rightFirst.flagsChanged(keyCode: Int64(kVK_Option), flags: [],
            trigger: .leftOption, enabled: true))
    }

    func testPreexistingCapsLockAllowsStandaloneOptionButModifierTransitionCancelsIt() {
        var caps = CorrectionTriggerGesture()
        _ = caps.flagsChanged(keyCode: Int64(kVK_Option), flags: [.maskAlternate, .maskAlphaShift],
            trigger: .leftOption, enabled: true)
        XCTAssertTrue(caps.flagsChanged(keyCode: Int64(kVK_Option), flags: .maskAlphaShift,
            trigger: .leftOption, enabled: true))

        var capsTransition = CorrectionTriggerGesture()
        _ = capsTransition.flagsChanged(keyCode: Int64(kVK_Option), flags: .maskAlternate,
            trigger: .leftOption, enabled: true)
        _ = capsTransition.flagsChanged(keyCode: Int64(kVK_CapsLock), flags: [.maskAlternate, .maskAlphaShift],
            trigger: .leftOption, enabled: true)
        XCTAssertFalse(capsTransition.flagsChanged(keyCode: Int64(kVK_Option), flags: .maskAlphaShift,
            trigger: .leftOption, enabled: true))

        var shift = CorrectionTriggerGesture()
        _ = shift.flagsChanged(keyCode: Int64(kVK_Option), flags: .maskAlternate,
            trigger: .leftOption, enabled: true)
        _ = shift.flagsChanged(keyCode: Int64(kVK_Shift), flags: [.maskAlternate, .maskShift],
            trigger: .leftOption, enabled: true)
        XCTAssertFalse(shift.flagsChanged(keyCode: Int64(kVK_Option), flags: .maskShift,
            trigger: .leftOption, enabled: true))
    }

    func testAlternativeTriggerAndDisabledLeftOptionDoNotFire() {
        let shortcut = CorrectionTrigger.shortcut(ShortcutBinding(keyCode: 40,
            keyRepresentation: "K", modifiers: [.command, .option]))
        var gesture = CorrectionTriggerGesture()
        _ = gesture.flagsChanged(keyCode: Int64(kVK_Option), flags: .maskAlternate,
            trigger: shortcut, enabled: true)
        XCTAssertFalse(gesture.flagsChanged(keyCode: Int64(kVK_Option), flags: [],
            trigger: shortcut, enabled: true))

        _ = gesture.flagsChanged(keyCode: Int64(kVK_Option), flags: .maskAlternate,
            trigger: .leftOption, enabled: false)
        XCTAssertFalse(gesture.flagsChanged(keyCode: Int64(kVK_Option), flags: [],
            trigger: .leftOption, enabled: false))
    }
}
