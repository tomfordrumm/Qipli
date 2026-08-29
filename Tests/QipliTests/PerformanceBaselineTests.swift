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

        for size in [1_800, 10_000, 50_000] {
            let entries = SyntheticPerformanceFixtures.historyEntries(count: size)
            let matches = probe.probe.measure(.historySearch, itemCount: size) {
                entries.filter { $0.text.localizedCaseInsensitiveContains("NÉEDLE") }
            }

            XCTAssertEqual(matches.count, SyntheticPerformanceFixtures.expectedNeedleCount(in: size))
        }

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

    @MainActor
    func testUnchangedPasteboardPollingBaselineDoesNotReadTextPayload() {
        let pasteboard = BaselinePasteboard(changeCount: 7)
        let monitor = PasteboardMonitor(pasteboard: pasteboard) { _ in
            XCTFail("An unchanged pasteboard must not enter capture.")
        }
        monitor.start(interval: 3_600)
        defer { monitor.stop() }
        let probe = RecordingPerformanceProbe()

        probe.probe.measure(.pasteboardPoll, itemCount: 10_000) {
            for _ in 0..<10_000 {
                monitor.poll()
            }
        }

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
    let changeCount: Int
    private(set) var textValueReadCount = 0

    init(changeCount: Int) {
        self.changeCount = changeCount
    }

    func textValue() -> String? {
        textValueReadCount += 1
        return nil
    }
}

private extension Array {
    var single: Element? { count == 1 ? first : nil }
}
