import AppKit
import XCTest
@testable import Qipli

@MainActor
final class StackSessionControllerTests: XCTestCase {
    func testStartIsUniqueAndAppendsExactDuplicateUnicodeOccurrences() {
        let controller = StackSessionController()
        let entry = HistoryEntry(id: UUID(), text: "same 🦊\nvalue", activityAt: .now)

        XCTAssertTrue(controller.startIfNeeded(captureAfterChangeCount: 10))
        let context = controller.captureContext
        XCTAssertFalse(controller.startIfNeeded(captureAfterChangeCount: 11))

        controller.appendPersistedHistoryEntry(entry, observedChangeCount: 11, for: context)
        controller.appendPersistedHistoryEntry(entry, observedChangeCount: 12, for: context)

        XCTAssertEqual(controller.occurrences.count, 2)
        XCTAssertNotEqual(controller.occurrences[0].id, controller.occurrences[1].id)
        XCTAssertEqual(controller.occurrences.map(\.historyEntryID), [entry.id, entry.id])
        XCTAssertEqual(controller.occurrences.map(\.text), [entry.text, entry.text])
        XCTAssertEqual(controller.occurrences.map(\.position), [0, 1])
    }

    func testCancelReleasesSessionAndNewSessionStartsEmpty() {
        let controller = StackSessionController()
        XCTAssertTrue(controller.startIfNeeded(captureAfterChangeCount: 10))
        let context = controller.captureContext
        controller.appendPersistedHistoryEntry(makeEntry("first"), observedChangeCount: 11, for: context)
        XCTAssertTrue(controller.setTraversalDirection(.reverse))
        XCTAssertTrue(controller.markTraversalStarted())
        let releasedSession = WeakBox<StackSession>()
        releasedSession.value = controller.session

        controller.cancel()

        XCTAssertNil(releasedSession.value)
        XCTAssertFalse(controller.isActive)
        XCTAssertTrue(controller.occurrences.isEmpty)
        XCTAssertEqual(controller.traversalDirection, .direct)
        XCTAssertFalse(controller.traversalHasStarted)
        XCTAssertTrue(controller.startIfNeeded(captureAfterChangeCount: 12))
        XCTAssertTrue(controller.occurrences.isEmpty)
        XCTAssertEqual(controller.traversalDirection, .direct)
        XCTAssertFalse(controller.traversalHasStarted)
    }

    func testCaptureBeforeStartAndCaptureFromCanceledSessionNeverEnterNewSession() {
        let store = StackTestHistoryStore()
        let viewModel = HistoryViewModel(service: HistoryService(store: store))
        let controller = StackSessionController()
        let coordinator = StackCollectionCaptureCoordinator(
            historyViewModel: viewModel,
            stackSessionController: controller
        )

        let preStartContext = controller.captureContext
        XCTAssertNil(preStartContext)
        XCTAssertTrue(controller.startIfNeeded(captureAfterChangeCount: 10))
        coordinator.recordExternalText("pre-start fixture", observedChangeCount: 10, stackCaptureContext: preStartContext)
        XCTAssertTrue(controller.occurrences.isEmpty)

        let canceledContext = controller.captureContext
        controller.cancel()
        XCTAssertTrue(controller.startIfNeeded(captureAfterChangeCount: 20))
        coordinator.recordExternalText("stale fixture", observedChangeCount: 21, stackCaptureContext: canceledContext)

        XCTAssertEqual(store.createdTexts, ["pre-start fixture", "stale fixture"])
        XCTAssertTrue(controller.occurrences.isEmpty)
    }

    func testHistorySavesBeforeStackAppendAndSaveFailureLeavesStackUnchanged() {
        let store = StackTestHistoryStore()
        let viewModel = HistoryViewModel(service: HistoryService(store: store))
        let controller = StackSessionController()
        let coordinator = StackCollectionCaptureCoordinator(
            historyViewModel: viewModel,
            stackSessionController: controller
        )
        XCTAssertTrue(controller.startIfNeeded(captureAfterChangeCount: 10))
        let context = controller.captureContext
        store.onCreate = { XCTAssertTrue(controller.occurrences.isEmpty) }

        coordinator.recordExternalText("durable fixture", observedChangeCount: 11, stackCaptureContext: context)
        store.onCreate = nil

        XCTAssertEqual(store.createdTexts, ["durable fixture"])
        XCTAssertEqual(controller.occurrences.map(\.text), ["durable fixture"])
        XCTAssertFalse(controller.hasCaptureError)

        store.createError = HistoryStoreError.unavailable
        coordinator.recordExternalText("failed fixture", observedChangeCount: 12, stackCaptureContext: context)

        XCTAssertEqual(controller.occurrences.map(\.text), ["durable fixture"])
        XCTAssertTrue(controller.hasCaptureError)
    }

    func testPreviewTruncatesOnlyDisplayValue() {
        let fullText = String(repeating: "x", count: StackPreview.maximumCharacters + 1)

        XCTAssertEqual(StackPreview.text(for: fullText).count, StackPreview.maximumCharacters + 1)
        XCTAssertTrue(StackPreview.text(for: fullText).hasSuffix("…"))
        XCTAssertEqual(fullText.count, StackPreview.maximumCharacters + 1)
    }

    func testDirectAndReverseChooseDeterministicNextForEmptySingleAndManyOccurrences() {
        let controller = StackSessionController()
        XCTAssertTrue(controller.startIfNeeded(captureAfterChangeCount: 10))
        XCTAssertNil(controller.nextOccurrence)

        let context = controller.captureContext
        controller.appendPersistedHistoryEntry(makeEntry("only"), observedChangeCount: 11, for: context)
        XCTAssertEqual(controller.traversalDirection, .direct)
        XCTAssertEqual(controller.nextOccurrence?.text, "only")
        XCTAssertTrue(controller.setTraversalDirection(.reverse))
        XCTAssertEqual(controller.nextOccurrence?.text, "only")

        controller.appendPersistedHistoryEntry(makeEntry("middle"), observedChangeCount: 12, for: context)
        controller.appendPersistedHistoryEntry(makeEntry("last"), observedChangeCount: 13, for: context)
        XCTAssertEqual(controller.nextOccurrence?.text, "last")
        XCTAssertTrue(controller.setTraversalDirection(.direct))
        XCTAssertEqual(controller.nextOccurrence?.text, "only")
    }

    func testReorderPreservesExactDuplicateOccurrencesAndContiguousPositions() {
        let controller = configuredController(with: ["duplicate", "duplicate", "third"])
        let original = controller.occurrences
        let reorderedIDs = [original[1].id, original[2].id, original[0].id]

        XCTAssertTrue(controller.reorder(occurrenceIDs: reorderedIDs))

        XCTAssertEqual(controller.occurrences.map(\.id), reorderedIDs)
        XCTAssertEqual(controller.occurrences.map(\.position), [0, 1, 2])
        XCTAssertEqual(controller.occurrences.map(\.text), ["duplicate", "third", "duplicate"])
        XCTAssertEqual(controller.occurrences.map(\.historyEntryID).sorted { $0.uuidString < $1.uuidString }, original.map(\.historyEntryID).sorted { $0.uuidString < $1.uuidString })
        XCTAssertEqual(controller.nextOccurrence?.id, original[1].id)

        XCTAssertTrue(controller.setTraversalDirection(.reverse))
        XCTAssertEqual(controller.nextOccurrence?.id, original[0].id)
    }

    func testInvalidReordersAreAtomic() {
        let controller = configuredController(with: ["one", "two", "three"])
        let originalOccurrences = controller.occurrences
        let originalDirection = controller.traversalDirection

        XCTAssertFalse(controller.reorder(occurrenceIDs: [originalOccurrences[0].id, UUID(), originalOccurrences[2].id]))
        XCTAssertEqual(controller.occurrences, originalOccurrences)
        XCTAssertFalse(controller.reorder(occurrenceIDs: [originalOccurrences[0].id, originalOccurrences[0].id, originalOccurrences[2].id]))
        XCTAssertEqual(controller.occurrences, originalOccurrences)
        XCTAssertFalse(controller.reorder(occurrenceIDs: Array(originalOccurrences.map(\.id).dropFirst())))
        XCTAssertEqual(controller.occurrences, originalOccurrences)
        XCTAssertEqual(controller.traversalDirection, originalDirection)
    }

    func testAppendAfterReorderEntersTheEndOfBaseVisibleOrder() {
        let controller = configuredController(with: ["first", "second"])
        let original = controller.occurrences
        XCTAssertTrue(controller.reorder(occurrenceIDs: [original[1].id, original[0].id]))

        controller.appendPersistedHistoryEntry(makeEntry("new external copy"), observedChangeCount: 13, for: controller.captureContext)

        XCTAssertEqual(controller.occurrences.map(\.id), [original[1].id, original[0].id, controller.occurrences[2].id])
        XCTAssertEqual(controller.occurrences.map(\.text), ["second", "first", "new external copy"])
        XCTAssertEqual(controller.occurrences.map(\.position), [0, 1, 2])
    }

    func testTraversalLockRejectsReorderAndDirectionChangesWithoutPartialMutation() {
        let controller = configuredController(with: ["first", "second"])
        XCTAssertTrue(controller.setTraversalDirection(.reverse))
        XCTAssertTrue(controller.markTraversalStarted())
        let originalOccurrences = controller.occurrences

        XCTAssertFalse(controller.setTraversalDirection(.direct))
        XCTAssertFalse(controller.reorder(occurrenceIDs: originalOccurrences.map(\.id).reversed()))
        XCTAssertFalse(controller.markTraversalStarted())
        XCTAssertTrue(controller.traversalHasStarted)
        XCTAssertEqual(controller.traversalDirection, .reverse)
        XCTAssertEqual(controller.occurrences, originalOccurrences)
        XCTAssertEqual(controller.nextOccurrence?.id, originalOccurrences.last?.id)
    }

    func testPasteStackPanelIntentsDriveOccurrenceOrderAndAccessibleFallbackState() {
        let controller = configuredController(with: ["one", "two", "three"])
        let initial = controller.occurrences
        let executor = PasteStackPanelIntentExecutor(
            occurrences: { controller.occurrences },
            canAdjustTraversal: { controller.canAdjustTraversal },
            setTraversalDirection: controller.setTraversalDirection,
            reorder: controller.reorder,
            schedule: { action in action() }
        )

        executor.execute(.moveOccurrence(initial[1].id, by: -1))
        XCTAssertEqual(controller.occurrences.map(\.id), [initial[1].id, initial[0].id, initial[2].id])

        executor.execute(.moveOccurrences(IndexSet(integer: 0), to: 2))
        XCTAssertEqual(controller.occurrences.map(\.id), [initial[0].id, initial[1].id, initial[2].id])
        executor.execute(.setTraversalDirection(.reverse))
        XCTAssertEqual(controller.nextOccurrence?.id, initial[2].id)

        XCTAssertEqual(PasteStackPanelAccessibility.directionLabel, "Traversal direction")
        XCTAssertEqual(PasteStackPanelAccessibility.nextItemLabel, "Next item")
        XCTAssertEqual(PasteStackPanelAccessibility.moveLabel(position: 1, direction: .up), "Move item 2 up")
        XCTAssertEqual(PasteStackPanelAccessibility.moveLabel(position: 1, direction: .down), "Move item 2 down")

        XCTAssertEqual(PasteStackPanelControlState(occurrenceCount: 0, canAdjustTraversal: true), .init(occurrenceCount: 0, canAdjustTraversal: true))
        XCTAssertFalse(PasteStackPanelControlState(occurrenceCount: 0, canAdjustTraversal: true).canReorder)
        XCTAssertTrue(PasteStackPanelControlState(occurrenceCount: 1, canAdjustTraversal: true).canChooseDirection)
        XCTAssertFalse(PasteStackPanelControlState(occurrenceCount: 1, canAdjustTraversal: true).canReorder)
        XCTAssertTrue(PasteStackPanelControlState(occurrenceCount: 3, canAdjustTraversal: true).canMove(position: 1, by: -1))
        XCTAssertFalse(PasteStackPanelControlState(occurrenceCount: 3, canAdjustTraversal: false).canMove(position: 1, by: 1))
    }

    func testStackPanelIntentsDeferEachControllerPublicationUntilScheduledActionRuns() {
        let controller = configuredController(with: ["one", "two"])
        let scheduler = QueuedStackIntentScheduler()
        let executor = makeIntentExecutor(controller: controller, scheduler: scheduler)
        let original = controller.occurrences

        executor.execute(.setTraversalDirection(.reverse))
        XCTAssertEqual(scheduler.pendingCount, 1)
        XCTAssertEqual(controller.traversalDirection, .direct)
        scheduler.runNext()
        XCTAssertEqual(controller.traversalDirection, .reverse)

        executor.execute(.moveOccurrence(original[1].id, by: -1))
        XCTAssertEqual(scheduler.pendingCount, 1)
        XCTAssertEqual(controller.occurrences.map(\.id), original.map(\.id))
        scheduler.runNext()
        XCTAssertEqual(controller.occurrences.map(\.id), [original[1].id, original[0].id])
    }

    func testDeferredReorderUsesCapturedIDsAndRejectsAppendRaceAtomically() {
        let controller = configuredController(with: ["one", "two"])
        let scheduler = QueuedStackIntentScheduler()
        let executor = makeIntentExecutor(controller: controller, scheduler: scheduler)
        let original = controller.occurrences

        executor.execute(.moveOccurrence(original[1].id, by: -1))
        controller.appendPersistedHistoryEntry(makeEntry("external"), observedChangeCount: 13, for: controller.captureContext)
        let afterAppend = controller.occurrences
        scheduler.runNext()

        XCTAssertEqual(controller.occurrences, afterAppend)
        XCTAssertEqual(controller.occurrences.map(\.id), [original[0].id, original[1].id, afterAppend[2].id])
    }

    func testDeferredIntentsAreRejectedWhenTraversalLocksOrSessionCancelsFirst() {
        let lockedController = configuredController(with: ["one", "two"])
        let lockedScheduler = QueuedStackIntentScheduler()
        let lockedExecutor = makeIntentExecutor(controller: lockedController, scheduler: lockedScheduler)
        lockedExecutor.execute(.setTraversalDirection(.reverse))
        XCTAssertTrue(lockedController.markTraversalStarted())
        lockedScheduler.runNext()
        XCTAssertEqual(lockedController.traversalDirection, .direct)

        let canceledController = configuredController(with: ["one", "two"])
        let canceledScheduler = QueuedStackIntentScheduler()
        let canceledExecutor = makeIntentExecutor(controller: canceledController, scheduler: canceledScheduler)
        canceledExecutor.execute(.moveOccurrence(canceledController.occurrences[1].id, by: -1))
        canceledController.cancel()
        canceledScheduler.runNext()
        XCTAssertFalse(canceledController.isActive)
        XCTAssertTrue(canceledController.occurrences.isEmpty)
    }

    func testClipboardChangeBeforeStartButPolledAfterStartStaysHistoryOnly() {
        let pasteboard = StackTestPasteboard(changeCount: 10)
        let store = StackTestHistoryStore()
        let viewModel = HistoryViewModel(service: HistoryService(store: store))
        let controller = StackSessionController()
        let coordinator = StackCollectionCaptureCoordinator(
            historyViewModel: viewModel,
            stackSessionController: controller
        )
        let monitor = PasteboardMonitor(pasteboard: pasteboard) { change in
            coordinator.recordExternalText(
                change.text,
                observedChangeCount: change.changeCount,
                stackCaptureContext: controller.captureContext
            )
        }

        pasteboard.setText("before start fixture")
        XCTAssertTrue(controller.startIfNeeded(captureAfterChangeCount: pasteboard.changeCount))
        monitor.poll()

        XCTAssertEqual(store.createdTexts, ["before start fixture"])
        XCTAssertTrue(controller.occurrences.isEmpty)
    }

    func testPreStartClipboardStorageFailureDoesNotSurfaceStackError() {
        let pasteboard = StackTestPasteboard(changeCount: 10)
        let store = StackTestHistoryStore()
        let viewModel = HistoryViewModel(service: HistoryService(store: store))
        let controller = StackSessionController()
        let coordinator = StackCollectionCaptureCoordinator(
            historyViewModel: viewModel,
            stackSessionController: controller
        )
        let monitor = PasteboardMonitor(pasteboard: pasteboard) { change in
            coordinator.recordExternalText(
                change.text,
                observedChangeCount: change.changeCount,
                stackCaptureContext: controller.captureContext
            )
        }

        pasteboard.setText("pre-start failure fixture")
        XCTAssertTrue(controller.startIfNeeded(captureAfterChangeCount: pasteboard.changeCount))
        store.createError = HistoryStoreError.unavailable
        monitor.poll()

        XCTAssertTrue(controller.occurrences.isEmpty)
        XCTAssertFalse(controller.hasCaptureError)
        XCTAssertEqual(viewModel.state, .error)
    }

    func testHotKeyStartsSessionShowsPanelThenDispatchesTaggedCopy() {
        let controller = StackSessionController()
        let trace = StackStartTrace()
        let starter = StackCollectionStarter(
            sessionController: controller,
            currentPasteboardChangeCount: { 41 },
            showStackPanel: {
                XCTAssertTrue(controller.isActive)
                trace.events.append("show")
            },
            copyCommandDispatcher: FakeCopyCommandDispatcher(trace: trace, result: true)
        )

        starter.startFromHotKey()

        XCTAssertEqual(controller.captureContext?.captureAfterChangeCount, 41)
        XCTAssertEqual(trace.events, ["show", "copy"])
        XCTAssertFalse(controller.hasCopyCommandDispatchFailure)
    }

    func testRepeatedHotKeyPreservesSessionAndDispatchesCopyAgain() {
        let controller = StackSessionController()
        let trace = StackStartTrace()
        let starter = StackCollectionStarter(
            sessionController: controller,
            currentPasteboardChangeCount: { 50 },
            showStackPanel: { trace.events.append("show") },
            copyCommandDispatcher: FakeCopyCommandDispatcher(trace: trace, result: true)
        )

        starter.startFromHotKey()
        let originalContext = controller.captureContext
        controller.appendPersistedHistoryEntry(makeEntry("existing"), observedChangeCount: 51, for: originalContext)
        starter.startFromHotKey()

        XCTAssertEqual(controller.captureContext, originalContext)
        XCTAssertEqual(controller.occurrences.map(\.text), ["existing"])
        XCTAssertEqual(trace.events, ["show", "copy", "show", "copy"])
    }

    func testMenuStartIsEmptyAndDoesNotDispatchCopy() {
        let controller = StackSessionController()
        let trace = StackStartTrace()
        let starter = StackCollectionStarter(
            sessionController: controller,
            currentPasteboardChangeCount: { 60 },
            showStackPanel: { trace.events.append("show") },
            copyCommandDispatcher: FakeCopyCommandDispatcher(trace: trace, result: true)
        )

        starter.startFromMenu()

        XCTAssertTrue(controller.isActive)
        XCTAssertTrue(controller.occurrences.isEmpty)
        XCTAssertEqual(trace.events, ["show"])
    }

    func testCopyDispatchFailureShowsRetryableStackErrorWithoutClaimingCapture() {
        let controller = StackSessionController()
        let trace = StackStartTrace()
        let starter = StackCollectionStarter(
            sessionController: controller,
            currentPasteboardChangeCount: { 70 },
            showStackPanel: { trace.events.append("show") },
            copyCommandDispatcher: FakeCopyCommandDispatcher(trace: trace, result: false)
        )

        starter.startFromHotKey()

        XCTAssertEqual(trace.events, ["show", "copy"])
        XCTAssertTrue(controller.hasCopyCommandDispatchFailure)
        XCTAssertTrue(controller.occurrences.isEmpty)
        XCTAssertFalse(controller.hasCaptureError)
    }

    private func makeEntry(_ text: String) -> HistoryEntry {
        HistoryEntry(id: UUID(), text: text, activityAt: .now)
    }

    private func configuredController(with texts: [String]) -> StackSessionController {
        let controller = StackSessionController()
        XCTAssertTrue(controller.startIfNeeded(captureAfterChangeCount: 10))
        let context = controller.captureContext
        for (offset, text) in texts.enumerated() {
            controller.appendPersistedHistoryEntry(makeEntry(text), observedChangeCount: 11 + offset, for: context)
        }
        return controller
    }

    private func makeIntentExecutor(
        controller: StackSessionController,
        scheduler: QueuedStackIntentScheduler
    ) -> PasteStackPanelIntentExecutor {
        PasteStackPanelIntentExecutor(
            occurrences: { controller.occurrences },
            canAdjustTraversal: { controller.canAdjustTraversal },
            setTraversalDirection: controller.setTraversalDirection,
            reorder: controller.reorder,
            schedule: scheduler.schedule
        )
    }
}

final class FloatingPanelPlacementTests: XCTestCase {
    func testCentersWithinCurrentDisplayVisibleFrame() {
        let visibleFrame = NSRect(x: 100, y: 50, width: 1_000, height: 700)

        let origin = FloatingPanelPlacement.origin(
            panelSize: NSSize(width: 400, height: 280),
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(origin, NSPoint(x: 400, y: 260))
    }

    func testClampsPanelOriginInsideVisibleFrame() {
        let visibleFrame = NSRect(x: 10, y: 20, width: 300, height: 180)

        let origin = FloatingPanelPlacement.origin(
            panelSize: NSSize(width: 400, height: 280),
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(origin, NSPoint(x: 10, y: 20))
    }
}

private final class StackTestHistoryStore: HistoryStoring {
    var entries: [HistoryEntry] = []
    var createdTexts: [String] = []
    var createError: Error?
    var onCreate: (() -> Void)?

    func fetchCurrent(since cutoff: Date) throws -> [HistoryEntry] {
        entries.filter { $0.activityAt > cutoff }
    }

    func create(text: String, activityAt: Date) throws -> HistoryEntry {
        onCreate?()
        if let createError { throw createError }
        createdTexts.append(text)
        let entry = HistoryEntry(id: UUID(), text: text, activityAt: activityAt)
        entries.append(entry)
        return entry
    }

    func markUsed(id: UUID, activityAt: Date) throws {}
    func delete(id: UUID) throws {}
    func clearAll() throws {}
}

private final class WeakBox<Object: AnyObject> {
    weak var value: Object?
}

private final class StackTestPasteboard: PasteboardReading {
    private(set) var changeCount: Int
    private var text: String?

    init(changeCount: Int) {
        self.changeCount = changeCount
    }

    func textValue() -> String? { text }

    func setText(_ text: String) {
        self.text = text
        changeCount += 1
    }
}

private final class StackStartTrace {
    var events: [String] = []
}

private final class QueuedStackIntentScheduler {
    private var actions: [() -> Void] = []

    var pendingCount: Int { actions.count }

    func schedule(_ action: @escaping () -> Void) {
        actions.append(action)
    }

    func runNext() {
        guard !actions.isEmpty else { return }
        actions.removeFirst()()
    }
}

private final class FakeCopyCommandDispatcher: TaggedCopyCommandDispatching {
    let trace: StackStartTrace
    let result: Bool

    init(trace: StackStartTrace, result: Bool) {
        self.trace = trace
        self.result = result
    }

    func postTaggedCommandC() -> Bool {
        trace.events.append("copy")
        return result
    }
}
