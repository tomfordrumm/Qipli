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

    func testSearchBaselineWorkloadsPreserveLocalizedSubstringSemantics() {
        let probe = RecordingPerformanceProbe()
        var inspectionCounts: [Int] = []

        for size in [1_800, 10_000, 50_000] {
            let entries = SyntheticPerformanceFixtures.historyEntries(count: size)
            var inspectedEntries = 0
            let matches = probe.probe.measure(.historySearch, itemCount: size) {
                HistorySearchMatcher.matches(
                    in: entries,
                    query: "NÉEDLE",
                    didInspect: { inspectedEntries += 1 }
                )
            }

            XCTAssertEqual(matches.count, SyntheticPerformanceFixtures.expectedNeedleCount(in: size))
            inspectionCounts.append(inspectedEntries)
        }

        XCTAssertEqual(inspectionCounts, [1_800, 10_000, 50_000])
        XCTAssertEqual(probe.observations.map(\.operation), Array(repeating: .historySearch, count: 3))
        XCTAssertEqual(probe.observations.map(\.itemCount), [1_800, 10_000, 50_000])
        XCTAssertTrue(probe.observations.allSatisfy { $0.elapsedNanoseconds > 0 })
    }

    func testHistoryFetchBaselineUsesAggregateEntryCount() throws {
        let entries = SyntheticPerformanceFixtures.historyEntries(count: 1_800)
        let store = BaselineHistoryStore(entries: entries)
        let probe = RecordingPerformanceProbe()

        let fetched = try probe.probe.measure(.historyFetch, itemCount: entries.count) {
            try store.fetchCurrent(since: .distantPast)
        }

        XCTAssertEqual(fetched, entries)
        XCTAssertEqual(probe.observations.single?.operation, .historyFetch)
        XCTAssertEqual(probe.observations.single?.itemCount, 1_800)
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

private final class BaselineHistoryStore: HistoryStoring {
    private let entries: [HistoryEntry]

    init(entries: [HistoryEntry]) {
        self.entries = entries
    }

    func fetchCurrent(since cutoff: Date) throws -> [HistoryEntry] { entries }
    func create(text: String, activityAt: Date) throws -> HistoryEntry {
        HistoryEntry(id: UUID(), text: text, activityAt: activityAt)
    }
    func markUsed(id: UUID, activityAt: Date) throws {}
    func delete(id: UUID) throws {}
    func clearAll() throws {}
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
