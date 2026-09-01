import CoreData
import AppKit
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

    func testManagedImageCaptureSurvivesRestartAndPastesExactRepresentations() throws {
        let clock = MutableClock(now: Date(timeIntervalSinceReferenceDate: 8_300_000))
        let store = try makeStore()
        let service = HistoryService(store: store, clock: clock)
        let imageData = try makePNGData()
        let entry = try XCTUnwrap(try service.capture(imageItems: [
            ManagedImageCaptureItem(order: 0, representations: [
                ManagedImageCaptureRepresentation(typeIdentifier: "public.png", data: imageData)
            ])
        ]))

        XCTAssertTrue(entry.isImageEntry)
        XCTAssertTrue(entry.text.isEmpty)
        XCTAssertEqual(entry.imageMetadata.first?.pixelWidth, 2)
        XCTAssertEqual(try service.entries().map(\.id), [entry.id])
        XCTAssertNotNil(try service.thumbnailData(id: entry.id))

        let restarted = try CoreDataHistoryStore(storeURL: directory.appendingPathComponent("History.sqlite"))
        let restored = try XCTUnwrap(restarted.fetchEntry(id: entry.id))
        XCTAssertEqual(restored.managedImages, entry.managedImages)
        let payload = try XCTUnwrap(restarted.pastePayload(id: entry.id))
        XCTAssertEqual(payload.items.count, 1)
        XCTAssertEqual(payload.items[0].representations.map(\.typeIdentifier), ["public.png"])
        XCTAssertEqual(payload.items[0].representations[0].data, imageData)
        restarted.close()
        store.close()
    }

    func testMixedImageAndReferenceRemainOneOccurrenceAndOnePasteboardItem() throws {
        let clock = MutableClock(now: Date(timeIntervalSinceReferenceDate: 8_325_000))
        let store = try makeStore()
        let service = HistoryService(store: store, clock: clock)
        let sourceURL = directory.appendingPathComponent("mixed.txt")
        let sourceBytes = Data("mixed source remains outside Qipli".utf8)
        try sourceBytes.write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        let imageData = try makePNGData()

        let entry = try XCTUnwrap(service.capture(
            imageItems: [ManagedImageCaptureItem(
                order: 0,
                representations: [ManagedImageCaptureRepresentation(typeIdentifier: "public.png", data: imageData)]
            )],
            referenceItems: [makeReferenceItem(url: sourceURL, kind: .fileReference, order: 0)]
        ))

        XCTAssertEqual(try service.entries().map(\.id), [entry.id])
        XCTAssertEqual(entry.representations.map(\.kind), [.inlineImage, .fileReference])
        let occurrence = try XCTUnwrap(service.occurrence(id: entry.id))
        XCTAssertEqual(occurrence.items.flatMap(\.representations).map(\.kind), [.inlineImage, .fileReference])
        let payload = try XCTUnwrap(service.pastePayload(id: entry.id))
        XCTAssertEqual(payload.items.count, 1)
        XCTAssertEqual(payload.items[0].representations.map(\.typeIdentifier), ["public.png", "public.file-url"])
        XCTAssertEqual(payload.items[0].representations[0].data, imageData)
        let pastedURL = try XCTUnwrap(URL(string: String(
            data: payload.items[0].representations[1].data,
            encoding: .utf8
        ) ?? ""))
        XCTAssertEqual(pastedURL.lastPathComponent, sourceURL.lastPathComponent)
        XCTAssertEqual(try Data(contentsOf: pastedURL), sourceBytes)
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBytes)
        store.close()
    }

    func testManagedImageNameUsesFirstCaptureTimeAndSurvivesReuse() throws {
        let firstCapture = Date(timeIntervalSinceReferenceDate: 8_350_000)
        let clock = MutableClock(now: firstCapture)
        let store = try makeStore()
        let service = HistoryService(store: store, clock: clock)
        let entry = try XCTUnwrap(try service.capture(imageItems: [
            ManagedImageCaptureItem(order: 0, representations: [
                ManagedImageCaptureRepresentation(typeIdentifier: "public.png", data: try makePNGData())
            ])
        ]))
        let expectedName = ManagedImageNaming.name(capturedAt: firstCapture)
        XCTAssertEqual(entry.displayText, expectedName)

        clock.now = firstCapture.addingTimeInterval(120)
        _ = try service.markUsed(id: entry.id)
        XCTAssertEqual(try store.fetchEntry(id: entry.id)?.displayText, expectedName)

        let restarted = try CoreDataHistoryStore(storeURL: directory.appendingPathComponent("History.sqlite"))
        XCTAssertEqual(try restarted.fetchEntry(id: entry.id)?.displayText, expectedName)
        restarted.close()
        store.close()
    }

    func testWebURLStoresExactStringSearchMetadataAndPastePayloadWithoutNetwork() throws {
        let clock = MutableClock(now: Date(timeIntervalSinceReferenceDate: 8_360_000))
        let store = try makeStore()
        let service = HistoryService(store: store, clock: clock)
        let exactURL = "https://example.com/a%2Fb?q=one%20two"
        let entry = try XCTUnwrap(service.capture(referenceItems: [
            HistoryReferenceCaptureItem(
                order: 0,
                kind: .url,
                typeIdentifier: NSPasteboard.PasteboardType.URL.rawValue,
                urlString: exactURL,
                metadata: HistoryReferenceMetadata(
                    displayName: "example.com",
                    typeIdentifier: NSPasteboard.PasteboardType.URL.rawValue,
                    domain: "example.com",
                    searchText: exactURL
                )
            )
        ]))

        XCTAssertEqual(entry.displayText, "example.com")
        XCTAssertEqual(entry.referenceMetadata.first?.domain, "example.com")
        let page = try store.searchPage(
            query: "a%2Fb",
            since: clock.now.addingTimeInterval(-1),
            after: nil,
            limit: 10
        )
        XCTAssertEqual(page.descriptors.map(\.id), [entry.id])
        let payload = try XCTUnwrap(service.pastePayload(id: entry.id))
        XCTAssertEqual(payload.items.first?.representations.first?.typeIdentifier, "public.url")
        XCTAssertEqual(payload.items.first?.representations.first?.data, Data(exactURL.utf8))
        store.close()
    }

    func testFileAndVideoReferencesKeepOrderAndPasteOnlyFileURLs() throws {
        let store = try makeStore()
        let service = HistoryService(store: store)
        let textURL = directory.appendingPathComponent("notes.txt")
        let videoURL = directory.appendingPathComponent("clip.mov")
        let sourceBytes = Data("source bytes remain owned by the user".utf8)
        try sourceBytes.write(to: textURL)
        try Data(repeating: 4, count: 12).write(to: videoURL)
        let entry = try XCTUnwrap(service.capture(referenceItems: [
            makeReferenceItem(url: videoURL, kind: .videoReference, order: 4),
            makeReferenceItem(url: textURL, kind: .fileReference, order: 2)
        ]))

        XCTAssertEqual(entry.representations.map(\.kind), [.fileReference, .videoReference])
        XCTAssertEqual(entry.referenceMetadata.map(\.displayName), ["notes.txt", "clip.mov"])
        let occurrence = try XCTUnwrap(store.fetchOccurrence(id: entry.id))
        XCTAssertEqual(occurrence.items.map(\.order), [2, 4])
        XCTAssertEqual(occurrence.items.map { $0.representations.first?.kind }, [.fileReference, .videoReference])

        let payload = try XCTUnwrap(service.pastePayload(id: entry.id))
        XCTAssertEqual(payload.items.count, 2)
        XCTAssertEqual(payload.items.map { $0.representations.first?.typeIdentifier }, ["public.file-url", "public.file-url"])
        XCTAssertEqual(
            payload.items.map { URL(string: String(decoding: $0.representations[0].data, as: UTF8.self))?.standardizedFileURL },
            [textURL, videoURL].map(\.standardizedFileURL)
        )
        XCTAssertEqual(try Data(contentsOf: textURL), sourceBytes)
        store.close()
    }

    func testMovedReferenceRefreshesStaleBookmarkWithoutDuplicateOccurrence() throws {
        let store = try makeStore()
        let service = HistoryService(store: store)
        let originalURL = directory.appendingPathComponent("original.txt")
        let movedURL = directory.appendingPathComponent("renamed.txt")
        try Data("bookmark source".utf8).write(to: originalURL)
        let entry = try XCTUnwrap(service.capture(referenceItems: [
            makeReferenceItem(url: originalURL, kind: .fileReference, order: 0)
        ]))
        try FileManager.default.moveItem(at: originalURL, to: movedURL)

        let payload = try XCTUnwrap(service.pastePayload(id: entry.id))
        XCTAssertEqual(
            URL(string: String(decoding: payload.items[0].representations[0].data, as: UTF8.self))?.standardizedFileURL,
            movedURL.standardizedFileURL
        )
        XCTAssertEqual(try store.fetchCurrent(since: .distantPast).map(\.id), [entry.id])
        XCTAssertEqual(try store.fetchEntry(id: entry.id)?.referenceMetadata.first?.displayName, "renamed.txt")
        store.close()
    }

    func testUnavailableReferenceRemainsVisibleAndHistoryDeletionDoesNotDeleteSource() throws {
        let store = try makeStore()
        let service = HistoryService(store: store)
        let sourceURL = directory.appendingPathComponent("keep.txt")
        let sourceBytes = Data("do not delete this".utf8)
        try sourceBytes.write(to: sourceURL)
        let entry = try XCTUnwrap(service.capture(referenceItems: [
            makeReferenceItem(url: sourceURL, kind: .fileReference, order: 0)
        ]))
        try FileManager.default.removeItem(at: sourceURL)

        XCTAssertThrowsError(try service.pastePayload(id: entry.id)) { error in
            XCTAssertEqual(error as? HistoryStoreError, .referenceUnavailable)
        }
        XCTAssertEqual(try store.fetchEntry(id: entry.id)?.referenceMetadata.first?.availability, .unavailable)
        try service.delete(id: entry.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))

        let protectedURL = directory.appendingPathComponent("protected.txt")
        let protectedBytes = Data("source survives History deletion".utf8)
        try protectedBytes.write(to: protectedURL)
        let protectedEntry = try XCTUnwrap(service.capture(referenceItems: [
            makeReferenceItem(url: protectedURL, kind: .fileReference, order: 0)
        ]))
        try service.delete(id: protectedEntry.id)
        XCTAssertEqual(try Data(contentsOf: protectedURL), protectedBytes)

        let clearURL = directory.appendingPathComponent("clear-keeps-source.txt")
        let clearBytes = Data("clear all must not touch this".utf8)
        try clearBytes.write(to: clearURL)
        _ = try service.capture(referenceItems: [
            makeReferenceItem(url: clearURL, kind: .fileReference, order: 0)
        ])
        try service.clearAll()
        XCTAssertEqual(try Data(contentsOf: clearURL), clearBytes)
        store.close()
    }

    func testManagedImageOccurrencePreservesItemAndRepresentationOrderAcrossRestart() throws {
        let store = try makeStore()
        let service = HistoryService(store: store)
        let firstPNG = try makeImageData(width: 4, height: 2, format: .png)
        let firstTIFF = try makeImageData(width: 4, height: 2, format: .tiff)
        let secondPNG = try makeImageData(width: 2, height: 4, format: .png)
        let entry = try XCTUnwrap(try service.capture(imageItems: [
            ManagedImageCaptureItem(order: 9, representations: [
                ManagedImageCaptureRepresentation(typeIdentifier: "public.png", data: firstPNG),
                ManagedImageCaptureRepresentation(typeIdentifier: "public.tiff", data: firstTIFF)
            ]),
            ManagedImageCaptureItem(order: 3, representations: [
                ManagedImageCaptureRepresentation(typeIdentifier: "public.png", data: secondPNG)
            ])
        ]))

        let restarted = try CoreDataHistoryStore(storeURL: directory.appendingPathComponent("History.sqlite"))
        let payload = try XCTUnwrap(restarted.pastePayload(id: entry.id))
        XCTAssertEqual(payload.items.count, 2)
        XCTAssertEqual(payload.items.map(\.representations.count), [1, 2])
        XCTAssertEqual(payload.items[0].representations[0].data, secondPNG)
        XCTAssertEqual(payload.items[1].representations.map(\.typeIdentifier), ["public.png", "public.tiff"])
        XCTAssertEqual(payload.items[1].representations.map(\.data), [firstPNG, firstTIFF])
        restarted.close()
        store.close()
    }

    func testManagedImageThumbnailRespectsConfiguredLongEdge() throws {
        let policy = HistoryImageStoragePolicy(
            maxImageItemBytes: 2 * 1024 * 1024,
            maxOccurrenceBytes: 2 * 1024 * 1024,
            maxTotalOriginalBytes: 2 * 1024 * 1024,
            thumbnailCacheBytes: 1024,
            thumbnailLongEdge: 32
        )
        let assetStore = try ManagedImageAssetStore(
            rootURL: directory.appendingPathComponent("ManagedImages", isDirectory: true),
            policy: policy
        )
        let source = try makeImageData(width: 128, height: 64, format: .png)
        let manifest = try assetStore.commit(
            occurrenceID: UUID(),
            items: [ManagedImageCaptureItem(order: 0, representations: [
                ManagedImageCaptureRepresentation(typeIdentifier: "public.png", data: source)
            ])]
        )

        let thumbnail = try XCTUnwrap(assetStore.makeThumbnail(for: manifest))
        let dimensions = HistoryImageDimensions.read(from: thumbnail)
        XCTAssertEqual(max(dimensions.width, dimensions.height), 32)
    }

    func testTypedImagePageExcludesPayloadFromTextEntries() throws {
        let store = try makeStore()
        let service = HistoryService(store: store)
        _ = try service.capture(text: "text row")
        let image = try XCTUnwrap(try service.capture(imageItems: [
            ManagedImageCaptureItem(order: 0, representations: [
                ManagedImageCaptureRepresentation(typeIdentifier: "public.png", data: try makePNGData())
            ])
        ]))

        let page = try store.fetchPage(since: .distantPast, after: nil, limit: 500)
        XCTAssertTrue(page.entries.contains(where: { $0.id == image.id }))
        XCTAssertFalse(page.textEntries.contains(where: { $0.id == image.id }))
        store.close()
    }

    func testManagedImageDeleteRemovesOwnedAssetAndClearAllRemovesTheRoot() throws {
        let store = try makeStore()
        let service = HistoryService(store: store)
        let entry = try XCTUnwrap(try service.capture(imageItems: [
            ManagedImageCaptureItem(order: 0, representations: [
                ManagedImageCaptureRepresentation(typeIdentifier: "public.png", data: try makePNGData())
            ])
        ]))
        let imagesRoot = directory.appendingPathComponent("ManagedImages/images", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: imagesRoot.path))

        try service.delete(id: entry.id)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: imagesRoot.appendingPathComponent(entry.id.uuidString).path
        ))

        _ = try service.capture(imageItems: [
            ManagedImageCaptureItem(order: 0, representations: [
                ManagedImageCaptureRepresentation(typeIdentifier: "public.png", data: try makePNGData())
            ])
        ])
        try service.clearAll()
        XCTAssertTrue(try service.entries().isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: imagesRoot.path))
        store.close()
    }

    func testManagedImageCapacityRejectsNewCaptureWithoutRemovingExistingAssets() throws {
        let policy = HistoryImageStoragePolicy(
            maxImageItemBytes: 100,
            maxOccurrenceBytes: 100,
            maxTotalOriginalBytes: 100,
            thumbnailCacheBytes: 100,
            thumbnailLongEdge: 32
        )
        let assetStore = try ManagedImageAssetStore(
            rootURL: directory.appendingPathComponent("ManagedImages", isDirectory: true),
            policy: policy
        )
        let first = try assetStore.commit(
            occurrenceID: UUID(),
            items: [ManagedImageCaptureItem(order: 0, representations: [
                ManagedImageCaptureRepresentation(typeIdentifier: "public.png", data: Data(repeating: 7, count: 60))
            ])]
        )

        XCTAssertThrowsError(try assetStore.commit(
            occurrenceID: UUID(),
            items: [ManagedImageCaptureItem(order: 0, representations: [
                ManagedImageCaptureRepresentation(typeIdentifier: "public.png", data: Data(repeating: 8, count: 60))
            ])]
        )) { error in
            XCTAssertEqual(error as? ManagedImageStoreError, .storageLimitReached)
        }
        XCTAssertEqual(try assetStore.read(first.representations[0]).count, 60)
    }

    func testManagedImagePathsAndIntegrityFailClosed() throws {
        let assetStore = try ManagedImageAssetStore(
            rootURL: directory.appendingPathComponent("ManagedImages", isDirectory: true),
            policy: .production
        )
        let manifest = try assetStore.commit(
            occurrenceID: UUID(),
            items: [ManagedImageCaptureItem(order: 0, representations: [
                ManagedImageCaptureRepresentation(typeIdentifier: "public.png", data: Data(repeating: 3, count: 4))
            ])]
        )
        XCTAssertThrowsError(try assetStore.read(HistoryManagedImageRepresentation(
            typeIdentifier: "public.png",
            relativePath: "images/../outside",
            metadata: HistoryImageMetadata(byteCount: 4),
            sha256: manifest.representations[0].sha256
        ))) { error in
            XCTAssertEqual(error as? ManagedImageStoreError, .invalidManagedPath)
        }
        let url = directory.appendingPathComponent("ManagedImages").appendingPathComponent(manifest.representations[0].relativePath)
        try Data(repeating: 9, count: 4).write(to: url)
        XCTAssertThrowsError(try assetStore.read(manifest.representations[0])) { error in
            XCTAssertEqual(error as? ManagedImageStoreError, .corruptAsset)
        }
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

    private func makePNGData() throws -> Data {
        try makeImageData(width: 2, height: 2, format: .png)
    }

    private func makeReferenceItem(
        url: URL,
        kind: HistoryRepresentationKind,
        order: Int
    ) -> HistoryReferenceCaptureItem {
        let name = url.lastPathComponent
        let typeIdentifier = kind == .videoReference ? "public.movie" : "public.data"
        return HistoryReferenceCaptureItem(
            order: order,
            kind: kind,
            typeIdentifier: typeIdentifier,
            url: url,
            metadata: HistoryReferenceMetadata(
                displayName: name,
                fileExtension: url.pathExtension,
                typeIdentifier: typeIdentifier,
                byteCount: nil,
                searchText: [name, url.pathExtension, typeIdentifier].joined(separator: " ")
            )
        )
    }

    private func makeImageData(
        width: Int,
        height: Int,
        format: NSBitmapImageRep.FileType
    ) throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        return try XCTUnwrap(bitmap.representation(using: format, properties: [:]))
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
