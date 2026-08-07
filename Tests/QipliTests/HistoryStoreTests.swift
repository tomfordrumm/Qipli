import Foundation
import XCTest
@testable import Qipli

final class HistoryStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testCreateListAndRestartPreserveExactTextAndDuplicateOccurrences() throws {
        let clock = MutableClock(now: Date(timeIntervalSinceReferenceDate: 8_000_000))
        let store = try makeStore()
        let service = HistoryService(store: store, clock: clock)
        let multiline = ["same", "text"].joined(separator: "\n")
        let first = try service.capture(text: multiline)
        clock.now = clock.now.addingTimeInterval(1)
        let second = try service.capture(text: multiline)

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(try service.entries().map(\.id), [second.id, first.id])
        XCTAssertEqual(try service.entries().map(\.text), [multiline, multiline])

        let restarted = try CoreDataHistoryStore(storeURL: directory.appendingPathComponent("History.sqlite"))
        XCTAssertEqual(try restarted.fetchCurrent(since: clock.now.addingTimeInterval(-HistoryService.retention)).map(\.id), [second.id, first.id])
        restarted.close()
        store.close()
    }

    func testRetentionHidesAndPurgesBoundaryEntries() throws {
        let now = Date(timeIntervalSinceReferenceDate: 9_000_000)
        let clock = MutableClock(now: now)
        let store = try makeStore()
        let service = HistoryService(store: store, clock: clock)
        let cutoff = now.addingTimeInterval(-HistoryService.retention)

        _ = try store.create(text: "old", capturedAt: cutoff.addingTimeInterval(-1))
        _ = try store.create(text: "boundary", capturedAt: cutoff)
        let recent = try store.create(text: "recent", capturedAt: cutoff.addingTimeInterval(1))

        XCTAssertEqual(try service.entries().map(\.id), [recent.id])
        XCTAssertEqual(try store.fetchCurrent(since: cutoff).map(\.id), [recent.id])
        store.close()
    }

    func testDeleteIsDurableAfterRestart() throws {
        let clock = MutableClock(now: Date(timeIntervalSinceReferenceDate: 10_000_000))
        let store = try makeStore()
        let service = HistoryService(store: store, clock: clock)
        let entry = try service.capture(text: "remove only this")
        try service.delete(id: entry.id)

        let restartedAfterDelete = try CoreDataHistoryStore(storeURL: directory.appendingPathComponent("History.sqlite"))
        XCTAssertTrue(try restartedAfterDelete.fetchCurrent(since: clock.now.addingTimeInterval(-HistoryService.retention)).isEmpty)
        restartedAfterDelete.close()
        store.close()

    }

    func testClearAllDestroysManagedStoreAndPersistsAcrossRestart() throws {
        let storeURL = directory.appendingPathComponent("History.sqlite")
        try clearStoreInSeparateLifetime(at: storeURL)

        let restarted = try CoreDataHistoryStore(storeURL: storeURL)
        XCTAssertTrue(try restarted.fetchCurrent(since: Date.distantPast).isEmpty)
        restarted.close()
    }

    func testRetryingStoreRetriesATransientInitialLoadFailure() throws {
        let underlying = try makeStore()
        var attempts = 0
        let retrying = RetryingHistoryStore {
            attempts += 1
            if attempts == 1 { throw HistoryStoreError.unavailable }
            return underlying
        }

        XCTAssertThrowsError(try retrying.fetchCurrent(since: .distantPast))
        XCTAssertTrue(try retrying.fetchCurrent(since: .distantPast).isEmpty)
        XCTAssertEqual(attempts, 2)
        underlying.close()
    }

    private func makeStore() throws -> CoreDataHistoryStore {
        try CoreDataHistoryStore(storeURL: directory.appendingPathComponent("History.sqlite"))
    }

    private func clearStoreInSeparateLifetime(at storeURL: URL) throws {
        let store = try CoreDataHistoryStore(storeURL: storeURL)
        let service = HistoryService(store: store)
        _ = try service.capture(text: "clear all")
        try service.clearAll()
        XCTAssertTrue(try service.entries().isEmpty)
        store.close()
    }
}

private final class MutableClock: HistoryClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}
