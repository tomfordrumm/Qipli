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

    func testExistingCapturedAtSchemaStoreMigratesWithoutDataLossAndCreatesQueryIndexes() throws {
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

        let exactIDPlan = try sqliteOutput(
            database: storeURL,
            sql: "EXPLAIN QUERY PLAN SELECT Z_PK FROM ZHISTORYENTRY WHERE ZID = X'00000000000000000000000000000000';"
        )
        let orderedPlan = try sqliteOutput(
            database: storeURL,
            sql: "EXPLAIN QUERY PLAN SELECT Z_PK FROM ZHISTORYENTRY ORDER BY ZCAPTUREDAT DESC, ZID DESC;"
        )
        XCTAssertTrue(exactIDPlan.contains("USING COVERING INDEX") || exactIDPlan.contains("USING INDEX"), exactIDPlan)
        XCTAssertFalse(exactIDPlan.contains("SCAN ZHISTORYENTRY"), exactIDPlan)
        XCTAssertTrue(orderedPlan.contains("USING COVERING INDEX") || orderedPlan.contains("USING INDEX"), orderedPlan)
        XCTAssertFalse(orderedPlan.contains("USE TEMP B-TREE"), orderedPlan)

        let occurrence = try XCTUnwrap(upgradedDomainStore.fetchOccurrence(id: id))
        XCTAssertEqual(occurrence.id, id)
        XCTAssertEqual(occurrence.items.count, 1)
        XCTAssertEqual(occurrence.items[0].order, 0)
        XCTAssertEqual(occurrence.items[0].representations[0].kind, .text)
        upgradedDomainStore.close()
    }

    func testTypedHistoryPagesUseBoundedKeysetCursorWithoutDuplicates() throws {
        let store = try makeStore()
        let clock = MutableClock(now: Date(timeIntervalSinceReferenceDate: 8_750_000))
        let service = HistoryService(store: store, clock: clock)
        var expectedIDs = Set<UUID>()
        for index in 0..<1_001 {
            expectedIDs.insert(try XCTUnwrap(service.capture(text: "page entry \(index)")).id)
        }

        var cursor: HistoryPageCursor?
        var observedIDs = [UUID]()
        var pageCount = 0
        var hasMore = true
        while hasMore {
            let page = try store.fetchPage(
                since: Date(timeIntervalSinceReferenceDate: 8_750_000 - 1),
                after: cursor,
                limit: 500
            )
            pageCount += 1
            XCTAssertLessThanOrEqual(page.descriptors.count, 500)
            observedIDs.append(contentsOf: page.descriptors.map(\.id))
            cursor = page.nextCursor
            hasMore = page.hasMore
        }

        XCTAssertEqual(pageCount, 3)
        XCTAssertEqual(observedIDs.count, expectedIDs.count)
        XCTAssertEqual(Set(observedIDs), expectedIDs)
        XCTAssertEqual(observedIDs.count, Set(observedIDs).count)
        XCTAssertNil(try store.fetchPage(
            since: Date(timeIntervalSinceReferenceDate: 8_750_000 - 1),
            after: cursor,
            limit: 500
        ).nextCursor)
        store.close()
    }

    func testDatabaseSearchPagesFullRetentionAndPreservesLocalizedText() throws {
        let store = try makeStore()
        let clock = MutableClock(now: Date(timeIntervalSinceReferenceDate: 8_900_000))
        let service = HistoryService(store: store, clock: clock)
        for index in 0..<501 {
            clock.now = Date(timeIntervalSinceReferenceDate: 8_900_000 + TimeInterval(index))
            _ = try service.capture(text: "Ä MATCH entry \(index)")
        }
        _ = try service.capture(text: "not relevant")

        let first = try store.searchPage(
            query: "ä match",
            since: Date(timeIntervalSinceReferenceDate: 8_900_000 - 1),
            after: nil,
            limit: 500
        )
        XCTAssertEqual(first.descriptors.count, 500)
        XCTAssertTrue(first.hasMore)
        XCTAssertTrue(first.descriptors.allSatisfy { $0.textPreview?.localizedCaseInsensitiveContains("ä match") == true })

        let second = try store.searchPage(
            query: "ä match",
            since: Date(timeIntervalSinceReferenceDate: 8_900_000 - 1),
            after: first.nextCursor,
            limit: 500
        )
        XCTAssertEqual(second.descriptors.count, 1)
        XCTAssertFalse(second.hasMore)
        XCTAssertEqual(Set(first.descriptors.map(\.id)).intersection(second.descriptors.map(\.id)).count, 0)
        store.close()
    }

    func testDatabaseSearchMatchesComposedAndDecomposedUnicodeText() throws {
        let store = try makeStore()
        let clock = MutableClock(now: Date(timeIntervalSinceReferenceDate: 8_950_000))
        let service = HistoryService(store: store, clock: clock)
        let decomposed = "e\u{301}clair"
        let entry = try XCTUnwrap(service.capture(text: decomposed))

        let page = try store.searchPage(
            query: "éCLAIR",
            since: Date(timeIntervalSinceReferenceDate: 8_950_000 - 1),
            after: nil,
            limit: 500
        )

        XCTAssertEqual(page.descriptors.map(\.id), [entry.id])
        store.close()
    }

    func testDatabaseSearchMatchesTheLocalizedMatcherForUnicodeFixtures() throws {
        let store = try makeStore()
        let clock = MutableClock(now: Date(timeIntervalSinceReferenceDate: 8_975_000))
        let service = HistoryService(store: store, clock: clock)
        let fixtures = ["ä", "a", "İstanbul", "istanbul", "Καφές", "καφε"]
        let entries = try fixtures.map { try XCTUnwrap(service.capture(text: $0)) }

        for query in ["ä", "a", "i", "İ", "καφε", "Καφές"] {
            let expected = entries
                .filter { $0.text.localizedCaseInsensitiveContains(query) }
                .sorted {
                    if $0.activityAt != $1.activityAt { return $0.activityAt > $1.activityAt }
                    return $0.id.uuidString > $1.id.uuidString
                }
                .map(\.id)
            let actual = try store.searchPage(
                query: query,
                since: Date(timeIntervalSinceReferenceDate: 8_975_000 - 1),
                after: nil,
                limit: 500
            ).textEntries.map(\.id)
            XCTAssertEqual(actual, expected, "query=\(query)")
        }
        store.close()
    }

    func testPagedDescriptorsHideLegacyBlankRowsAndBoundDisplayText() throws {
        let store = try makeStore()
        let clock = MutableClock(now: Date(timeIntervalSinceReferenceDate: 8_985_000))
        let service = HistoryService(store: store, clock: clock)
        _ = try store.create(text: " \n\t", activityAt: clock.now)
        let marker = "needle after the preview boundary"
        let longText = String(repeating: "🦊", count: HistoryPreview.maximumCharacters + 10) + marker
        let entry = try XCTUnwrap(service.capture(text: longText))

        let page = try store.fetchPage(
            since: Date(timeIntervalSinceReferenceDate: 8_985_000 - 1),
            after: nil,
            limit: 500
        )

        XCTAssertEqual(page.textEntries.map(\.id), [entry.id])
        XCTAssertFalse(page.descriptors[0].textPreview?.contains(marker) == true)
        XCTAssertEqual(page.textEntries[0].text, longText)
        store.close()
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

    func testRetentionBatchDeletesLargeExpiredSetWithoutChangingRecentOrdering() throws {
        let now = Date(timeIntervalSinceReferenceDate: 9_250_000)
        let cutoff = now.addingTimeInterval(-HistoryService.retention)
        let store = try makeStore()
        for index in 0..<1_000 {
            _ = try store.create(
                text: "synthetic-expired-\(index)",
                activityAt: cutoff.addingTimeInterval(TimeInterval(-index))
            )
        }
        let first = try store.create(text: "synthetic-recent-first", activityAt: cutoff.addingTimeInterval(1))
        let second = try store.create(text: "synthetic-recent-second", activityAt: cutoff.addingTimeInterval(2))

        XCTAssertEqual(try store.fetchCurrent(since: cutoff).map(\.id), [second.id, first.id])
        XCTAssertEqual(try store.fetchCurrent(since: .distantPast).count, 2)
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

    private func sqliteOutput(database: URL, sql: String) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", database.path, sql]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "HistoryStoreTests.sqlite3",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: text]
            )
        }
        return text
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

@MainActor
final class HistoryViewModelPagingTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testReloadAndLoadMoreKeepViewModelBoundedToRequestedPages() async throws {
        let store = try CoreDataHistoryStore(storeURL: directory.appendingPathComponent("History.sqlite"))
        let service = HistoryService(store: store)
        for index in 0..<501 {
            _ = try service.capture(text: "bounded entry \(index)")
        }

        let viewModel = HistoryViewModel(service: service)
        await viewModel.reload(selectFirstResult: true)
        XCTAssertEqual(viewModel.visibleEntries.count, 500)

        await viewModel.loadMore()

        XCTAssertEqual(viewModel.visibleEntries.count, 501)
        XCTAssertEqual(Set(viewModel.visibleEntries.map(\.id)).count, 501)
        store.close()
    }

    func testDatabaseSearchAndLoadMoreReachMatchesOutsideFirstPage() async throws {
        let store = try CoreDataHistoryStore(storeURL: directory.appendingPathComponent("History.sqlite"))
        let service = HistoryService(store: store)
        for index in 0..<501 {
            _ = try service.capture(text: "needle entry \(index)")
        }

        let viewModel = HistoryViewModel(service: service)
        await viewModel.reload()
        viewModel.updateQuery("needle")
        await viewModel.waitForPendingSearch()
        XCTAssertEqual(viewModel.visibleEntries.count, 500)

        await viewModel.loadMore()

        XCTAssertEqual(viewModel.visibleEntries.count, 501)
        XCTAssertTrue(viewModel.visibleEntries.allSatisfy { $0.text.contains("needle") })
        store.close()
    }

    func testReloadWhileSearchIsActiveKeepsTheSearchGeneration() async throws {
        let store = try CoreDataHistoryStore(storeURL: directory.appendingPathComponent("History.sqlite"))
        let service = HistoryService(store: store)
        for index in 0..<3 {
            _ = try service.capture(text: index == 1 ? "needle result" : "other result")
        }

        let viewModel = HistoryViewModel(service: service, searchDebounceNanoseconds: 0)
        await viewModel.reload()
        viewModel.updateQuery("needle")
        await viewModel.waitForPendingSearch()
        await viewModel.reload()

        XCTAssertEqual(viewModel.query, "needle")
        XCTAssertEqual(viewModel.visibleEntries.map(\.text), ["needle result"])
        store.close()
    }
}
