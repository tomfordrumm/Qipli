import AppKit
import Combine
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

    func testCaptureBeforeStartAndCaptureFromCanceledSessionNeverEnterNewSession() async {
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
        await coordinator.recordExternalText("pre-start fixture", observedChangeCount: 10, stackCaptureContext: preStartContext)
        XCTAssertTrue(controller.occurrences.isEmpty)

        let canceledContext = controller.captureContext
        controller.cancel()
        XCTAssertTrue(controller.startIfNeeded(captureAfterChangeCount: 20))
        await coordinator.recordExternalText("stale fixture", observedChangeCount: 21, stackCaptureContext: canceledContext)

        XCTAssertEqual(store.createdTexts, ["pre-start fixture", "stale fixture"])
        XCTAssertTrue(controller.occurrences.isEmpty)
    }

    func testHistorySavesBeforeStackAppendAndSaveFailureLeavesStackUnchanged() async {
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

        await coordinator.recordExternalText("durable fixture", observedChangeCount: 11, stackCaptureContext: context)
        store.onCreate = nil

        XCTAssertEqual(store.createdTexts, ["durable fixture"])
        XCTAssertEqual(controller.occurrences.map(\.text), ["durable fixture"])
        XCTAssertFalse(controller.hasCaptureError)

        store.createError = HistoryStoreError.unavailable
        await coordinator.recordExternalText("failed fixture", observedChangeCount: 12, stackCaptureContext: context)

        XCTAssertEqual(controller.occurrences.map(\.text), ["durable fixture"])
        XCTAssertTrue(controller.hasCaptureError)
    }

    func testWhitespaceOnlyCaptureIsIgnoredWithoutHistoryOrStackError() async {
        let store = StackTestHistoryStore()
        let viewModel = HistoryViewModel(service: HistoryService(store: store))
        let controller = StackSessionController()
        let coordinator = StackCollectionCaptureCoordinator(
            historyViewModel: viewModel,
            stackSessionController: controller
        )
        XCTAssertTrue(controller.startIfNeeded(captureAfterChangeCount: 10))

        await coordinator.recordExternalText(
            " \t\n",
            observedChangeCount: 11,
            stackCaptureContext: controller.captureContext
        )

        XCTAssertTrue(store.createdTexts.isEmpty)
        XCTAssertTrue(controller.occurrences.isEmpty)
        XCTAssertFalse(controller.hasCaptureError)
    }

    func testQueuedCapturesPersistAndPublishInObservedOrder() async {
        let store = StackTestHistoryStore()
        let viewModel = HistoryViewModel(service: HistoryService(store: store))
        let controller = StackSessionController()
        let coordinator = StackCollectionCaptureCoordinator(
            historyViewModel: viewModel,
            stackSessionController: controller
        )
        XCTAssertTrue(controller.startIfNeeded(captureAfterChangeCount: 10))
        let context = controller.captureContext

        coordinator.enqueueExternalText("duplicate", observedChangeCount: 11, stackCaptureContext: context)
        coordinator.enqueueExternalText("duplicate", observedChangeCount: 12, stackCaptureContext: context)
        coordinator.enqueueExternalText("third", observedChangeCount: 13, stackCaptureContext: context)
        await coordinator.drainPendingCaptures()

        XCTAssertEqual(store.createdTexts, ["duplicate", "duplicate", "third"])
        XCTAssertEqual(controller.occurrences.map(\.text), ["duplicate", "duplicate", "third"])
        XCTAssertNotEqual(controller.occurrences[0].id, controller.occurrences[1].id)
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

        XCTAssertEqual(PasteStackPanelControlState(occurrenceCount: 0, canAdjustTraversal: true), .init(occurrenceCount: 0, canAdjustTraversal: true))
        XCTAssertFalse(PasteStackPanelControlState(occurrenceCount: 0, canAdjustTraversal: true).canReorder)
        XCTAssertTrue(PasteStackPanelControlState(occurrenceCount: 1, canAdjustTraversal: true).canChooseDirection)
        XCTAssertFalse(PasteStackPanelControlState(occurrenceCount: 1, canAdjustTraversal: true).canReorder)
        XCTAssertTrue(PasteStackPanelControlState(occurrenceCount: 3, canAdjustTraversal: true).canMove(position: 1, by: -1))
        XCTAssertFalse(PasteStackPanelControlState(occurrenceCount: 3, canAdjustTraversal: false).canMove(position: 1, by: 1))
    }

    func testDirectionToggleAndAccessibleMoveAdmissionDescribeOnlyAvailableActions() {
        XCTAssertEqual(
            PasteStackDirectionToggleConfiguration.resolve(direction: .direct),
            .init(
                iconSystemName: "arrow.down",
                nextDirection: .reverse,
                accessibilityValue: "Top to bottom",
                accessibilityHint: "Switches to bottom to top"
            )
        )
        XCTAssertEqual(
            PasteStackDirectionToggleConfiguration.resolve(direction: .reverse),
            .init(
                iconSystemName: "arrow.up",
                nextDirection: .direct,
                accessibilityValue: "Bottom to top",
                accessibilityHint: "Switches to top to bottom"
            )
        )

        let adjustable = PasteStackPanelControlState(occurrenceCount: 3, canAdjustTraversal: true)
        XCTAssertEqual(adjustable.accessibilityMoveDirections(position: 0), [.down])
        XCTAssertEqual(adjustable.accessibilityMoveDirections(position: 1), [.up, .down])
        XCTAssertEqual(adjustable.accessibilityMoveDirections(position: 2), [.up])
        XCTAssertTrue(PasteStackPanelControlState(
            occurrenceCount: 3,
            canAdjustTraversal: false
        ).accessibilityMoveDirections(position: 1).isEmpty)
        XCTAssertEqual(PasteStackPanelAccessibility.moveActionLabel(direction: .up), "Move Up")
        XCTAssertEqual(PasteStackPanelAccessibility.moveActionLabel(direction: .down), "Move Down")
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

    func testReactivateIntentIsUUIDBasedDeferredAndAccessible() {
        let controller = configuredController(with: ["used", "pending"])
        let usedID = controller.occurrences[0].id
        XCTAssertTrue(controller.markTraversalStarted())
        XCTAssertEqual(controller.acceptNextPasteInput(), .consumeAndDispatch)
        XCTAssertTrue(controller.completePasteReservation(try! XCTUnwrap(controller.currentPasteReservation)))

        let scheduler = QueuedStackIntentScheduler()
        let executor = PasteStackPanelIntentExecutor(
            occurrences: { controller.occurrences },
            canAdjustTraversal: { controller.canAdjustTraversal },
            setTraversalDirection: controller.setTraversalDirection,
            reorder: controller.reorder,
            reactivate: controller.reactivateOccurrence,
            schedule: scheduler.schedule
        )
        executor.execute(.reactivate(usedID))
        XCTAssertNil(controller.reactivationPriorityID)
        XCTAssertEqual(scheduler.pendingCount, 1)
        scheduler.runNext()
        XCTAssertEqual(controller.reactivationPriorityID, usedID)
        XCTAssertEqual(PasteStackPanelAccessibility.reactivatedNextItemLabel, "Reactivated item is next")
        XCTAssertEqual(PasteStackPanelAccessibility.reactivatingItemLabel, "Preparing reactivated item")
        XCTAssertEqual(PasteStackPanelAccessibility.reactivateLabel(position: 1), "Reactivate used item 2")
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

    func testClipboardChangeBeforeStartButPolledAfterStartStaysHistoryOnly() async {
        let pasteboard = StackTestPasteboard(changeCount: 10)
        let store = StackTestHistoryStore()
        let viewModel = HistoryViewModel(service: HistoryService(store: store))
        let controller = StackSessionController()
        let coordinator = StackCollectionCaptureCoordinator(
            historyViewModel: viewModel,
            stackSessionController: controller
        )
        let monitor = PasteboardMonitor(pasteboard: pasteboard) { change in
            coordinator.enqueueExternalText(
                change.text,
                observedChangeCount: change.changeCount,
                stackCaptureContext: controller.captureContext
            )
        }
        monitor.start(interval: 3_600)
        defer { monitor.stop() }

        pasteboard.setText("before start fixture")
        XCTAssertTrue(controller.startIfNeeded(captureAfterChangeCount: pasteboard.changeCount))
        monitor.poll()
        await coordinator.drainPendingCaptures()

        XCTAssertEqual(store.createdTexts, ["before start fixture"])
        XCTAssertTrue(controller.occurrences.isEmpty)
    }

    func testPreStartClipboardStorageFailureDoesNotSurfaceStackError() async {
        let pasteboard = StackTestPasteboard(changeCount: 10)
        let store = StackTestHistoryStore()
        let viewModel = HistoryViewModel(service: HistoryService(store: store))
        let controller = StackSessionController()
        let coordinator = StackCollectionCaptureCoordinator(
            historyViewModel: viewModel,
            stackSessionController: controller
        )
        let monitor = PasteboardMonitor(pasteboard: pasteboard) { change in
            coordinator.enqueueExternalText(
                change.text,
                observedChangeCount: change.changeCount,
                stackCaptureContext: controller.captureContext
            )
        }
        monitor.start(interval: 3_600)
        defer { monitor.stop() }

        pasteboard.setText("pre-start failure fixture")
        XCTAssertTrue(controller.startIfNeeded(captureAfterChangeCount: pasteboard.changeCount))
        store.createError = HistoryStoreError.unavailable
        monitor.poll()
        await coordinator.drainPendingCaptures()

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

    func testSequentialPasteDirectWritesExactOccurrencesAndPublishesUsedBeforeDeferredFinish() {
        let controller = configuredController(with: ["fixture 🦊\nfirst", "fixture 🦊\nfirst", "third"])
        let writer = StackPasteWriter(changeCount: 40)
        let dispatcher = StackPasteDispatcher(results: [true, true, true])
        let finishScheduler = QueuedFinishScheduler()
        var finishPresentationCount = 0
        let executor = makeSequentialExecutor(
            controller: controller,
            writer: writer,
            dispatcher: dispatcher,
            finishScheduler: finishScheduler,
            finishPresentation: { finishPresentationCount += 1 }
        )

        for expectedID in controller.occurrences.map(\.id) {
            XCTAssertEqual(controller.acceptNextPasteInput(), .consumeAndDispatch)
            executor.executeReservedPaste()
            XCTAssertEqual(controller.occurrences.first(where: { $0.id == expectedID })?.state, .used)
        }

        XCTAssertEqual(writer.texts, ["fixture 🦊\nfirst", "fixture 🦊\nfirst", "third"])
        XCTAssertEqual(dispatcher.dispatchCount, 3)
        XCTAssertEqual(controller.occurrences.map(\.state), [.used, .used, .used])
        XCTAssertTrue(controller.traversalHasStarted)
        XCTAssertFalse(controller.canAdjustTraversal)
        XCTAssertTrue(controller.isActive)
        XCTAssertEqual(finishPresentationCount, 0)

        finishScheduler.runNext()
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(finishPresentationCount, 1)
    }

    func testSequentialPastePublishesProcessingBeforeDeferredProduction() {
        let controller = configuredController(with: ["layout fixture"])
        let writer = StackPasteWriter(changeCount: 40)
        let productionScheduler = QueuedFinishScheduler()
        let finishScheduler = QueuedFinishScheduler()
        let executor = makeSequentialExecutor(
            controller: controller,
            writer: writer,
            dispatcher: StackPasteDispatcher(results: [true]),
            productionSchedule: productionScheduler.schedule,
            finishScheduler: finishScheduler
        )

        XCTAssertEqual(controller.acceptNextPasteInput(), .consumeAndDispatch)
        executor.executeReservedPaste()

        XCTAssertEqual(controller.occurrences.first?.state, .processing)
        XCTAssertTrue(writer.texts.isEmpty)
        XCTAssertEqual(productionScheduler.pendingCount, 1)
        XCTAssertEqual(finishScheduler.pendingCount, 0)

        productionScheduler.runNext()

        XCTAssertEqual(controller.occurrences.first?.state, .used)
        XCTAssertEqual(writer.texts, ["layout fixture"])
        XCTAssertEqual(finishScheduler.pendingCount, 1)
    }

    func testSequentialPasteDoesNotPublishWhenFailureStateIsAlreadyClear() {
        let controller = configuredController(with: ["publication fixture"])
        let writer = StackPasteWriter(changeCount: 40)
        let executor = makeSequentialExecutor(
            controller: controller,
            writer: writer,
            dispatcher: StackPasteDispatcher(results: [true])
        )
        var publicationCount = 0
        let observation = controller.objectWillChange.sink { _ in publicationCount += 1 }
        defer { observation.cancel() }

        XCTAssertEqual(controller.acceptNextPasteInput(), .consumeAndDispatch)
        executor.executeReservedPaste()

        // Processing plus first-paste traversal lock are one logical snapshot;
        // completion is the second. Clearing an already-nil failure must not
        // add another publication.
        XCTAssertEqual(publicationCount, 2)
        XCTAssertEqual(controller.occurrences.first?.state, .used)
    }

    func testSequentialPasteReverseUsesExactOccurrenceIDsAndPreservesUnicodeMultilineText() {
        let controller = configuredController(with: ["alpha", "βeta\nline", "alpha"])
        XCTAssertTrue(controller.setTraversalDirection(.reverse))
        let writer = StackPasteWriter(changeCount: 10)
        let dispatcher = StackPasteDispatcher(results: [true, true, true])
        let executor = makeSequentialExecutor(controller: controller, writer: writer, dispatcher: dispatcher)

        while controller.hasPendingOccurrence {
            XCTAssertEqual(controller.acceptNextPasteInput(), .consumeAndDispatch)
            executor.executeReservedPaste()
        }

        XCTAssertEqual(writer.texts, ["alpha", "βeta\nline", "alpha"])
        XCTAssertEqual(controller.occurrences.map(\.state), [.used, .used, .used])
    }

    func testRapidPasteInputConsumesRepeatWithoutASecondReservationOrDispatch() {
        let controller = configuredController(with: ["one", "two"])
        let writer = StackPasteWriter(changeCount: 20)
        let dispatcher = StackPasteDispatcher(results: [true])
        let executor = makeSequentialExecutor(controller: controller, writer: writer, dispatcher: dispatcher)

        XCTAssertEqual(controller.acceptNextPasteInput(), .consumeAndDispatch)
        XCTAssertEqual(controller.acceptNextPasteInput(), .consume)
        executor.executeReservedPaste()

        XCTAssertEqual(writer.texts, ["one"])
        XCTAssertEqual(dispatcher.dispatchCount, 1)
        XCTAssertEqual(controller.occurrences.map(\.state), [.used, .pending])
        XCTAssertEqual(controller.nextOccurrence?.text, "two")
    }

    func testReactivationPriorityPreservesDirectAndReverseTraversalCursors() {
        let direct = configuredController(with: ["direct first", "direct next"])
        let directWriter = StackPasteWriter(changeCount: 10)
        let directExecutor = makeSequentialExecutor(
            controller: direct,
            writer: directWriter,
            dispatcher: StackPasteDispatcher(results: [true, true])
        )
        let directFirstID = direct.nextOccurrence?.id
        XCTAssertEqual(direct.acceptNextPasteInput(), .consumeAndDispatch)
        directExecutor.executeReservedPaste()
        let directTraversalNextID = direct.nextOccurrence?.id
        XCTAssertTrue(direct.reactivateOccurrence(id: try! XCTUnwrap(directFirstID)))
        XCTAssertEqual(direct.nextOccurrence?.id, directFirstID)
        XCTAssertEqual(direct.acceptNextPasteInput(), .consumeAndDispatch)
        directExecutor.executeReservedPaste()
        XCTAssertNil(direct.reactivationPriorityID)
        XCTAssertEqual(direct.nextOccurrence?.id, directTraversalNextID)

        let reverse = configuredController(with: ["reverse last", "reverse next"])
        XCTAssertTrue(reverse.setTraversalDirection(.reverse))
        let reverseWriter = StackPasteWriter(changeCount: 20)
        let reverseExecutor = makeSequentialExecutor(
            controller: reverse,
            writer: reverseWriter,
            dispatcher: StackPasteDispatcher(results: [true, true])
        )
        let reverseFirstID = reverse.nextOccurrence?.id
        XCTAssertEqual(reverse.acceptNextPasteInput(), .consumeAndDispatch)
        reverseExecutor.executeReservedPaste()
        let reverseTraversalNextID = reverse.nextOccurrence?.id
        XCTAssertTrue(reverse.reactivateOccurrence(id: try! XCTUnwrap(reverseFirstID)))
        XCTAssertEqual(reverse.acceptNextPasteInput(), .consumeAndDispatch)
        reverseExecutor.executeReservedPaste()
        XCTAssertEqual(reverse.nextOccurrence?.id, reverseTraversalNextID)
    }

    func testReactivationReplacementRepeatAndFailureRollbackKeepUsedPriorityRetryable() {
        let controller = configuredController(with: ["first", "second", "pending"])
        let writer = StackPasteWriter(changeCount: 30)
        let executor = makeSequentialExecutor(
            controller: controller,
            writer: writer,
            dispatcher: StackPasteDispatcher(results: [true, true, true])
        )
        let firstID = controller.occurrences[0].id
        let secondID = controller.occurrences[1].id
        let pendingID = controller.occurrences[2].id

        for _ in 0 ..< 2 {
            XCTAssertEqual(controller.acceptNextPasteInput(), .consumeAndDispatch)
            executor.executeReservedPaste()
        }
        XCTAssertEqual(controller.nextOccurrence?.id, pendingID)

        XCTAssertTrue(controller.reactivateOccurrence(id: firstID))
        XCTAssertEqual(controller.reactivationPriorityID, firstID)
        XCTAssertTrue(controller.reactivateOccurrence(id: secondID))
        XCTAssertEqual(controller.reactivationPriorityID, secondID)
        XCTAssertTrue(controller.reactivateOccurrence(id: secondID))

        writer.shouldFail = true
        XCTAssertEqual(controller.acceptNextPasteInput(), .consumeAndDispatch)
        XCTAssertEqual(controller.currentPasteReservation?.origin, .reactivation)
        executor.executeReservedPaste()
        XCTAssertEqual(controller.occurrences.first(where: { $0.id == secondID })?.state, .used)
        XCTAssertEqual(controller.reactivationPriorityID, secondID)
        XCTAssertEqual(controller.nextOccurrence?.id, secondID)
        XCTAssertEqual(controller.pasteFailure, .pasteboardWriteFailed)

        writer.shouldFail = false
        XCTAssertEqual(controller.acceptNextPasteInput(), .consumeAndDispatch)
        executor.executeReservedPaste()
        XCTAssertNil(controller.reactivationPriorityID)
        XCTAssertEqual(controller.nextOccurrence?.id, pendingID)
        XCTAssertEqual(writer.texts, ["first", "second", "second"])
    }

    func testReactivatePreviousUsesLastSuccessDoesNotPasteImmediatelyAndIsIdempotent() {
        let controller = configuredController(with: ["previous", "pending"])
        let writer = StackPasteWriter(changeCount: 40)
        let dispatcher = StackPasteDispatcher(results: [true, true])
        let executor = makeSequentialExecutor(controller: controller, writer: writer, dispatcher: dispatcher)
        let previousID = controller.occurrences[0].id
        let pendingID = controller.occurrences[1].id

        XCTAssertEqual(controller.acceptReactivatePreviousInput(), .passThrough)
        XCTAssertEqual(controller.acceptNextPasteInput(), .consumeAndDispatch)
        executor.executeReservedPaste()
        XCTAssertEqual(controller.nextOccurrence?.id, pendingID)

        var publicationCount = 0
        let observation = controller.objectWillChange.sink { _ in publicationCount += 1 }
        defer { observation.cancel() }

        XCTAssertEqual(controller.acceptReactivatePreviousInput(), .consumeAndReactivate)
        controller.publishAcceptedReactivatePreviousState()
        XCTAssertEqual(controller.reactivationPriorityID, previousID)
        XCTAssertEqual(writer.texts, ["previous"])
        XCTAssertEqual(publicationCount, 1)
        XCTAssertEqual(controller.acceptReactivatePreviousInput(), .consumeAndReactivate)
        controller.publishAcceptedReactivatePreviousState()
        XCTAssertEqual(controller.reactivationPriorityID, previousID)
        XCTAssertEqual(writer.texts, ["previous"])
        XCTAssertEqual(publicationCount, 1)

        XCTAssertEqual(controller.acceptNextPasteInput(), .consumeAndDispatch)
        executor.executeReservedPaste()
        XCTAssertEqual(writer.texts, ["previous", "previous"])
        XCTAssertNil(controller.reactivationPriorityID)
        XCTAssertEqual(controller.nextOccurrence?.id, pendingID)
    }

    func testReactivatePreviousReplacesManualPriorityAndLeavesInFlightReservationUnchanged() {
        let controller = configuredController(with: ["manual", "previous", "pending"])
        let writer = StackPasteWriter(changeCount: 50)
        let executor = makeSequentialExecutor(
            controller: controller,
            writer: writer,
            dispatcher: StackPasteDispatcher(results: [true, true, true])
        )
        let manualID = controller.occurrences[0].id
        let previousID = controller.occurrences[1].id

        for _ in 0 ..< 2 {
            XCTAssertEqual(controller.acceptNextPasteInput(), .consumeAndDispatch)
            executor.executeReservedPaste()
        }
        XCTAssertTrue(controller.reactivateOccurrence(id: manualID))
        XCTAssertEqual(controller.reactivationPriorityID, manualID)
        XCTAssertEqual(controller.acceptReactivatePreviousInput(), .consumeAndReactivate)
        controller.publishAcceptedReactivatePreviousState()
        XCTAssertEqual(controller.reactivationPriorityID, previousID)

        XCTAssertEqual(controller.acceptNextPasteInput(), .consumeAndDispatch)
        let reservationID = controller.currentPasteReservation?.occurrence.id
        XCTAssertEqual(controller.acceptReactivatePreviousInput(), .consume)
        XCTAssertEqual(controller.currentPasteReservation?.occurrence.id, reservationID)
        executor.executeReservedPaste()
    }

    func testUsedReactivationDuringTraversalProcessingKeepsReservationAndBecomesNext() {
        let controller = configuredController(with: ["used", "processing", "later"])
        let writer = StackPasteWriter(changeCount: 55)
        let production = QueuedFinishScheduler()
        let executor = makeSequentialExecutor(
            controller: controller,
            writer: writer,
            dispatcher: StackPasteDispatcher(results: [true, true]),
            productionSchedule: production.schedule
        )
        let usedID = controller.occurrences[0].id
        let processingID = controller.occurrences[1].id

        XCTAssertEqual(controller.acceptNextPasteInput(), .consumeAndDispatch)
        executor.executeReservedPaste()
        production.runNext()
        XCTAssertEqual(controller.acceptNextPasteInput(), .consumeAndDispatch)
        XCTAssertEqual(controller.currentPasteReservation?.occurrence.id, processingID)
        XCTAssertTrue(controller.reactivateOccurrence(id: usedID))
        XCTAssertEqual(controller.reactivationPriorityID, usedID)
        XCTAssertEqual(controller.currentPasteReservation?.occurrence.id, processingID)
        executor.executeReservedPaste()
        production.runNext()
        XCTAssertEqual(controller.nextOccurrence?.id, usedID)
    }

    func testReactivateRejectsPendingProcessingAndStaleIDsWithoutPublishingExtraState() {
        let controller = configuredController(with: ["used", "pending"])
        let writer = StackPasteWriter(changeCount: 60)
        let production = QueuedFinishScheduler()
        let executor = makeSequentialExecutor(
            controller: controller,
            writer: writer,
            dispatcher: StackPasteDispatcher(results: [true]),
            productionSchedule: production.schedule
        )
        let usedID = controller.occurrences[0].id
        let pendingID = controller.occurrences[1].id

        XCTAssertFalse(controller.reactivateOccurrence(id: pendingID))
        XCTAssertFalse(controller.reactivateOccurrence(id: UUID()))
        XCTAssertEqual(controller.acceptNextPasteInput(), .consumeAndDispatch)
        executor.executeReservedPaste()
        production.runNext()
        XCTAssertTrue(controller.reactivateOccurrence(id: usedID))
        XCTAssertEqual(controller.acceptNextPasteInput(), .consumeAndDispatch)
        XCTAssertFalse(controller.reactivateOccurrence(id: usedID))
        controller.cancel()
        XCTAssertFalse(controller.reactivateOccurrence(id: usedID))
        XCTAssertEqual(controller.acceptReactivatePreviousInput(), .passThrough)
    }

    func testReactivationPreventsDeferredAutoFinishAndCancellationInvalidatesAllReservations() {
        let controller = configuredController(with: ["finish fixture"])
        let writer = StackPasteWriter(changeCount: 70)
        let finish = QueuedFinishScheduler()
        let executor = makeSequentialExecutor(
            controller: controller,
            writer: writer,
            dispatcher: StackPasteDispatcher(results: [true]),
            finishScheduler: finish
        )
        let itemID = controller.occurrences[0].id

        XCTAssertEqual(controller.acceptNextPasteInput(), .consumeAndDispatch)
        executor.executeReservedPaste()
        XCTAssertEqual(finish.pendingCount, 1)
        XCTAssertTrue(controller.reactivateOccurrence(id: itemID))
        finish.runNext()
        XCTAssertTrue(controller.isActive)
        XCTAssertEqual(controller.reactivationPriorityID, itemID)

        let production = QueuedFinishScheduler()
        let canceledExecutor = makeSequentialExecutor(
            controller: controller,
            writer: writer,
            dispatcher: StackPasteDispatcher(results: [true]),
            productionSchedule: production.schedule
        )
        XCTAssertEqual(controller.acceptNextPasteInput(), .consumeAndDispatch)
        canceledExecutor.executeReservedPaste()
        controller.cancel()
        controller.cancel()
        XCTAssertEqual(controller.acceptNextPasteInput(), .passThrough)
        XCTAssertEqual(controller.acceptReactivatePreviousInput(), .passThrough)
        production.runNext()
        XCTAssertEqual(writer.texts, ["finish fixture"])
    }

    func testCancelIsImmediateAndIdempotentForEmptyCollectingPartialPriorityAndProcessingSessions() {
        let empty = StackSessionController()
        XCTAssertTrue(empty.startIfNeeded(captureAfterChangeCount: 1))
        empty.cancel()
        empty.cancel()
        XCTAssertFalse(empty.isActive)
        XCTAssertEqual(empty.acceptNextPasteInput(), .passThrough)

        let collecting = configuredController(with: ["collecting"])
        collecting.cancel()
        collecting.cancel()
        XCTAssertFalse(collecting.isActive)
        XCTAssertTrue(collecting.occurrences.isEmpty)

        let partial = configuredController(with: ["used", "pending"])
        let partialExecutor = makeSequentialExecutor(
            controller: partial,
            writer: StackPasteWriter(changeCount: 80),
            dispatcher: StackPasteDispatcher(results: [true])
        )
        XCTAssertEqual(partial.acceptNextPasteInput(), .consumeAndDispatch)
        partialExecutor.executeReservedPaste()
        partial.cancel()
        XCTAssertFalse(partial.isActive)

        let priority = configuredController(with: ["priority", "pending"])
        let priorityExecutor = makeSequentialExecutor(
            controller: priority,
            writer: StackPasteWriter(changeCount: 90),
            dispatcher: StackPasteDispatcher(results: [true])
        )
        let priorityID = priority.occurrences[0].id
        XCTAssertEqual(priority.acceptNextPasteInput(), .consumeAndDispatch)
        priorityExecutor.executeReservedPaste()
        XCTAssertTrue(priority.reactivateOccurrence(id: priorityID))
        priority.cancel()
        XCTAssertNil(priority.reactivationPriorityID)
        XCTAssertFalse(priority.isActive)

        let processing = configuredController(with: ["processing"])
        XCTAssertEqual(processing.acceptNextPasteInput(), .consumeAndDispatch)
        XCTAssertNotNil(processing.currentPasteReservation)
        processing.cancel()
        processing.cancel()
        XCTAssertNil(processing.currentPasteReservation)
        XCTAssertEqual(processing.acceptNextPasteInput(), .passThrough)
    }

    func testPasteAdmissionPassesThroughForInactiveEmptyAndFinishedStacks() {
        let controller = StackSessionController()
        XCTAssertEqual(controller.acceptNextPasteInput(), .passThrough)

        XCTAssertTrue(controller.startIfNeeded(captureAfterChangeCount: 1))
        XCTAssertEqual(controller.acceptNextPasteInput(), .passThrough)

        let context = controller.captureContext
        controller.appendPersistedHistoryEntry(makeEntry("one"), observedChangeCount: 2, for: context)
        let executor = makeSequentialExecutor(
            controller: controller,
            writer: StackPasteWriter(changeCount: 2),
            dispatcher: StackPasteDispatcher(results: [true])
        )
        XCTAssertEqual(controller.acceptNextPasteInput(), .consumeAndDispatch)
        executor.executeReservedPaste()
        XCTAssertEqual(controller.acceptNextPasteInput(), .passThrough)
    }

    func testSequentialPasteFailureRollsBackReservationAndRetryUsesSameOccurrence() {
        let controller = configuredController(with: ["retry fixture"])
        let writer = StackPasteWriter(changeCount: 30, shouldFail: true)
        let dispatcher = StackPasteDispatcher(results: [true])
        let executor = makeSequentialExecutor(controller: controller, writer: writer, dispatcher: dispatcher)
        let expectedID = controller.nextOccurrence?.id

        XCTAssertEqual(controller.acceptNextPasteInput(), .consumeAndDispatch)
        executor.executeReservedPaste()
        XCTAssertEqual(controller.occurrences.first?.state, .pending)
        XCTAssertEqual(controller.nextOccurrence?.id, expectedID)
        XCTAssertEqual(controller.pasteFailure, .pasteboardWriteFailed)
        XCTAssertEqual(dispatcher.dispatchCount, 0)

        writer.shouldFail = false
        XCTAssertEqual(controller.acceptNextPasteInput(), .consumeAndDispatch)
        executor.executeReservedPaste()
        XCTAssertEqual(controller.occurrences.first?.state, .used)
        XCTAssertEqual(writer.texts, ["retry fixture"])
    }

    func testDispatchAndPermissionFailuresLeaveTheOccurrencePendingForRetry() {
        let controller = configuredController(with: ["pending fixture"])
        let permission = StackPastePermission(state: .denied)
        let writer = StackPasteWriter(changeCount: 5)
        let dispatcher = StackPasteDispatcher(results: [false, true])
        let executor = makeSequentialExecutor(
            controller: controller,
            writer: writer,
            dispatcher: dispatcher,
            permission: permission
        )

        XCTAssertEqual(controller.acceptNextPasteInput(), .consumeAndDispatch)
        executor.executeReservedPaste()
        XCTAssertEqual(controller.occurrences.first?.state, .pending)
        XCTAssertEqual(controller.pasteFailure, .accessibilityRequired)
        XCTAssertTrue(writer.texts.isEmpty)

        permission.state = .granted
        XCTAssertEqual(controller.acceptNextPasteInput(), .consumeAndDispatch)
        executor.executeReservedPaste()
        XCTAssertEqual(controller.occurrences.first?.state, .pending)
        XCTAssertEqual(controller.pasteFailure, .commandDispatchFailed)
        XCTAssertEqual(writer.texts, ["pending fixture"])

        XCTAssertEqual(controller.acceptNextPasteInput(), .consumeAndDispatch)
        executor.executeReservedPaste()
        XCTAssertEqual(controller.occurrences.first?.state, .used)
    }

    func testCancellationAndAppendRacesDoNotDispatchStaleReservationOrFinishNewPendingItem() {
        let canceled = configuredController(with: ["cancel fixture"])
        let canceledWriter = StackPasteWriter(changeCount: 3)
        let canceledExecutor = makeSequentialExecutor(
            controller: canceled,
            writer: canceledWriter,
            dispatcher: StackPasteDispatcher(results: [true])
        )
        XCTAssertEqual(canceled.acceptNextPasteInput(), .consumeAndDispatch)
        canceled.cancel()
        canceledExecutor.executeReservedPaste()
        XCTAssertTrue(canceledWriter.texts.isEmpty)

        let appended = configuredController(with: ["first"])
        let appendedWriter = StackPasteWriter(changeCount: 4)
        let scheduler = QueuedFinishScheduler()
        let appendedExecutor = makeSequentialExecutor(
            controller: appended,
            writer: appendedWriter,
            dispatcher: StackPasteDispatcher(results: [true]),
            finishScheduler: scheduler
        )
        XCTAssertEqual(appended.acceptNextPasteInput(), .consumeAndDispatch)
        appended.appendPersistedHistoryEntry(makeEntry("late append"), observedChangeCount: 99, for: appended.captureContext)
        appendedExecutor.executeReservedPaste()
        scheduler.runNext()
        XCTAssertTrue(appended.isActive)
        XCTAssertEqual(appended.occurrences.map(\.state), [.used, .pending])
    }

    func testSelfWriteSuppressionUsesTheWriterFinalChangeCountExactlyOnce() {
        let pasteboard = StackTestPasteboard(changeCount: 10)
        let controller = configuredController(with: ["suppression fixture"])
        var observed = 0
        let monitor = PasteboardMonitor(pasteboard: pasteboard) { _ in observed += 1 }
        monitor.start(interval: 3_600)
        defer { monitor.stop() }
        let writer = StackPasteboardWriter(pasteboard: pasteboard)
        let executor = StackSequentialPasteExecutor(
            permissionService: StackPastePermission(state: .granted),
            pasteboardWriter: writer,
            registerSelfWrite: monitor.registerSelfWrite,
            commandDispatcher: StackPasteDispatcher(results: [true]),
            sessionController: controller,
            scheduleProduction: { $0() },
            finishPresentation: {}
        )

        XCTAssertEqual(controller.acceptNextPasteInput(), .consumeAndDispatch)
        executor.executeReservedPaste()
        monitor.poll()

        XCTAssertEqual(writer.returnedChangeCounts, [11])
        XCTAssertEqual(observed, 0)
    }

    func testReactivatedPasteAlsoRegistersOnlyItsExactSelfWritesWithoutHistoryDuplicate() {
        let pasteboard = StackTestPasteboard(changeCount: 20)
        let controller = configuredController(with: ["reactivation suppression fixture"])
        var observed = 0
        let monitor = PasteboardMonitor(pasteboard: pasteboard) { _ in observed += 1 }
        monitor.start(interval: 3_600)
        defer { monitor.stop() }
        let writer = StackPasteboardWriter(pasteboard: pasteboard)
        let finish = QueuedFinishScheduler()
        let executor = StackSequentialPasteExecutor(
            permissionService: StackPastePermission(state: .granted),
            pasteboardWriter: writer,
            registerSelfWrite: monitor.registerSelfWrite,
            commandDispatcher: StackPasteDispatcher(results: [true, true]),
            sessionController: controller,
            scheduleProduction: { $0() },
            scheduleAutoFinish: finish.schedule,
            finishPresentation: {}
        )
        let occurrenceID = controller.occurrences[0].id

        XCTAssertEqual(controller.acceptNextPasteInput(), .consumeAndDispatch)
        executor.executeReservedPaste()
        monitor.poll()
        XCTAssertTrue(controller.reactivateOccurrence(id: occurrenceID))
        XCTAssertEqual(controller.acceptNextPasteInput(), .consumeAndDispatch)
        executor.executeReservedPaste()
        monitor.poll()

        XCTAssertEqual(writer.returnedChangeCounts, [21, 22])
        XCTAssertEqual(observed, 0)
    }

    func testInputUnavailableReleasesReservationWithoutSkippingAnItem() {
        let controller = configuredController(with: ["one", "two"])
        let firstID = controller.nextOccurrence?.id
        XCTAssertEqual(controller.acceptNextPasteInput(), .consumeAndDispatch)

        controller.recordInputUnavailable()

        XCTAssertEqual(controller.pasteFailure, .inputUnavailable)
        XCTAssertEqual(controller.occurrences.map(\.state), [.pending, .pending])
        XCTAssertEqual(controller.nextOccurrence?.id, firstID)
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

    private func makeSequentialExecutor(
        controller: StackSessionController,
        writer: HistoryPasteboardWriting,
        dispatcher: TaggedPasteCommandDispatching,
        permission: StackPastePermission = StackPastePermission(state: .granted),
        productionSchedule: @escaping (@escaping () -> Void) -> Void = { action in action() },
        finishScheduler: QueuedFinishScheduler = QueuedFinishScheduler(),
        finishPresentation: @escaping () -> Void = {}
    ) -> StackSequentialPasteExecutor {
        StackSequentialPasteExecutor(
            permissionService: permission,
            pasteboardWriter: writer,
            registerSelfWrite: { _ in },
            commandDispatcher: dispatcher,
            sessionController: controller,
            scheduleProduction: productionSchedule,
            scheduleAutoFinish: finishScheduler.schedule,
            finishPresentation: finishPresentation
        )
    }
}

final class FloatingPanelPlacementTests: XCTestCase {
    func testRestoresSavedOriginWhenEntirePanelRemainsVisible() {
        let savedOrigin = NSPoint(x: 1_250, y: 180)

        let origin = FloatingPanelPlacement.restoredOrigin(
            savedOrigin: savedOrigin,
            panelSize: NSSize(width: 400, height: 360),
            availableVisibleFrames: [
                NSRect(x: 0, y: 0, width: 1_000, height: 800),
                NSRect(x: 1_000, y: 0, width: 1_000, height: 800)
            ],
            fallbackVisibleFrame: NSRect(x: 0, y: 0, width: 1_000, height: 800)
        )

        XCTAssertEqual(origin, savedOrigin)
    }

    func testCentersOnFallbackDisplayWhenSavedDisplayIsUnavailable() {
        let origin = FloatingPanelPlacement.restoredOrigin(
            savedOrigin: NSPoint(x: 1_250, y: 180),
            panelSize: NSSize(width: 400, height: 360),
            availableVisibleFrames: [NSRect(x: 0, y: 0, width: 1_000, height: 800)],
            fallbackVisibleFrame: NSRect(x: 0, y: 0, width: 1_000, height: 800)
        )

        XCTAssertEqual(origin, NSPoint(x: 300, y: 220))
    }

    func testCentersInsteadOfRestoringPartiallyOffscreenPanel() {
        let origin = FloatingPanelPlacement.restoredOrigin(
            savedOrigin: NSPoint(x: 850, y: 180),
            panelSize: NSSize(width: 400, height: 360),
            availableVisibleFrames: [NSRect(x: 0, y: 0, width: 1_000, height: 800)],
            fallbackVisibleFrame: NSRect(x: 0, y: 0, width: 1_000, height: 800)
        )

        XCTAssertEqual(origin, NSPoint(x: 300, y: 220))
    }

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

final class PasteStackPanelPositionStoreTests: XCTestCase {
    func testSavedOriginPersistsAcrossStoreInstances() {
        let suiteName = "QipliTests.PasteStackPanelPosition.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let storageKey = "panel-origin"

        PasteStackPanelPositionStore(defaults: defaults, storageKey: storageKey)
            .save(origin: NSPoint(x: -480.5, y: 240.25))

        XCTAssertEqual(
            PasteStackPanelPositionStore(defaults: defaults, storageKey: storageKey).savedOrigin,
            NSPoint(x: -480.5, y: 240.25)
        )
    }

    func testMalformedSavedOriginIsIgnored() {
        let suiteName = "QipliTests.PasteStackPanelPosition.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let storageKey = "panel-origin"
        defaults.set(["not-a-coordinate"], forKey: storageKey)

        XCTAssertNil(
            PasteStackPanelPositionStore(defaults: defaults, storageKey: storageKey).savedOrigin
        )
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

private final class StackPastePermission: AccessibilityPermissionChecking {
    var state: AccessibilityPermissionState

    init(state: AccessibilityPermissionState) {
        self.state = state
    }

    func refresh() -> AccessibilityPermissionState { state }
    func requestAccess() -> AccessibilityPermissionState { state }
    func openSystemSettings() {}
}

private final class StackPasteWriter: HistoryPasteboardWriting {
    var changeCount: Int
    var shouldFail: Bool
    private(set) var texts: [String] = []

    init(changeCount: Int, shouldFail: Bool = false) {
        self.changeCount = changeCount
        self.shouldFail = shouldFail
    }

    func write(text: String) throws -> Int {
        if shouldFail { throw HistoryPasteboardWriteError.unableToWriteText }
        texts.append(text)
        changeCount += 1
        return changeCount
    }
}

private final class StackPasteboardWriter: HistoryPasteboardWriting {
    private let pasteboard: StackTestPasteboard
    private(set) var returnedChangeCounts: [Int] = []

    init(pasteboard: StackTestPasteboard) {
        self.pasteboard = pasteboard
    }

    func write(text: String) throws -> Int {
        pasteboard.setText(text)
        let count = pasteboard.changeCount
        returnedChangeCounts.append(count)
        return count
    }
}

private final class StackPasteDispatcher: TaggedPasteCommandDispatching {
    private var results: [Bool]
    private(set) var dispatchCount = 0

    init(results: [Bool]) {
        self.results = results
    }

    func postTaggedCommandV() -> Bool {
        dispatchCount += 1
        guard !results.isEmpty else { return false }
        return results.removeFirst()
    }
}

private final class QueuedFinishScheduler {
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
