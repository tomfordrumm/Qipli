import CoreData
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
        let first = try XCTUnwrap(service.capture(text: multiline))
        clock.now = clock.now.addingTimeInterval(1)
        let second = try XCTUnwrap(service.capture(text: multiline))

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(try service.entries().map(\.id), [second.id, first.id])
        XCTAssertEqual(try service.entries().map(\.text), [multiline, multiline])

        let restarted = try CoreDataHistoryStore(storeURL: directory.appendingPathComponent("History.sqlite"))
        XCTAssertEqual(try restarted.fetchCurrent(since: clock.now.addingTimeInterval(-HistoryService.retention)).map(\.id), [second.id, first.id])
        restarted.close()
        store.close()
    }

    func testWhitespaceOnlyTextIsIgnoredAndExistingBlankEntriesStayHidden() throws {
        let clock = MutableClock(now: Date(timeIntervalSinceReferenceDate: 8_250_000))
        let store = try makeStore()
        let service = HistoryService(store: store, clock: clock)

        for blankText in ["", "   ", "\t\r\n"] {
            XCTAssertNil(try service.capture(text: blankText))
        }
        _ = try store.create(text: "\n", activityAt: clock.now)

        let meaningfulText = " \nvisible text\t "
        let meaningfulEntry = try XCTUnwrap(service.capture(text: meaningfulText))

        XCTAssertEqual(meaningfulEntry.text, meaningfulText)
        XCTAssertEqual(try service.entries(), [meaningfulEntry])
        store.close()
    }

    func testExistingCapturedAtSchemaStoreRemainsReadableWithoutMigration() throws {
        let storeURL = directory.appendingPathComponent("History.sqlite")
        let id = UUID()
        let activityAt = Date(timeIntervalSinceReferenceDate: 8_500_000)
        try writeLegacyCapturedAtStore(
            at: storeURL,
            id: id,
            text: "legacy occurrence",
            activityAt: activityAt
        )

        let upgradedDomainStore = try CoreDataHistoryStore(storeURL: storeURL)
        let entries = try upgradedDomainStore.fetchCurrent(since: .distantPast)

        XCTAssertEqual(entries, [HistoryEntry(id: id, text: "legacy occurrence", activityAt: activityAt)])
        upgradedDomainStore.close()
    }

    func testRetentionHidesAndPurgesBoundaryEntries() throws {
        let now = Date(timeIntervalSinceReferenceDate: 9_000_000)
        let clock = MutableClock(now: now)
        let store = try makeStore()
        let service = HistoryService(store: store, clock: clock)
        let cutoff = now.addingTimeInterval(-HistoryService.retention)

        _ = try store.create(text: "old", activityAt: cutoff.addingTimeInterval(-1))
        _ = try store.create(text: "boundary", activityAt: cutoff)
        let recent = try store.create(text: "recent", activityAt: cutoff.addingTimeInterval(1))

        XCTAssertEqual(try service.entries().map(\.id), [recent.id])
        XCTAssertEqual(try store.fetchCurrent(since: cutoff).map(\.id), [recent.id])
        store.close()
    }

    func testMarkUsedPromotesExactOccurrenceAndPersistsAcrossRestart() throws {
        let clock = MutableClock(now: Date(timeIntervalSinceReferenceDate: 9_500_000))
        let store = try makeStore()
        let service = HistoryService(store: store, clock: clock)
        let first = try XCTUnwrap(service.capture(text: "same occurrence text"))
        clock.now = clock.now.addingTimeInterval(1)
        let second = try XCTUnwrap(service.capture(text: "same occurrence text"))
        clock.now = clock.now.addingTimeInterval(1)

        try service.markUsed(id: first.id)

        let promoted = try service.entries()
        XCTAssertEqual(promoted.map(\.id), [first.id, second.id])
        XCTAssertEqual(promoted.map(\.text), ["same occurrence text", "same occurrence text"])
        XCTAssertEqual(promoted.first?.activityAt, clock.now)
        XCTAssertEqual(promoted.count, 2)

        let restarted = try CoreDataHistoryStore(storeURL: directory.appendingPathComponent("History.sqlite"))
        let afterRestart = try restarted.fetchCurrent(since: clock.now.addingTimeInterval(-HistoryService.retention))
        XCTAssertEqual(afterRestart.map(\.id), [first.id, second.id])
        XCTAssertEqual(afterRestart.first?.activityAt, clock.now)
        XCTAssertEqual(afterRestart.count, 2)
        restarted.close()
        store.close()
    }

    func testSuccessfulUseExtendsRetentionFromActivityTime() throws {
        let clock = MutableClock(now: Date(timeIntervalSinceReferenceDate: 9_750_000))
        let store = try makeStore()
        let service = HistoryService(store: store, clock: clock)
        let old = try store.create(
            text: "old occurrence",
            activityAt: clock.now.addingTimeInterval(-HistoryService.retention - 1)
        )

        try service.markUsed(id: old.id)
        XCTAssertEqual(try service.entries().map(\.id), [old.id])

        clock.now = clock.now.addingTimeInterval(HistoryService.retention)
        XCTAssertTrue(try service.entries().isEmpty)
        store.close()
    }

    func testDeleteIsDurableAfterRestart() throws {
        let clock = MutableClock(now: Date(timeIntervalSinceReferenceDate: 10_000_000))
        let store = try makeStore()
        let service = HistoryService(store: store, clock: clock)
        let entry = try XCTUnwrap(service.capture(text: "remove only this"))
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

        let initialActivity = Date(timeIntervalSinceReferenceDate: 11_000_000)
        let usedActivity = initialActivity.addingTimeInterval(1)
        let entry = try retrying.create(text: "retrying occurrence", activityAt: initialActivity)
        try retrying.markUsed(id: entry.id, activityAt: usedActivity)
        XCTAssertEqual(try retrying.fetchCurrent(since: .distantPast).first?.activityAt, usedActivity)
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

    private func writeLegacyCapturedAtStore(
        at storeURL: URL,
        id: UUID,
        text: String,
        activityAt: Date
    ) throws {
        let model = NSManagedObjectModel()
        let entry = NSEntityDescription()
        entry.name = "HistoryEntry"
        entry.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        let idAttribute = NSAttributeDescription()
        idAttribute.name = "id"
        idAttribute.attributeType = .UUIDAttributeType
        idAttribute.isOptional = false

        let textAttribute = NSAttributeDescription()
        textAttribute.name = "text"
        textAttribute.attributeType = .stringAttributeType
        textAttribute.isOptional = false

        let capturedAtAttribute = NSAttributeDescription()
        capturedAtAttribute.name = "capturedAt"
        capturedAtAttribute.attributeType = .dateAttributeType
        capturedAtAttribute.isOptional = false

        entry.properties = [idAttribute, textAttribute, capturedAtAttribute]
        entry.indexes = [NSFetchIndexDescription(
            name: "capturedAtIndex",
            elements: [NSFetchIndexElementDescription(property: capturedAtAttribute, collationType: .binary)]
        )]
        model.entities = [entry]

        let container = NSPersistentContainer(name: "QipliHistory", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: storeURL)
        description.type = NSSQLiteStoreType
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError { throw loadError }

        try container.viewContext.performAndWait {
            let object = NSEntityDescription.insertNewObject(forEntityName: "HistoryEntry", into: container.viewContext)
            object.setValue(id, forKey: "id")
            object.setValue(text, forKey: "text")
            object.setValue(activityAt, forKey: "capturedAt")
            try container.viewContext.save()
        }
        for persistentStore in container.persistentStoreCoordinator.persistentStores {
            try container.persistentStoreCoordinator.remove(persistentStore)
        }
    }
}

private final class MutableClock: HistoryClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}
