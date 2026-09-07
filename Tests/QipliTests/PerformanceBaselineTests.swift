import Combine
import Foundation
import XCTest
@testable import Qipli

final class PerformanceBaselineTests: XCTestCase {
    func testProbeRecordsOnlyBoundedAggregateDimensions() {
        var ticks: [UInt64] = [100, 145]
        var observations: [PerformanceObservation] = []
        let probe = PerformanceProbe(
            clock: { ticks.removeFirst() },
            recorder: { observations.append($0) }
        )

        let value = probe.measure(.historySearch, itemCount: 10_000) { 42 }

        XCTAssertEqual(value, 42)
        XCTAssertEqual(observations, [PerformanceObservation(
            operation: .historySearch,
            itemCount: 10_000,
            elapsedNanoseconds: 45
        )])
        XCTAssertEqual(PerformanceOperation.allCases.map(\.rawValue), [
            "historyFetch",
            "historySearch",
            "previewConstruction",
            "stackTraversal",
            "pasteboardPoll",
        ])
    }

    func testSyntheticHistoryFixturesAreDeterministicAndPayloadFree() {
        let first = SyntheticPerformanceFixtures.historyEntries(count: 1_800)
        let second = SyntheticPerformanceFixtures.historyEntries(count: 1_800)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 1_800)
        XCTAssertTrue(first.allSatisfy { $0.text.hasPrefix("fixture-") })
        XCTAssertEqual(Set(first.map(\.id)).count, first.count)
    }

    func testProductionSearchScansEachCandidateOnceAndPagesKeepExactPayloadOutsideDisplay() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var inspected = 0
        let store = try CoreDataHistoryStore(storeURL: root.appendingPathComponent("History.sqlite"), onSearchBatch: { inspected += $0 })
        defer { store.close() }
        let entries = SyntheticPerformanceFixtures.historyEntries(count: 10_000)
        for entry in entries { _ = try store.create(text: entry.text, activityAt: entry.activityAt) }
        let probe = RecordingPerformanceProbe()
        let missing = try probe.probe.measure(.historySearch, itemCount: entries.count) {
            try store.searchPage(query: "not-in-any-fixture", since: .distantPast, after: nil, limit: 500)
        }
        XCTAssertTrue(missing.descriptors.isEmpty)
        XCTAssertEqual(inspected, 10_000)
        inspected = 0
        let matches = try store.searchPage(query: "NÉEDLE", since: .distantPast, after: nil, limit: 500)
        XCTAssertEqual(matches.descriptors.count, SyntheticPerformanceFixtures.expectedNeedleCount(in: entries.count))
        XCTAssertEqual(inspected, 10_000)
        let page = try probe.probe.measure(.historyFetch, itemCount: entries.count) {
            try store.fetchPage(since: .distantPast, after: nil, limit: 500)
        }
        XCTAssertEqual(page.descriptors.count, 500)
        XCTAssertTrue(page.hasMore)
        XCTAssertTrue(page.descriptors.allSatisfy { ($0.textPreview?.count ?? 0) <= HistoryPreview.maximumCharacters + 1 })
        XCTAssertEqual(probe.observations.map(\.operation), [.historySearch, .historyFetch])
    }

    func testCancelledProductionSearchStopsBeforeReadingTheNextBatch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let started = expectation(description: "first batch")
        let release = DispatchSemaphore(value: 0)
        var inspected = 0
        let store = try CoreDataHistoryStore(storeURL: root.appendingPathComponent("History.sqlite"), onSearchBatch: { count in
            inspected += count
            started.fulfill()
            release.wait()
        })
        defer { store.close() }
        for entry in SyntheticPerformanceFixtures.historyEntries(count: 600) {
            _ = try store.create(text: entry.text, activityAt: entry.activityAt)
        }
        let search = Task.detached {
            try store.searchPage(query: "missing", since: .distantPast, after: nil, limit: 500)
        }
        await fulfillment(of: [started], timeout: 5)
        search.cancel()
        release.signal()
        do {
            _ = try await search.value
            XCTFail("Cancelled storage work must throw rather than finish the scan")
        } catch is CancellationError { }
        XCTAssertEqual(inspected, 256)
    }

    func testThumbnailCacheEvictsLeastRecentlyUsedAndNeverExceedsBudget() {
        let first = UUID(), second = UUID(), third = UUID()
        var cache = HistoryThumbnailCache(byteLimit: 8)
        cache.insert(Data(repeating: 1, count: 4), for: first)
        cache.insert(Data(repeating: 2, count: 4), for: second)
        XCTAssertNotNil(cache.value(for: first))
        XCTAssertEqual(cache.insert(Data(repeating: 3, count: 4), for: third), [second])
        XCTAssertNotNil(cache.value(for: first))
        XCTAssertNil(cache.value(for: second))
        XCTAssertEqual(cache.byteCount, 8)
        cache.insert(Data(repeating: 4, count: 9), for: UUID())
        XCTAssertEqual(cache.byteCount, 8)
        cache.removeAll()
        XCTAssertEqual(cache.byteCount, 0)
        XCTAssertTrue(cache.values.isEmpty)
    }

    func testPreviewBaselineKeepsExactOccurrenceTextOutsideDisplayValue() {
        let fixtureCharacterCount = 50_000
        let fullText = SyntheticPerformanceFixtures.longText(characterCount: fixtureCharacterCount)
        let occurrence = StackOccurrence(
            id: SyntheticPerformanceFixtures.uuid(index: 1),
            historyEntryID: SyntheticPerformanceFixtures.uuid(index: 2),
            text: fullText,
            position: 0
        )
        let probe = RecordingPerformanceProbe()

        let preview = probe.probe.measure(.previewConstruction, itemCount: fixtureCharacterCount) {
            StackPreview.text(for: occurrence.text)
        }

        XCTAssertEqual(occurrence.text, fullText)
        XCTAssertEqual(preview.count, StackPreview.maximumCharacters + 1)
        XCTAssertTrue(preview.hasSuffix("…"))
        XCTAssertEqual(probe.observations.single?.operation, .previewConstruction)
    }

    func testStackTraversalBaselineReturnsExactOccurrenceAtLargeSize() {
        let session = StackSession(captureAfterChangeCount: 0)
        let entries = SyntheticPerformanceFixtures.historyEntries(count: 10_000)
        for entry in entries {
            session.append(historyEntry: entry)
        }
        let probe = RecordingPerformanceProbe()

        let direct = probe.probe.measure(.stackTraversal, itemCount: session.occurrences.count) {
            session.nextOccurrence
        }
        XCTAssertEqual(direct?.historyEntryID, entries.first?.id)

        XCTAssertTrue(session.setTraversalDirection(.reverse))
        let reverse = probe.probe.measure(.stackTraversal, itemCount: session.occurrences.count) {
            session.nextOccurrence
        }
        XCTAssertEqual(reverse?.historyEntryID, entries.last?.id)
        XCTAssertEqual(probe.observations.map(\.itemCount), [10_000, 10_000])
    }

    func testStackNextResolverUsesAtMostOneLinearTraversalWithPriorityFallback() {
        let entries = SyntheticPerformanceFixtures.historyEntries(count: 10_000)
        let occurrences = entries.enumerated().map { index, entry in
            StackOccurrence(
                id: SyntheticPerformanceFixtures.uuid(index: index + 20_000),
                historyEntryID: entry.id,
                text: entry.text,
                position: index,
                state: index == entries.indices.last ? .pending : .used
            )
        }
        var visits = 0

        let directIndex = StackNextOccurrenceResolver.index(
            in: occurrences,
            direction: .direct,
            reactivationPriorityID: nil,
            didInspect: { visits += 1 }
        )

        XCTAssertEqual(directIndex, occurrences.indices.last)
        XCTAssertEqual(visits, occurrences.count)

        visits = 0
        let reverseIndex = StackNextOccurrenceResolver.index(
            in: occurrences,
            direction: .reverse,
            reactivationPriorityID: occurrences.first?.id,
            didInspect: { visits += 1 }
        )

        XCTAssertEqual(reverseIndex, occurrences.indices.first)
        XCTAssertEqual(visits, occurrences.count)
    }

    @MainActor
    func testStackRenderSnapshotResolvesNextIDOnceForEveryRow() {
        var traversalVisits = 0
        let controller = StackSessionController(onNextTraversalVisit: { traversalVisits += 1 })
        XCTAssertTrue(controller.startIfNeeded(captureAfterChangeCount: 0))
        let context = controller.captureContext
        for (offset, entry) in SyntheticPerformanceFixtures.historyEntries(count: 10_000).enumerated() {
            controller.appendPersistedHistoryEntry(
                entry,
                observedChangeCount: offset + 1,
                for: context
            )
        }

        traversalVisits = 0
        XCTAssertTrue(controller.setTraversalDirection(.reverse))
        let preparedNextID = controller.nextOccurrenceID
        let matchingRows = controller.occurrences.reduce(into: 0) { count, occurrence in
            if occurrence.id == preparedNextID { count += 1 }
        }

        XCTAssertEqual(matchingRows, 1)
        XCTAssertEqual(traversalVisits, 1)
    }

    @MainActor
    func testStackAppendKeepsOneSessionCollectionAndOnePublicationPerOccurrence() {
        var traversalVisits = 0
        let controller = StackSessionController(onNextTraversalVisit: { traversalVisits += 1 })
        XCTAssertTrue(controller.startIfNeeded(captureAfterChangeCount: 0))
        let context = controller.captureContext
        var publicationCount = 0
        let observation = controller.objectWillChange.sink { _ in publicationCount += 1 }
        defer { observation.cancel() }

        for (offset, entry) in SyntheticPerformanceFixtures.historyEntries(count: 10_000).enumerated() {
            controller.appendPersistedHistoryEntry(
                entry,
                observedChangeCount: offset + 1,
                for: context
            )
        }

        XCTAssertEqual(controller.occurrences.count, 10_000)
        XCTAssertEqual(controller.session?.occurrencesRevision, 10_000)
        XCTAssertEqual(traversalVisits, 10_000)
        XCTAssertEqual(publicationCount, 10_000)
    }

    @MainActor
    func testUnchangedPasteboardPollingBaselineDoesNotReadTextPayload() {
        let pasteboard = BaselinePasteboard(changeCount: 7)
        let scheduler = BaselinePollScheduler()
        let monitor = PasteboardMonitor(pasteboard: pasteboard, scheduler: scheduler) { _ in
            XCTFail("An unchanged pasteboard must not enter capture.")
        }
        monitor.start()
        defer { monitor.stop() }
        let probe = RecordingPerformanceProbe()

        probe.probe.measure(.pasteboardPoll, itemCount: 10_000) {
            for _ in 0..<10_000 {
                scheduler.fire()
            }
        }

        XCTAssertEqual(scheduler.scheduleCount, 1)
        XCTAssertEqual(scheduler.interval, PasteboardMonitor.productionInterval)
        XCTAssertEqual(scheduler.tolerance, PasteboardMonitor.productionTolerance)
        XCTAssertEqual(pasteboard.changeCountReadCount, 10_001)
        XCTAssertEqual(pasteboard.textValueReadCount, 0)
        XCTAssertEqual(probe.observations.single?.operation, .pasteboardPoll)
    }
}

private enum SyntheticPerformanceFixtures {
    private static let baseDate = Date(timeIntervalSinceReferenceDate: 800_000_000)

    static func historyEntries(count: Int) -> [HistoryEntry] {
        (0..<count).map { index in
            let marker = index.isMultiple(of: 997) ? " néeDle " : " filler "
            return HistoryEntry(
                id: uuid(index: index),
                text: "fixture-\(index)\(marker)\(String(repeating: "x", count: index % 31))",
                activityAt: baseDate.addingTimeInterval(TimeInterval(-index))
            )
        }
    }

    static func expectedNeedleCount(in count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((count - 1) / 997) + 1
    }

    static func longText(characterCount: Int) -> String {
        String(repeating: "λ", count: max(0, characterCount))
    }

    static func uuid(index: Int) -> UUID {
        let value = UInt32(truncatingIfNeeded: index)
        return UUID(uuid: (
            0x51, 0x49, 0x50, 0x4c,
            UInt8(truncatingIfNeeded: value >> 24),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value),
            0x50, 0x45, 0x52, 0x46, 0x54, 0x45, 0x53, 0x54
        ))
    }
}

private final class RecordingPerformanceProbe {
    private(set) var observations: [PerformanceObservation] = []

    lazy var probe = PerformanceProbe(recorder: { [weak self] observation in
        self?.observations.append(observation)
    })
}

private final class BaselinePasteboard: PasteboardReading {
    private let storedChangeCount: Int
    private(set) var changeCountReadCount = 0
    private(set) var textValueReadCount = 0

    init(changeCount: Int) {
        storedChangeCount = changeCount
    }

    var changeCount: Int {
        changeCountReadCount += 1
        return storedChangeCount
    }

    func textValue() -> String? {
        textValueReadCount += 1
        return nil
    }
}

@MainActor
private final class BaselinePollScheduler: PasteboardPollScheduling {
    private var action: (@MainActor () -> Void)?
    private(set) var scheduleCount = 0
    private(set) var interval: TimeInterval?
    private(set) var tolerance: TimeInterval?

    func schedule(
        interval: TimeInterval,
        tolerance: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> PasteboardPollCancellation {
        scheduleCount += 1
        self.interval = interval
        self.tolerance = tolerance
        self.action = action
        return BaselinePollCancellation { [weak self] in self?.action = nil }
    }

    func fire() {
        action?()
    }
}

@MainActor
private final class BaselinePollCancellation: PasteboardPollCancellation {
    private var action: (@MainActor () -> Void)?

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    func cancel() {
        action?()
        action = nil
    }
}

private extension Array {
    var single: Element? { count == 1 ? first : nil }
}
