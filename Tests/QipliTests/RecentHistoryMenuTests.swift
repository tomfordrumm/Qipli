import AppKit
import XCTest
@testable import Qipli

@MainActor
final class RecentHistoryMenuTests: XCTestCase {
    private func descriptor(_ text: String = "Synthetic preview", offset: Int = 0) -> HistoryOccurrenceDescriptor {
        HistoryOccurrenceDescriptor(id: UUID(), activityAt: Date().addingTimeInterval(Double(offset)),
            textPreview: text, representations: [.init(kind: .text, typeIdentifier: "public.utf8-plain-text")])
    }

    private func menu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for title in ["Open History", "Start Paste Stack", "Settings…", "Quit Qipli"] {
            menu.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: ""))
        }
        return menu
    }

    func testCountsPlacementAndSeparators() {
        for count in [0, 1, 4, 5, 8] {
            let rows = (0..<count).map { descriptor(offset: $0) }
            let controller = RecentHistoryMenuController(snapshot: { rows.isEmpty ? .empty : .list(rows) },
                refresh: {}, captureTarget: { nil }, stackIsActive: { false }, paste: { _, _ in XCTFail() })
            let menu = menu()
            controller.menuWillOpen(menu)
            let expected = min(count, 5)
            XCTAssertEqual(menu.items.filter { $0.representedObject is UUID }.count, expected)
            XCTAssertEqual(menu.items.first?.title, "Open History")
            XCTAssertEqual(menu.items.filter(\.isSeparatorItem).count, count == 0 ? 0 : 2)
            XCTAssertEqual(menu.items[expected + (count == 0 ? 1 : 3)].title, "Start Paste Stack")
            controller.menuWillOpen(menu)
            XCTAssertEqual(menu.items.filter { $0.representedObject is UUID }.count, expected)
        }
    }

    func testSnapshotIdentityAndNextOpening() async {
        let first = descriptor(), second = descriptor()
        var state = HistoryViewState.list([first, second])
        var pasted: [UUID] = []
        let target = RecentMenuTarget()
        let controller = RecentHistoryMenuController(snapshot: { state }, refresh: {}, captureTarget: { target },
            stackIsActive: { false }, paste: { id, captured in
                XCTAssertTrue(captured === target)
                pasted.append(id)
            })
        let menu = menu()
        controller.menuWillOpen(menu)
        let originalItem = menu.items[2]
        state = .list([second, first])
        controller.menuDidClose(menu)
        controller.selectRecent(originalItem)
        controller.selectRecent(originalItem)
        await drainMainQueue()
        XCTAssertEqual(pasted, [first.id])
        controller.menuWillOpen(menu)
        XCTAssertEqual(menu.items[2].representedObject as? UUID, second.id)
        controller.selectRecent(originalItem)
        await drainMainQueue()
        XCTAssertEqual(pasted, [first.id])
    }

    func testDismissWithoutSelectionAndOldCloseCannotClearNewOpening() async {
        let entry = descriptor()
        var pasted: [UUID] = []
        let controller = RecentHistoryMenuController(snapshot: { .list([entry]) }, refresh: {}, captureTarget: { nil },
            stackIsActive: { false }, paste: { id, _ in pasted.append(id) })
        let menu = menu()
        controller.menuWillOpen(menu)
        controller.menuDidClose(menu)
        await drainMainQueue()
        XCTAssertTrue(pasted.isEmpty)
        controller.menuWillOpen(menu)
        controller.menuDidClose(menu)
        controller.menuWillOpen(menu)
        await drainMainQueue()
        controller.selectRecent(menu.items[2])
        await drainMainQueue()
        XCTAssertEqual(pasted, [entry.id])
    }

    func testActiveStackAndLateStackStartBlockSelection() async {
        var active = true
        let controller = RecentHistoryMenuController(snapshot: { .list([self.descriptor()]) }, refresh: {},
            captureTarget: { nil }, stackIsActive: { active }, paste: { _, _ in XCTFail("Stack must not paste") })
        let menu = menu()
        controller.menuWillOpen(menu)
        XCTAssertFalse(menu.items[2].isEnabled)
        XCTAssertTrue(menu.items.contains { $0.title.contains("Finish Paste Stack") })
        controller.selectRecent(menu.items[2])
        active = false
        controller.menuWillOpen(menu)
        controller.selectRecent(menu.items[2])
        active = true
        await drainMainQueue()
    }

    func testLoadingErrorAndEmptyAreDistinct() {
        for state in [HistoryViewState.loading, .error, .empty] {
            let controller = RecentHistoryMenuController(snapshot: { state }, refresh: {}, captureTarget: { nil },
                stackIsActive: { false }, paste: { _, _ in XCTFail() })
            let menu = menu()
            controller.menuWillOpen(menu)
            if state == .empty {
                XCTAssertEqual(menu.items.count, 4)
            } else {
                XCTAssertFalse(menu.items[2].isEnabled)
                XCTAssertTrue(menu.items[2].title.contains(state == .loading ? "Loading" : "unavailable"))
            }
        }
    }

    func testBoundedSingleLineAndTypedFallbacks() {
        let original = descriptor("Synthetic\n\t" + String(repeating: "long ", count: 200))
        let row = RecentHistoryMenuRow(original)
        XCTAssertLessThanOrEqual(row.title.count, 65)
        XCTAssertFalse(row.title.contains("\n"))
        XCTAssertTrue(row.title.hasSuffix("…"))
        XCTAssertTrue(original.textPreview!.contains("\n"))
        for kind in [HistoryRepresentationKind.url, .inlineImage, .fileReference, .videoReference] {
            let typed = HistoryOccurrenceDescriptor(id: UUID(), activityAt: Date(), textPreview: nil,
                representations: [.init(kind: kind, typeIdentifier: "synthetic")])
            XCTAssertFalse(RecentHistoryMenuRow(typed).title.isEmpty)
            XCTAssertFalse(RecentHistoryMenuRow(typed).symbol.isEmpty)
        }
    }

    func testRecentProjectionIgnoresFiltersAndTracksMutations() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try CoreDataHistoryStore(storeURL: root.appendingPathComponent("History.sqlite"))
        let model = HistoryViewModel(service: HistoryService(store: store))
        var ids: [UUID] = []
        for index in 0..<7 {
            let entry = await model.recordExternalText("Synthetic recent \(index)")
            ids.append(try XCTUnwrap(entry).id)
        }
        func recentIDs() -> [UUID] {
            if case let .list(rows) = model.recentState { return rows.map(\.id) }
            return []
        }
        XCTAssertEqual(recentIDs(), Array(ids.reversed().prefix(5)))
        model.updateQuery("no synthetic match")
        await model.waitForPendingSearch()
        model.switchMode(to: .favorites)
        await model.waitForPendingSearch()
        XCTAssertEqual(recentIDs(), Array(ids.reversed().prefix(5)))
        await model.markUsedAfterSuccessfulPaste(id: ids[0])
        XCTAssertEqual(recentIDs().first, ids[0])
        await model.delete(id: ids[0])
        XCTAssertFalse(recentIDs().contains(ids[0]))
        let cleared = await model.clearAll()
        XCTAssertTrue(cleared)
        XCTAssertEqual(model.recentState, .empty)
        let missing = await model.entryForPaste(id: ids[0])
        if case .failure(.entryUnavailable) = missing {} else { XCTFail("Deleted UUID must fail") }
    }

    func testRetentionAndEqualTimestampUUIDOrder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try CoreDataHistoryStore(storeURL: root.appendingPathComponent("History.sqlite"))
        let now = Date()
        _ = try store.create(text: "Synthetic expired", activityAt: now.addingTimeInterval(-HistoryService.retention - 60))
        let rows = try (0..<7).map { _ in try store.create(text: "Synthetic identical", activityAt: now) }
        let recent = try HistoryService(store: store).recentDescriptors()
        XCTAssertEqual(recent.map(\.id), Array(rows.map(\.id).sorted { $0.uuidString > $1.uuidString }.prefix(5)))
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}

private final class RecentMenuTarget: HistoryPasteTarget {
    var isTerminated = false
    var isActive = true
    func activate() -> Bool { true }
}
