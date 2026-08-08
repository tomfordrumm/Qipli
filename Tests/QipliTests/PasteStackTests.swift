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
        let releasedSession = WeakBox<StackSession>()
        releasedSession.value = controller.session

        controller.cancel()

        XCTAssertNil(releasedSession.value)
        XCTAssertFalse(controller.isActive)
        XCTAssertTrue(controller.occurrences.isEmpty)
        XCTAssertTrue(controller.startIfNeeded(captureAfterChangeCount: 12))
        XCTAssertTrue(controller.occurrences.isEmpty)
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

    private func makeEntry(_ text: String) -> HistoryEntry {
        HistoryEntry(id: UUID(), text: text, activityAt: .now)
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
