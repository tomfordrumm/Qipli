import AppKit
import Combine
import XCTest
@testable import Qipli

@MainActor
final class HistoryViewModelSearchTests: XCTestCase {
    func testHistoryTableRowsStayCompactAndGrowForMultilinePreviews() {
        let singleLineHeight = HistoryTableRowLayout.height(
            for: "Short entry",
            textWidth: 500
        )
        let twoLineHeight = HistoryTableRowLayout.height(
            for: "First line\nSecond line",
            textWidth: 500
        )
        let threeLineHeight = HistoryTableRowLayout.height(
            for: "First line\nSecond line\nThird line",
            textWidth: 500
        )
        let fourLineHeight = HistoryTableRowLayout.height(
            for: "First line\nSecond line\nThird line\nFourth line",
            textWidth: 500
        )

        XCTAssertEqual(singleLineHeight, HistoryTableRowLayout.minimumRowHeight)
        XCTAssertGreaterThan(twoLineHeight, singleLineHeight)
        XCTAssertGreaterThan(threeLineHeight, twoLineHeight)
        XCTAssertEqual(fourLineHeight, threeLineHeight)
    }

    func testHistoryTableRowHeightCacheStaysBoundedAndEvictsOldestEntry() {
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        var cache = HistoryTableRowHeightCache(capacity: 2)

        cache.insert(height: 38, for: firstID, textWidth: 300)
        cache.insert(height: 54, for: secondID, textWidth: 300)
        cache.insert(height: 70, for: thirdID, textWidth: 300)

        XCTAssertEqual(cache.count, 2)
        XCTAssertNil(cache.height(for: firstID, textWidth: 300))
        XCTAssertEqual(cache.height(for: secondID, textWidth: 300), 54)
        XCTAssertEqual(cache.height(for: thirdID, textWidth: 300), 70)
    }

    func testHistoryTableRowHeightCacheReplacesWidthWithoutGrowing() {
        let id = UUID()
        var cache = HistoryTableRowHeightCache(capacity: 2)

        cache.insert(height: 38, for: id, textWidth: 300)
        cache.insert(height: 54, for: id, textWidth: 220)

        XCTAssertEqual(cache.count, 1)
        XCTAssertNil(cache.height(for: id, textWidth: 300))
        XCTAssertEqual(cache.height(for: id, textWidth: 220), 54)
    }

    func testLocalizedCaseInsensitiveSearchSelectsFirstResultAndKeepsStoredText() async throws {
        let first = makeEntry("first", offset: 1)
        let matching = makeEntry("Äpfel", offset: 2)
        let other = makeEntry("other", offset: 3)
        let store = InMemoryHistoryStore(entries: [other, matching, first])
        let viewModel = HistoryViewModel(service: HistoryService(store: store))

        await viewModel.reload(selectFirstResult: true)
        viewModel.updateQuery("äP")
        await viewModel.waitForPendingSearch()

        XCTAssertEqual(viewModel.visibleEntries, [matching])
        XCTAssertEqual(viewModel.selectedEntryID, matching.id)
        XCTAssertEqual(store.entries.first { $0.id == matching.id }?.text, "Äpfel")
    }

    func testSelectionMovesWithinVisibleResultsAndResetsAfterQueryChange() async {
        let first = makeEntry("alpha", offset: 3)
        let second = makeEntry("alphabet", offset: 2)
        let third = makeEntry("beta", offset: 1)
        let viewModel = HistoryViewModel(service: HistoryService(store: InMemoryHistoryStore(entries: [first, second, third])))

        await viewModel.reload(selectFirstResult: true)
        viewModel.moveSelection(by: 1)
        XCTAssertEqual(viewModel.selectedEntryID, second.id)

        viewModel.updateQuery("alpha")
        await viewModel.waitForPendingSearch()
        XCTAssertEqual(viewModel.selectedEntryID, first.id)
        viewModel.moveSelection(by: 100)
        XCTAssertEqual(viewModel.selectedEntryID, second.id)
        viewModel.moveSelection(by: -100)
        XCTAssertEqual(viewModel.selectedEntryID, first.id)
    }

    func testDeletingSelectedFilteredEntrySelectsNearestVisibleEntry() async {
        let first = makeEntry("needle one", offset: 3)
        let second = makeEntry("needle two", offset: 2)
        let third = makeEntry("needle three", offset: 1)
        let store = InMemoryHistoryStore(entries: [first, second, third])
        let viewModel = HistoryViewModel(service: HistoryService(store: store))

        await viewModel.reload(selectFirstResult: true)
        viewModel.updateQuery("needle")
        await viewModel.waitForPendingSearch()
        viewModel.select(id: second.id)
        await viewModel.delete(second)

        XCTAssertEqual(viewModel.visibleEntries.map(\.id), [first.id, third.id])
        XCTAssertEqual(viewModel.selectedEntryID, third.id)
        XCTAssertFalse(store.entries.contains { $0.id == second.id })
    }

    func testPromotionStorageFailureDoesNotClaimPasteFailureOrChangeOccurrence() async {
        let entry = makeEntry("stable", offset: 1)
        let store = InMemoryHistoryStore(entries: [entry], markUsedError: HistoryStoreError.unavailable)
        let viewModel = HistoryViewModel(service: HistoryService(store: store))

        await viewModel.reload(selectFirstResult: true)
        await viewModel.markUsedAfterSuccessfulPaste(id: entry.id)

        XCTAssertEqual(viewModel.selectedEntry, entry)
        XCTAssertNil(viewModel.pasteFailure)
        XCTAssertEqual(store.entries, [entry])
    }

    func testSuccessfulPromotionUpdatesCachedRecencyWithoutRefetchingStorage() async {
        let initialNow = Date(timeIntervalSinceReferenceDate: 10_000)
        let first = HistoryEntry(id: UUID(), text: "first", activityAt: initialNow.addingTimeInterval(-10))
        let promoted = HistoryEntry(id: UUID(), text: "promoted", activityAt: initialNow.addingTimeInterval(-20))
        let clock = TestHistoryClock(now: initialNow)
        let store = InMemoryHistoryStore(entries: [first, promoted])
        let viewModel = HistoryViewModel(
            service: HistoryService(store: store, clock: clock),
            now: { clock.now }
        )
        await viewModel.reload(selectFirstResult: true)
        let fetchCountBeforePromotion = store.fetchCount

        clock.now = initialNow.addingTimeInterval(5)
        await viewModel.markUsedAfterSuccessfulPaste(id: promoted.id)

        XCTAssertEqual(viewModel.visibleEntries.map(\.id), [first.id, promoted.id])

        viewModel.prepareForPresentation()

        XCTAssertEqual(store.fetchCount, fetchCountBeforePromotion)
        XCTAssertEqual(viewModel.visibleEntries.map(\.id), [promoted.id, first.id])
        XCTAssertEqual(viewModel.visibleEntries.first?.activityAt, clock.now)
    }

    func testCachedRecencyPublishesOnlyOnTheNextPresentation() async {
        let initialNow = Date(timeIntervalSinceReferenceDate: 10_000)
        let first = HistoryEntry(id: UUID(), text: "first", activityAt: initialNow.addingTimeInterval(-10))
        let promoted = HistoryEntry(id: UUID(), text: "promoted", activityAt: initialNow.addingTimeInterval(-20))
        let clock = TestHistoryClock(now: initialNow)
        let store = InMemoryHistoryStore(entries: [first, promoted])
        let viewModel = HistoryViewModel(
            service: HistoryService(store: store, clock: clock),
            now: { clock.now }
        )
        await viewModel.reload(selectFirstResult: true)
        viewModel.select(id: promoted.id)

        clock.now = initialNow.addingTimeInterval(5)
        await viewModel.markUsedAfterSuccessfulPaste(id: promoted.id)
        var statePublicationCount = 0
        let observation = viewModel.$state
            .dropFirst()
            .sink { _ in statePublicationCount += 1 }

        XCTAssertEqual(viewModel.visibleEntries.map(\.id), [first.id, promoted.id])
        XCTAssertEqual(viewModel.selectedEntryID, promoted.id)

        viewModel.prepareForPresentation()

        XCTAssertEqual(viewModel.visibleEntries.map(\.id), [promoted.id, first.id])
        XCTAssertEqual(viewModel.selectedEntryID, promoted.id)
        XCTAssertEqual(viewModel.visibleEntries.first?.activityAt, clock.now)
        XCTAssertEqual(statePublicationCount, 1)
        withExtendedLifetime(observation) {}
    }

    func testPresentationPrunesExpiredCachedEntriesWithoutRefetchingStorage() async {
        let initialNow = Date(timeIntervalSinceReferenceDate: HistoryService.retention + 10_000)
        let soonExpired = HistoryEntry(
            id: UUID(),
            text: "expires from snapshot",
            activityAt: initialNow.addingTimeInterval(-HistoryService.retention + 60)
        )
        let fresh = HistoryEntry(id: UUID(), text: "fresh", activityAt: initialNow.addingTimeInterval(-10))
        let clock = TestHistoryClock(now: initialNow)
        let store = InMemoryHistoryStore(entries: [fresh, soonExpired])
        let viewModel = HistoryViewModel(
            service: HistoryService(store: store, clock: clock),
            now: { clock.now }
        )
        await viewModel.reload(selectFirstResult: true)
        let fetchCountAfterReload = store.fetchCount

        clock.now = initialNow.addingTimeInterval(61)
        viewModel.prepareForPresentation()

        XCTAssertEqual(store.fetchCount, fetchCountAfterReload)
        XCTAssertEqual(viewModel.visibleEntries, [fresh])
        XCTAssertEqual(viewModel.selectedEntryID, fresh.id)
    }

    func testFreshPresentationViewportResetSignalIsIndependentFromSearchFocus() async {
        let first = makeEntry("first", offset: 2)
        let second = makeEntry("second", offset: 1)
        let viewModel = HistoryViewModel(service: HistoryService(store: InMemoryHistoryStore(entries: [first, second])))

        await viewModel.reload()
        viewModel.prepareForPresentation()
        viewModel.requestPresentationViewportReset()

        XCTAssertEqual(viewModel.selectedEntryID, first.id)
        XCTAssertEqual(viewModel.presentationViewportResetRequestID, 1)
        XCTAssertEqual(viewModel.searchFocusRequestID, 0)

        viewModel.requestSearchFocus()
        XCTAssertEqual(viewModel.presentationViewportResetRequestID, 1)
        XCTAssertEqual(viewModel.searchFocusRequestID, 1)
    }

    func testClearAllReportsSuccessAndFailureWithoutClaimingAFalseEmptyState() async {
        let entry = makeEntry("private", offset: 1)
        let store = InMemoryHistoryStore(entries: [entry])
        let viewModel = HistoryViewModel(service: HistoryService(store: store))
        await viewModel.reload(selectFirstResult: true)

        store.clearAllError = HistoryStoreError.unavailable
        let failedClearResult = await viewModel.clearAll()
        XCTAssertFalse(failedClearResult)
        XCTAssertEqual(viewModel.state, .error)
        XCTAssertEqual(store.entries, [entry])

        store.clearAllError = nil
        let successfulClearResult = await viewModel.clearAll()
        XCTAssertTrue(successfulClearResult)
        XCTAssertEqual(viewModel.state, .empty)
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testExternalCaptureUpdatesVisibleHistoryWithoutRefetchingStorage() async {
        let existing = makeEntry("existing", offset: 1)
        let store = InMemoryHistoryStore(entries: [existing])
        let viewModel = HistoryViewModel(service: HistoryService(store: store))
        await viewModel.reload(selectFirstResult: true)
        let fetchCountBeforeCapture = store.fetchCount

        let captured = await viewModel.recordExternalText("new capture")

        XCTAssertEqual(store.fetchCount, fetchCountBeforeCapture)
        XCTAssertEqual(viewModel.visibleEntries.first?.id, captured?.id)
        XCTAssertEqual(viewModel.visibleEntries.map(\.text), ["new capture", "existing"])
    }

    func testRepeatedPresentationsReuseLoadedSnapshotWithoutRefetchingStorage() async {
        let store = InMemoryHistoryStore(entries: [makeEntry("existing", offset: 1)])
        let viewModel = HistoryViewModel(service: HistoryService(store: store))
        await viewModel.reload(selectFirstResult: true)
        let fetchCountAfterStartup = store.fetchCount

        viewModel.prepareForPresentation()
        viewModel.prepareForPresentation()

        XCTAssertEqual(store.fetchCount, fetchCountAfterStartup)
        XCTAssertEqual(viewModel.visibleEntries.map(\.text), ["existing"])
    }

    func testEveryViewModelStorageOperationRunsAwayFromMainThread() async {
        let existing = makeEntry("existing", offset: 1)
        let store = InMemoryHistoryStore(entries: [existing])
        let viewModel = HistoryViewModel(service: HistoryService(store: store))

        await viewModel.reload()
        let captured = await viewModel.recordExternalText("captured")
        await viewModel.markUsedAfterSuccessfulPaste(id: existing.id)
        if let captured {
            await viewModel.delete(captured)
        }
        _ = await viewModel.clearAll()

        XCTAssertEqual(store.operationNames, ["fetch", "create", "markUsed", "delete", "clearAll"])
        XCTAssertTrue(store.operationWasOnMainThread.allSatisfy { !$0 })
    }

    func testMainActorRemainsAvailableWhileStorageFetchIsBlocked() async {
        let fetchStarted = expectation(description: "background fetch started")
        let releaseFetch = DispatchSemaphore(value: 0)
        let store = InMemoryHistoryStore(entries: [makeEntry("existing", offset: 1)])
        store.onFetch = {
            fetchStarted.fulfill()
            _ = releaseFetch.wait(timeout: .now() + 2)
        }
        let viewModel = HistoryViewModel(service: HistoryService(store: store))

        let reload = Task { @MainActor in
            await viewModel.reload()
        }
        await fulfillment(of: [fetchStarted], timeout: 0.5)

        XCTAssertEqual(viewModel.state, .loading)
        releaseFetch.signal()
        await reload.value
        XCTAssertEqual(viewModel.visibleEntries.map(\.text), ["existing"])
    }

    func testStaleSearchCompletionCannotReplaceLatestQueryResults() async {
        let alpha = makeEntry("alpha result", offset: 2)
        let beta = makeEntry("beta result", offset: 1)
        let searcher = StaleCompletionHistorySearcher()
        let viewModel = HistoryViewModel(
            service: HistoryService(store: InMemoryHistoryStore(entries: [alpha, beta])),
            searcher: searcher,
            searchDebounceNanoseconds: 0
        )
        await viewModel.reload()

        viewModel.updateQuery("alpha")
        await searcher.waitUntilSlowSearchStarts()
        viewModel.updateQuery("beta")
        await viewModel.waitForPendingSearch()

        XCTAssertEqual(viewModel.visibleEntries, [beta])
        XCTAssertEqual(viewModel.selectedEntryID, beta.id)
        await searcher.releaseSlowSearch()
        await searcher.waitUntilSlowSearchFinishes()
        await Task.yield()
        XCTAssertEqual(viewModel.visibleEntries, [beta])
        XCTAssertEqual(viewModel.query, "beta")
    }

    func testSearchRunsOffMainActorAndEmptyQueryRestoresSnapshotImmediately() async {
        let first = makeEntry("alpha", offset: 2)
        let second = makeEntry("beta", offset: 1)
        let searcher = RecordingHistorySearcher()
        let viewModel = HistoryViewModel(
            service: HistoryService(store: InMemoryHistoryStore(entries: [first, second])),
            searcher: searcher,
            searchDebounceNanoseconds: 0
        )
        await viewModel.reload()

        viewModel.updateQuery("missing")
        await viewModel.waitForPendingSearch()
        XCTAssertTrue(viewModel.visibleEntries.isEmpty)
        XCTAssertNil(viewModel.selectedEntryID)
        let searchRanOnMainThread = await searcher.lastRunWasOnMainThread()
        XCTAssertFalse(searchRanOnMainThread)

        viewModel.updateQuery("")
        XCTAssertEqual(viewModel.visibleEntries, [first, second])
        XCTAssertEqual(viewModel.selectedEntryID, first.id)
        XCTAssertFalse(viewModel.isSearchInProgress)
    }

    func testBoundedPreviewTraversesOnlyLimitPlusOneUnicodeCharacters() {
        let family = "👨‍👩‍👧‍👦"
        let fullText = family + "\n" + "é" + "🦊" + String(repeating: "tail", count: 10_000)
        var traversedCharacters: [Character] = []

        let preview = BoundedTextPreview.text(
            for: fullText,
            maximumCharacters: 3,
            didTraverse: { traversedCharacters.append($0) }
        )

        XCTAssertEqual(traversedCharacters, [Character(family), "\n", "é", "🦊"])
        XCTAssertEqual(preview, family + "\n" + "é…")
        XCTAssertEqual(HistoryPreview.text(for: "short\n🦊"), "short\n🦊")
    }

    func testSearchBeyondPreviewBoundaryStillPastesExactLongText() async {
        let marker = "needle-beyond-preview"
        let fullText = String(repeating: "🦊", count: HistoryPreview.maximumCharacters + 500) + "\n" + marker
        let entry = makeEntry(fullText, offset: 1)
        let viewModel = HistoryViewModel(
            service: HistoryService(store: InMemoryHistoryStore(entries: [entry])),
            searchDebounceNanoseconds: 0
        )
        await viewModel.reload()

        XCTAssertFalse(HistoryPreview.text(for: fullText).contains(marker))
        viewModel.updateQuery(marker)
        await viewModel.waitForPendingSearch()
        XCTAssertEqual(viewModel.selectedEntry?.text, fullText)

        let trace = Trace()
        let writer = FakeHistoryPasteboardWriter(changeCount: 42, trace: trace)
        let executor = HistoryPasteExecutor(
            permissionService: FakeHistoryPermissionService(state: .granted),
            pasteboardWriter: writer,
            registerSelfWrite: { _ in },
            commandDispatcher: FakePasteCommandDispatcher(trace: trace, result: true)
        )
        var result: Result<Void, HistoryPasteFailure>?
        executor.paste(
            entry: viewModel.selectedEntry!,
            target: FakeHistoryPasteTarget(trace: trace),
            concealPanel: {},
            closePanel: {},
            completion: { result = $0 }
        )

        XCTAssertNoThrow(try result?.get())
        XCTAssertEqual(writer.writtenTexts, [fullText])
    }

    private func makeEntry(_ text: String, offset: TimeInterval) -> HistoryEntry {
        HistoryEntry(id: UUID(), text: text, activityAt: Date.now.addingTimeInterval(offset))
    }
}

private actor RecordingHistorySearcher: HistorySearching {
    private var ranOnMainThread = false

    func matches(in entries: [HistoryEntry], query: String) -> [HistoryEntry] {
        ranOnMainThread = Thread.isMainThread
        return entries.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    func lastRunWasOnMainThread() -> Bool {
        ranOnMainThread
    }
}

private actor StaleCompletionHistorySearcher: HistorySearching {
    private var slowSearchStarted = false
    private var slowSearchFinished = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var finishWaiters: [CheckedContinuation<Void, Never>] = []
    private var slowSearchContinuation: CheckedContinuation<Void, Never>?

    func matches(in entries: [HistoryEntry], query: String) async -> [HistoryEntry] {
        if query == "alpha" {
            slowSearchStarted = true
            startWaiters.forEach { $0.resume() }
            startWaiters = []
            await withCheckedContinuation { continuation in
                slowSearchContinuation = continuation
            }
            slowSearchFinished = true
            finishWaiters.forEach { $0.resume() }
            finishWaiters = []
        }
        return entries.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    func waitUntilSlowSearchStarts() async {
        guard !slowSearchStarted else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func releaseSlowSearch() {
        slowSearchContinuation?.resume()
        slowSearchContinuation = nil
    }

    func waitUntilSlowSearchFinishes() async {
        guard !slowSearchFinished else { return }
        await withCheckedContinuation { finishWaiters.append($0) }
    }
}

@MainActor
final class HistoryPasteExecutorTests: XCTestCase {
    func testSuccessfulPasteRegistersExactFinalChangeAndDispatchesAfterTargetActivation() {
        let trace = Trace()
        let writer = FakeHistoryPasteboardWriter(changeCount: 41, trace: trace)
        let target = FakeHistoryPasteTarget(trace: trace)
        let dispatcher = FakePasteCommandDispatcher(trace: trace, result: true)
        var registeredChanges: [Int] = []
        let executor = makeExecutor(writer: writer, dispatcher: dispatcher, register: { registeredChanges.append($0) })
        let entry = HistoryEntry(id: UUID(), text: "line α\nline β", activityAt: .now)
        var result: Result<Void, HistoryPasteFailure>?

        executor.paste(
            entry: entry,
            target: target,
            concealPanel: { trace.events.append("conceal") },
            closePanel: { trace.events.append("close") }
        ) { result = $0 }

        XCTAssertEqual(writer.writtenTexts, [entry.text])
        XCTAssertEqual(registeredChanges, [41])
        XCTAssertEqual(trace.events, ["write", "conceal", "activate", "close", "dispatch"])
        XCTAssertNoThrow(try result?.get())
    }

    func testImagePasteWritesTheExactTypedPayloadBeforeActivation() async {
        let trace = Trace()
        let writer = FakeHistoryPasteboardWriter(changeCount: 42, trace: trace)
        let dispatcher = FakePasteCommandDispatcher(trace: trace, result: true)
        let payload = HistoryPastePayload(items: [
            HistoryPasteboardItemPayload(representations: [
                HistoryPasteboardRepresentationPayload(typeIdentifier: "public.png", data: Data([4, 5, 6])),
                HistoryPasteboardRepresentationPayload(typeIdentifier: "public.tiff", data: Data([7, 8]))
            ])
        ])
        let image = HistoryEntry(
            id: UUID(),
            text: "",
            activityAt: .now,
            representations: [HistoryRepresentationDescriptor(kind: .inlineImage, typeIdentifier: "public.png")],
            imageMetadata: [HistoryImageMetadata(pixelWidth: 2, pixelHeight: 2, byteCount: 3)],
            managedImages: [HistoryManagedImageRepresentation(
                typeIdentifier: "public.png",
                relativePath: "images/managed.asset",
                metadata: HistoryImageMetadata(pixelWidth: 2, pixelHeight: 2, byteCount: 3),
                sha256: "fixture"
            )]
        )
        let executor = HistoryPasteExecutor(
            permissionService: FakeHistoryPermissionService(state: .granted),
            pasteboardWriter: writer,
            registerSelfWrite: { _ in },
            commandDispatcher: dispatcher,
            payloadProvider: { _ in payload }
        )
        let completionExpectation = expectation(description: "image paste completion")
        var result: Result<Void, HistoryPasteFailure>?

        executor.paste(
            entry: image,
            target: FakeHistoryPasteTarget(trace: trace),
            concealPanel: { trace.events.append("conceal") },
            closePanel: { trace.events.append("close") },
            completion: {
                result = $0
                completionExpectation.fulfill()
            }
        )
        await fulfillment(of: [completionExpectation], timeout: 1)

        XCTAssertEqual(writer.writtenPayloads, [payload])
        XCTAssertTrue(writer.writtenTexts.isEmpty)
        XCTAssertEqual(trace.events, ["write", "conceal", "activate", "close", "dispatch"])
        XCTAssertNoThrow(try result?.get())
    }

    func testMissingPermissionDoesNotWriteClipboardOrClaimSuccess() {
        let trace = Trace()
        let writer = FakeHistoryPasteboardWriter(changeCount: 6, trace: trace)
        let dispatcher = FakePasteCommandDispatcher(trace: trace, result: true)
        let executor = makeExecutor(permission: .denied, writer: writer, dispatcher: dispatcher, register: { _ in })
        var result: Result<Void, HistoryPasteFailure>?

        executor.paste(
            entry: sampleEntry,
            target: FakeHistoryPasteTarget(trace: trace),
            concealPanel: { trace.events.append("conceal") },
            closePanel: { trace.events.append("close") }
        ) {
            result = $0
        }

        XCTAssertEqual(result?.failureValue, .accessibilityRequired)
        XCTAssertTrue(trace.events.isEmpty)
    }

    func testUnavailableTargetDoesNotWriteClipboardOrClosePanel() {
        let trace = Trace()
        let writer = FakeHistoryPasteboardWriter(changeCount: 7, trace: trace)
        let dispatcher = FakePasteCommandDispatcher(trace: trace, result: true)
        let executor = makeExecutor(writer: writer, dispatcher: dispatcher, register: { _ in })
        let target = FakeHistoryPasteTarget(trace: trace, terminated: true)
        var result: Result<Void, HistoryPasteFailure>?

        executor.paste(
            entry: sampleEntry,
            target: target,
            concealPanel: { trace.events.append("conceal") },
            closePanel: { trace.events.append("close") }
        ) {
            result = $0
        }

        XCTAssertEqual(result?.failureValue, .targetUnavailable)
        XCTAssertTrue(trace.events.isEmpty)
    }

    func testPasteboardWriteFailureDoesNotConcealOrClosePanel() {
        let trace = Trace()
        let writer = FakeHistoryPasteboardWriter(changeCount: 7, trace: trace, shouldFail: true)
        let dispatcher = FakePasteCommandDispatcher(trace: trace, result: true)
        let executor = makeExecutor(writer: writer, dispatcher: dispatcher, register: { _ in })
        var result: Result<Void, HistoryPasteFailure>?

        executor.paste(
            entry: sampleEntry,
            target: FakeHistoryPasteTarget(trace: trace),
            concealPanel: { trace.events.append("conceal") },
            closePanel: { trace.events.append("close") }
        ) {
            result = $0
        }

        XCTAssertEqual(result?.failureValue, .pasteboardWriteFailed)
        XCTAssertEqual(trace.events, ["write"])
    }

    func testActivationFailureKeepsHistoryAvailableAndDoesNotDispatch() {
        let trace = Trace()
        let writer = FakeHistoryPasteboardWriter(changeCount: 8, trace: trace)
        let dispatcher = FakePasteCommandDispatcher(trace: trace, result: true)
        let executor = makeExecutor(writer: writer, dispatcher: dispatcher, register: { _ in })
        let target = FakeHistoryPasteTarget(trace: trace, activateResult: false)
        var result: Result<Void, HistoryPasteFailure>?
        var completionCount = 0

        executor.paste(
            entry: sampleEntry,
            target: target,
            concealPanel: { trace.events.append("conceal") },
            closePanel: { trace.events.append("close") }
        ) {
            result = $0
            completionCount += 1
        }

        XCTAssertEqual(result?.failureValue, .targetUnavailable)
        XCTAssertEqual(trace.events, ["write", "conceal", "activate"])
        XCTAssertEqual(writer.writtenTexts.count, 1)
        XCTAssertEqual(completionCount, 1)
    }

    func testDispatchFailureIsVisibleAndDoesNotDeleteTheEntry() {
        let trace = Trace()
        let writer = FakeHistoryPasteboardWriter(changeCount: 9, trace: trace)
        let dispatcher = FakePasteCommandDispatcher(trace: trace, result: false)
        let executor = makeExecutor(writer: writer, dispatcher: dispatcher, register: { _ in })
        var result: Result<Void, HistoryPasteFailure>?

        executor.paste(
            entry: sampleEntry,
            target: FakeHistoryPasteTarget(trace: trace),
            concealPanel: { trace.events.append("conceal") },
            closePanel: { trace.events.append("close") }
        ) { result = $0 }

        XCTAssertEqual(result?.failureValue, .commandDispatchFailed)
        XCTAssertEqual(trace.events, ["write", "conceal", "activate", "close", "dispatch"])
    }

    func testPasteWaitsForTargetToBecomeActiveBeforeDispatching() {
        let trace = Trace()
        let writer = FakeHistoryPasteboardWriter(changeCount: 10, trace: trace)
        let dispatcher = FakePasteCommandDispatcher(trace: trace, result: true)
        let target = FakeHistoryPasteTarget(trace: trace, activeResults: [false, true])
        let executor = makeExecutor(writer: writer, dispatcher: dispatcher, register: { _ in })
        var result: Result<Void, HistoryPasteFailure>?

        executor.paste(
            entry: sampleEntry,
            target: target,
            concealPanel: { trace.events.append("conceal") },
            closePanel: { trace.events.append("close") }
        ) {
            result = $0
        }

        XCTAssertNoThrow(try result?.get())
        XCTAssertEqual(trace.events, ["write", "conceal", "activate", "close", "dispatch"])
        XCTAssertEqual(target.activeCheckCount, 2)
    }

    func testPasteFailsWithoutDispatchWhenTargetNeverBecomesActive() {
        let trace = Trace()
        let writer = FakeHistoryPasteboardWriter(changeCount: 11, trace: trace)
        let dispatcher = FakePasteCommandDispatcher(trace: trace, result: true)
        let target = FakeHistoryPasteTarget(trace: trace, activeResults: [false, false, false])
        let executor = makeExecutor(writer: writer, dispatcher: dispatcher, register: { _ in })
        var result: Result<Void, HistoryPasteFailure>?
        var completionCount = 0

        executor.paste(
            entry: sampleEntry,
            target: target,
            concealPanel: { trace.events.append("conceal") },
            closePanel: { trace.events.append("close") }
        ) {
            result = $0
            completionCount += 1
        }

        XCTAssertEqual(result?.failureValue, .targetUnavailable)
        XCTAssertEqual(trace.events, ["write", "conceal", "activate"])
        XCTAssertEqual(target.activeCheckCount, 3)
        XCTAssertEqual(writer.writtenTexts.count, 1)
        XCTAssertEqual(completionCount, 1)
    }

    func testCancelCanReactivateCapturedTargetWithoutWritingOrDispatching() {
        let trace = Trace()
        let target = FakeHistoryPasteTarget(trace: trace)

        XCTAssertTrue(HistoryFocusRestorer.returnToCapturedTarget(target))

        XCTAssertEqual(trace.events, ["activate"])
    }

    func testRepeatedPasteIsRejectedWhileTargetActivationIsPending() {
        let trace = Trace()
        let writer = FakeHistoryPasteboardWriter(changeCount: 12, trace: trace)
        let target = FakeHistoryPasteTarget(trace: trace, activeResults: [false])
        let dispatcher = FakePasteCommandDispatcher(trace: trace, result: true)
        var scheduled: [() -> Void] = []
        let executor = HistoryPasteExecutor(
            permissionService: FakeHistoryPermissionService(state: .granted),
            pasteboardWriter: writer,
            registerSelfWrite: { _ in },
            commandDispatcher: dispatcher,
            scheduleAfterActivation: { _, work in scheduled.append(work) },
            observeTargetActivation: { FakeActivationObservation(action: $0) }
        )

        let firstStarted = executor.paste(
            entry: sampleEntry,
            target: target,
            concealPanel: { trace.events.append("conceal") },
            closePanel: { trace.events.append("close") },
            completion: { _ in }
        )
        let repeatedStarted = executor.paste(
            entry: sampleEntry,
            target: target,
            concealPanel: { trace.events.append("conceal") },
            closePanel: { trace.events.append("close") },
            completion: { _ in }
        )

        XCTAssertTrue(firstStarted)
        XCTAssertFalse(repeatedStarted)
        XCTAssertTrue(executor.hasActivePaste)
        XCTAssertEqual(writer.writtenTexts.count, 1)
        XCTAssertEqual(scheduled.count, 1)
        XCTAssertEqual(trace.events, ["write", "conceal", "activate"])

        executor.cancelActivePaste()
        XCTAssertFalse(executor.hasActivePaste)
    }

    func testActivationNotificationDispatchesBeforeScheduledFallback() {
        let trace = Trace()
        let writer = FakeHistoryPasteboardWriter(changeCount: 13, trace: trace)
        let target = FakeHistoryPasteTarget(trace: trace, activeResults: [false, true])
        let dispatcher = FakePasteCommandDispatcher(trace: trace, result: true)
        let observation = FakeActivationObservation()
        var scheduled: [() -> Void] = []
        var result: Result<Void, HistoryPasteFailure>?
        let executor = HistoryPasteExecutor(
            permissionService: FakeHistoryPermissionService(state: .granted),
            pasteboardWriter: writer,
            registerSelfWrite: { _ in },
            commandDispatcher: dispatcher,
            scheduleAfterActivation: { _, work in scheduled.append(work) },
            observeTargetActivation: {
                observation.action = $0
                return observation
            }
        )

        executor.paste(
            entry: sampleEntry,
            target: target,
            concealPanel: { trace.events.append("conceal") },
            closePanel: { trace.events.append("close") },
            completion: { result = $0 }
        )
        XCTAssertNil(result)
        XCTAssertEqual(scheduled.count, 1)

        observation.fire()

        XCTAssertNoThrow(try result?.get())
        XCTAssertEqual(trace.events, ["write", "conceal", "activate", "close", "dispatch"])
        XCTAssertFalse(executor.hasActivePaste)
    }

    private var sampleEntry: HistoryEntry {
        HistoryEntry(id: UUID(), text: "safe fixture", activityAt: .now)
    }

    private func makeExecutor(
        permission: AccessibilityPermissionState = .granted,
        writer: FakeHistoryPasteboardWriter,
        dispatcher: FakePasteCommandDispatcher,
        activationWaitPolicy: HistoryTargetActivationWaitPolicy = HistoryTargetActivationWaitPolicy(
            retryInterval: 0.1,
            timeout: 0.2
        ),
        register: @escaping (Int) -> Void
    ) -> HistoryPasteExecutor {
        let clock = FakeActivationClock()
        return HistoryPasteExecutor(
            permissionService: FakeHistoryPermissionService(state: permission),
            pasteboardWriter: writer,
            registerSelfWrite: register,
            commandDispatcher: dispatcher,
            activationWaitPolicy: activationWaitPolicy,
            scheduleAfterActivation: { interval, work in
                clock.advance(by: interval)
                work()
            },
            observeTargetActivation: { FakeActivationObservation(action: $0) },
            now: { clock.now }
        )
    }
}

@MainActor
final class PanelActivationPresenterTests: XCTestCase {
    func testUsesStrongUserInitiatedActivationAndRunsCompletionWhenActive() {
        let application = FakeQipliApplication(activeResults: [false, true])
        let presenter = PanelActivationPresenter(
            application: application,
            scheduleNextMainRunLoop: { $0() }
        )
        var completionCount = 0

        presenter.presentImmediatelyThenWhenActive(
            requiresStrongUserActivation: true,
            present: {},
            whenActive: {
                completionCount += 1
            }
        )

        XCTAssertEqual(application.strongActivationRequestCount, 1)
        XCTAssertEqual(application.activationRequestCount, 0)
        XCTAssertEqual(application.activeCheckCount, 2)
        XCTAssertEqual(completionCount, 1)
    }

    func testRegularPanelUsesCooperativeActivation() {
        let application = FakeQipliApplication(activeResults: [true])
        let presenter = PanelActivationPresenter(
            application: application,
            scheduleNextMainRunLoop: { $0() }
        )

        presenter.presentImmediatelyThenWhenActive(
            requiresStrongUserActivation: false,
            present: {},
            whenActive: {}
        )

        XCTAssertEqual(application.activationRequestCount, 1)
        XCTAssertEqual(application.strongActivationRequestCount, 0)
    }

    func testExhaustedActivationStillRunsImmediatePresentationAndSkipsActiveCompletion() {
        let application = FakeQipliApplication(activeResults: [false, false, false])
        let presenter = PanelActivationPresenter(
            application: application,
            scheduleNextMainRunLoop: { $0() }
        )
        var presentationCount = 0
        var completionCount = 0

        presenter.presentImmediatelyThenWhenActive(
            requiresStrongUserActivation: true,
            present: { presentationCount += 1 },
            whenActive: { completionCount += 1 }
        )

        XCTAssertEqual(application.strongActivationRequestCount, 1)
        XCTAssertEqual(application.activationRequestCount, 0)
        XCTAssertEqual(application.activeCheckCount, 3)
        XCTAssertEqual(presentationCount, 1)
        XCTAssertEqual(completionCount, 0)
    }
}

final class HistoryKeyboardGuidePresentationTests: XCTestCase {
    func testGuideShowsNavigationAndPasteKeysWithOneAccessibleInstruction() {
        XCTAssertEqual(
            HistoryKeyboardGuidePresentation.navigation,
            HistoryKeyboardGuideItem(
                symbolSystemNames: ["arrow.up", "arrow.down"],
                title: "Navigation"
            )
        )
        XCTAssertEqual(
            HistoryKeyboardGuidePresentation.paste,
            HistoryKeyboardGuideItem(symbolSystemNames: ["return"], title: "Paste")
        )
        XCTAssertEqual(
            HistoryKeyboardGuidePresentation.accessibilityLabel,
            "Use Up and Down Arrow to navigate. Press Return to paste."
        )
    }
}

@MainActor
final class HistoryPanelIntentTests: XCTestCase {
    func testKeyboardIntentsDriveSelectionPasteAndClose() {
        let entry = makeEntry("fixture", offset: 1)
        let trace = HistoryPanelIntentTrace(selectedEntryID: entry.id)
        let executor = makeExecutor(trace: trace)

        executor.execute(.moveSelection(by: 1))
        executor.execute(.paste(entry))
        executor.execute(.close)

        XCTAssertEqual(trace.selectionOffsets, [1])
        XCTAssertEqual(trace.pastedEntries, [entry])
        XCTAssertEqual(trace.closeCount, 1)
    }

    func testWindowKeyboardDownThenEnterPastesTheMovedSelectionSnapshot() async {
        let first = makeEntry("first fixture", offset: 2)
        let second = makeEntry("second fixture", offset: 1)
        let viewModel = HistoryViewModel(
            service: HistoryService(store: InMemoryHistoryStore(entries: [first, second]))
        )
        await viewModel.reload()
        viewModel.prepareForPresentation()
        var pastedEntries: [HistoryEntry] = []
        var closeCount = 0
        let executor = HistoryPanelKeyActionExecutor(
            moveSelection: viewModel.moveSelection,
            selectedEntry: { viewModel.selectedEntry },
            pasteEntry: { pastedEntries.append($0) },
            close: { closeCount += 1 }
        )

        XCTAssertTrue(executor.execute(.moveSelection(by: 1)))
        XCTAssertEqual(viewModel.selectedEntryID, second.id)
        XCTAssertTrue(executor.execute(.pasteSelection))

        viewModel.select(id: first.id)
        XCTAssertEqual(pastedEntries.map(\.id), [second.id])
        XCTAssertEqual(closeCount, 0)
    }

    func testDoubleClickSelectsExactIDThenPastesOnceWhenAllowed() {
        let entry = makeEntry("fixture", offset: 1)
        let trace = HistoryPanelIntentTrace(selectedEntryID: nil)
        let executor = makeExecutor(trace: trace)

        executor.execute(.selectAndPaste(entry))

        XCTAssertEqual(trace.selectedIDs, [entry.id])
        XCTAssertEqual(trace.pastedEntries, [entry])
    }

    func testDoubleClickDoesNotPasteWhenPermissionIsUnavailable() {
        let entry = makeEntry("fixture", offset: 1)
        let trace = HistoryPanelIntentTrace(selectedEntryID: nil, canPaste: false)

        makeExecutor(trace: trace).execute(.selectAndPaste(entry))

        XCTAssertEqual(trace.selectedIDs, [entry.id])
        XCTAssertTrue(trace.pastedEntries.isEmpty)
    }

    func testPasteIntentCarriesExactFilteredEntryInsteadOfReadingPreviousSelection() {
        let previous = makeEntry("previous fixture", offset: 2)
        let filtered = makeEntry("filtered fixture", offset: 1)
        let trace = HistoryPanelIntentTrace(selectedEntryID: previous.id)

        makeExecutor(trace: trace).execute(.paste(filtered))

        XCTAssertEqual(trace.selectedEntryID, previous.id)
        XCTAssertEqual(trace.pastedEntries, [filtered])
    }

    func testDeleteDoesNotSelectOrPaste() {
        let entry = makeEntry("fixture", offset: 1)
        let trace = HistoryPanelIntentTrace(selectedEntryID: nil)

        makeExecutor(trace: trace).execute(.delete(entry))

        XCTAssertEqual(trace.deletedIDs, [entry.id])
        XCTAssertTrue(trace.selectedIDs.isEmpty)
        XCTAssertTrue(trace.pastedEntries.isEmpty)
    }

    func testEmptyQueryAdmitsTheExactSelectedEntryForSearchDelete() {
        let selected = makeEntry("selected fixture", offset: 1)
        let other = makeEntry("other fixture", offset: 2)

        let admitted = HistorySearchDeleteAdmission.selectedEntry(
            query: "",
            state: .list([selected, other]),
            selectedEntry: selected
        )

        XCTAssertEqual(admitted?.id, selected.id)
    }

    func testNonEmptyQueryNoSelectionAndNonListStatePassSearchDeleteThrough() {
        let entry = makeEntry("fixture", offset: 1)

        XCTAssertNil(HistorySearchDeleteAdmission.selectedEntry(
            query: "f",
            state: .list([entry]),
            selectedEntry: entry
        ))
        XCTAssertNil(HistorySearchDeleteAdmission.selectedEntry(
            query: "",
            state: .list([entry]),
            selectedEntry: nil
        ))
        XCTAssertNil(HistorySearchDeleteAdmission.selectedEntry(
            query: "",
            state: .empty,
            selectedEntry: entry
        ))
    }

    func testLocalDeleteMonitorAdmissionRequiresFocusedKeyWindowAndPhysicalUnmodifiedNonrepeatDelete() {
        let entry = makeEntry("selected fixture", offset: 1)
        let sharedContext: (query: String, state: HistoryViewState, selectedEntry: HistoryEntry?) = (
            "",
            .list([entry]),
            entry
        )
        let backward = HistorySearchDeleteEvent(key: .backward, hasDisallowedModifiers: false, isRepeat: false)
        let forward = HistorySearchDeleteEvent(key: .forward, hasDisallowedModifiers: false, isRepeat: false)

        XCTAssertEqual(HistorySearchDeleteAdmission.selectedEntry(
            for: backward,
            isSearchFocused: true,
            isEventInKeyWindow: true,
            query: sharedContext.query,
            state: sharedContext.state,
            selectedEntry: sharedContext.selectedEntry
        )?.id, entry.id)
        XCTAssertEqual(HistorySearchDeleteAdmission.selectedEntry(
            for: forward,
            isSearchFocused: true,
            isEventInKeyWindow: true,
            query: sharedContext.query,
            state: sharedContext.state,
            selectedEntry: sharedContext.selectedEntry
        )?.id, entry.id)

        let rejectedEvents = [
            HistorySearchDeleteEvent(key: .backward, hasDisallowedModifiers: true, isRepeat: false),
            HistorySearchDeleteEvent(key: .forward, hasDisallowedModifiers: false, isRepeat: true),
            HistorySearchDeleteEvent(key: .other, hasDisallowedModifiers: false, isRepeat: false)
        ]
        for event in rejectedEvents {
            XCTAssertNil(HistorySearchDeleteAdmission.selectedEntry(
                for: event,
                isSearchFocused: true,
                isEventInKeyWindow: true,
                query: sharedContext.query,
                state: sharedContext.state,
                selectedEntry: sharedContext.selectedEntry
            ))
        }

        XCTAssertNil(HistorySearchDeleteAdmission.selectedEntry(
            for: backward,
            isSearchFocused: false,
            isEventInKeyWindow: true,
            query: sharedContext.query,
            state: sharedContext.state,
            selectedEntry: sharedContext.selectedEntry
        ))
        XCTAssertNil(HistorySearchDeleteAdmission.selectedEntry(
            for: backward,
            isSearchFocused: true,
            isEventInKeyWindow: false,
            query: sharedContext.query,
            state: sharedContext.state,
            selectedEntry: sharedContext.selectedEntry
        ))
    }

    func testPhysicalDeleteEventNormalizationAcceptsCapsFnAndNumericPadButRejectsShortcutModifiers() throws {
        let backward = HistorySearchDeleteEvent(event: try makeKeyEvent(keyCode: 51))
        let forward = HistorySearchDeleteEvent(event: try makeKeyEvent(keyCode: 117))
        let other = HistorySearchDeleteEvent(event: try makeKeyEvent(keyCode: 0))
        let modified = HistorySearchDeleteEvent(event: try makeKeyEvent(
            keyCode: 51,
            modifierFlags: [.command, .capsLock, .function, .numericPad]
        ))
        let acceptedFlags = HistorySearchDeleteEvent(event: try makeKeyEvent(
            keyCode: 51,
            modifierFlags: [.capsLock, .function, .numericPad]
        ))

        XCTAssertEqual(backward.key, .backward)
        XCTAssertEqual(forward.key, .forward)
        XCTAssertEqual(other.key, .other)
        XCTAssertFalse(acceptedFlags.hasDisallowedModifiers)
        XCTAssertTrue(modified.hasDisallowedModifiers)
    }

    func testWindowKeyboardAdmissionRoutesExactKeysAndKeepsNativeModifiedInput() {
        XCTAssertEqual(HistoryPanelKeyAdmission.action(
            for: HistoryPanelKeyEvent(key: .up, hasDisallowedModifiers: false, isRepeat: true),
            isEventInKeyHistoryWindow: true
        ), .moveSelection(by: -1))
        XCTAssertEqual(HistoryPanelKeyAdmission.action(
            for: HistoryPanelKeyEvent(key: .down, hasDisallowedModifiers: false, isRepeat: true),
            isEventInKeyHistoryWindow: true
        ), .moveSelection(by: 1))
        XCTAssertEqual(HistoryPanelKeyAdmission.action(
            for: HistoryPanelKeyEvent(key: .enter, hasDisallowedModifiers: false, isRepeat: false),
            isEventInKeyHistoryWindow: true
        ), .pasteSelection)
        XCTAssertEqual(HistoryPanelKeyAdmission.action(
            for: HistoryPanelKeyEvent(key: .escape, hasDisallowedModifiers: false, isRepeat: false),
            isEventInKeyHistoryWindow: true
        ), .close)
        XCTAssertNil(HistoryPanelKeyAdmission.action(
            for: HistoryPanelKeyEvent(key: .enter, hasDisallowedModifiers: false, isRepeat: true),
            isEventInKeyHistoryWindow: true
        ))
        XCTAssertNil(HistoryPanelKeyAdmission.action(
            for: HistoryPanelKeyEvent(key: .up, hasDisallowedModifiers: true, isRepeat: false),
            isEventInKeyHistoryWindow: true
        ))
        XCTAssertNil(HistoryPanelKeyAdmission.action(
            for: HistoryPanelKeyEvent(key: .down, hasDisallowedModifiers: false, isRepeat: false),
            isEventInKeyHistoryWindow: false
        ))
    }

    func testPassiveDismissHidesOnlyWhileExplicitDismissCancelsAndRestoresFocus() {
        var events: [String] = []
        let executor = HistoryPanelDismissalExecutor(
            cancelPaste: { events.append("cancel") },
            hide: { events.append("hide") },
            restoreFocus: { events.append("restore") }
        )

        executor.execute(.passive)
        XCTAssertEqual(events, ["hide"])

        events.removeAll()
        executor.execute(.explicit)
        XCTAssertEqual(events, ["cancel", "hide", "restore"])
    }

    func testOutsideClickAdmissionAppliesOnlyToVisibleHistoryAndOutsideCoordinates() {
        XCTAssertTrue(HistoryPanelOutsideClickAdmission.shouldDismiss(
            isPanelVisible: true,
            isInsideHistoryPanel: false
        ))
        XCTAssertFalse(HistoryPanelOutsideClickAdmission.shouldDismiss(
            isPanelVisible: true,
            isInsideHistoryPanel: true
        ))
        XCTAssertFalse(HistoryPanelOutsideClickAdmission.shouldDismiss(
            isPanelVisible: false,
            isInsideHistoryPanel: false
        ))
    }

    func testHistoryPresentationOrdersCachedPanelBeforeCaptureDrain() {
        var events: [String] = []
        HistoryPresentationExecutor(
            pollPasteboard: { events.append("poll") },
            presentCachedHistory: { events.append("present") },
            startCaptureDrain: { events.append("drain") }
        )
        .execute()

        XCTAssertEqual(events, ["poll", "present", "drain"])
    }

    func testHistoryTableBridgeAppliesSelectionSynchronously() {
        let id = UUID()
        let target = HistoryTableSelectionTargetSpy()
        let bridge = HistoryTableInteractionBridge()
        bridge.attach(target)

        bridge.applySelection(id: id)

        XCTAssertEqual(target.calls, [.init(id: id, resetViewport: false)])
    }

    func testHistoryTableBridgeForwardsEveryRapidSelectionWithoutCoalescing() {
        let ids = (0..<20).map { _ in UUID() }
        let target = HistoryTableSelectionTargetSpy()
        let bridge = HistoryTableInteractionBridge()
        bridge.attach(target)

        ids.forEach { bridge.applySelection(id: $0) }

        XCTAssertEqual(target.calls.map(\.id), ids)
        XCTAssertTrue(target.calls.allSatisfy { !$0.resetViewport })
    }

    func testHistoryTableBridgeResetsViewportInTheSameCall() {
        let id = UUID()
        let target = HistoryTableSelectionTargetSpy()
        let bridge = HistoryTableInteractionBridge()
        bridge.attach(target)

        bridge.applySelection(id: id, resetViewport: true)

        XCTAssertEqual(target.calls, [.init(id: id, resetViewport: true)])
    }

    func testHistoryTableBridgeAppliesFreshSnapshotBeforePresentation() {
        let entries = [makeEntry("first", offset: 2), makeEntry("second", offset: 1)]
        let target = HistoryTableSelectionTargetSpy()
        let bridge = HistoryTableInteractionBridge()
        bridge.attach(target)

        bridge.applySnapshot(
            entries: entries,
            revision: 7,
            selectedEntryID: entries[0].id,
            resetViewport: true
        )

        XCTAssertEqual(
            target.snapshotCalls,
            [.init(entryIDs: entries.map(\.id), revision: 7, selectedEntryID: entries[0].id, resetViewport: true)]
        )
    }

    private func makeKeyEvent(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags = [],
        isARepeat: Bool = false
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: isARepeat,
            keyCode: keyCode
        ))
    }

    private func makeEntry(_ text: String, offset: TimeInterval) -> HistoryEntry {
        HistoryEntry(id: UUID(), text: text, activityAt: Date.now.addingTimeInterval(offset))
    }

    private func makeExecutor(trace: HistoryPanelIntentTrace) -> HistoryPanelIntentExecutor {
        HistoryPanelIntentExecutor(
            moveSelection: { trace.selectionOffsets.append($0) },
            select: {
                trace.selectedIDs.append($0)
                trace.selectedEntryID = $0
            },
            canPaste: { trace.canPaste },
            pasteEntry: { trace.pastedEntries.append($0) },
            close: { trace.closeCount += 1 },
            delete: { trace.deletedIDs.append($0.id) }
        )
    }
}

@MainActor
private final class HistoryPanelIntentTrace {
    var selectedEntryID: UUID?
    var canPaste: Bool
    var selectionOffsets: [Int] = []
    var selectedIDs: [UUID] = []
    var pastedEntries: [HistoryEntry] = []
    var closeCount = 0
    var deletedIDs: [UUID] = []

    init(selectedEntryID: UUID?, canPaste: Bool = true) {
        self.selectedEntryID = selectedEntryID
        self.canPaste = canPaste
    }
}

private final class InMemoryHistoryStore: HistoryStoring {
    var entries: [HistoryEntry]
    var markUsedError: Error?
    var clearAllError: Error?
    private(set) var fetchCount = 0
    private(set) var operationNames: [String] = []
    private(set) var operationWasOnMainThread: [Bool] = []
    var onFetch: (() -> Void)?

    init(entries: [HistoryEntry] = [], markUsedError: Error? = nil) {
        self.entries = entries
        self.markUsedError = markUsedError
    }

    func fetchCurrent(since cutoff: Date) throws -> [HistoryEntry] {
        recordOperation("fetch")
        fetchCount += 1
        onFetch?()
        return entries
            .filter { $0.activityAt > cutoff }
            .sorted {
                if $0.activityAt != $1.activityAt {
                    return $0.activityAt > $1.activityAt
                }
                return $0.id.uuidString > $1.id.uuidString
            }
    }

    func create(text: String, activityAt: Date) throws -> HistoryEntry {
        recordOperation("create")
        let entry = HistoryEntry(id: UUID(), text: text, activityAt: activityAt)
        entries.append(entry)
        return entry
    }

    func markUsed(id: UUID, activityAt: Date) throws {
        recordOperation("markUsed")
        if let markUsedError { throw markUsedError }
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries[index]
        entries[index] = HistoryEntry(id: entry.id, text: entry.text, activityAt: activityAt)
    }

    func delete(id: UUID) throws {
        recordOperation("delete")
        entries.removeAll { $0.id == id }
    }

    func clearAll() throws {
        recordOperation("clearAll")
        if let clearAllError { throw clearAllError }
        entries = []
    }

    private func recordOperation(_ name: String) {
        operationNames.append(name)
        operationWasOnMainThread.append(Thread.isMainThread)
    }
}

private final class TestHistoryClock: HistoryClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

private final class FakeHistoryPermissionService: AccessibilityPermissionChecking {
    var state: AccessibilityPermissionState

    init(state: AccessibilityPermissionState) {
        self.state = state
    }

    func refresh() -> AccessibilityPermissionState { state }
    func requestAccess() -> AccessibilityPermissionState { state }
    func openSystemSettings() {}
}

private final class Trace {
    var events: [String] = []
}

private final class FakeActivationClock {
    var now = Date(timeIntervalSinceReferenceDate: 0)

    func advance(by interval: TimeInterval) {
        now.addTimeInterval(interval)
    }
}

private final class FakeActivationObservation: HistoryTargetActivationObserving {
    var action: (() -> Void)?
    private(set) var isInvalidated = false

    init(action: (() -> Void)? = nil) {
        self.action = action
    }

    func fire() {
        action?()
    }

    func invalidate() {
        isInvalidated = true
        action = nil
    }
}

private final class FakeHistoryPasteboardWriter: HistoryPasteboardWriting, TypedHistoryPasteboardWriting {
    let changeCount: Int
    let trace: Trace
    let shouldFail: Bool
    private(set) var writtenTexts: [String] = []
    private(set) var writtenPayloads: [HistoryPastePayload] = []

    init(changeCount: Int, trace: Trace, shouldFail: Bool = false) {
        self.changeCount = changeCount
        self.trace = trace
        self.shouldFail = shouldFail
    }

    func write(text: String) throws -> Int {
        trace.events.append("write")
        if shouldFail {
            throw HistoryPasteboardWriteError.unableToWriteText
        }
        writtenTexts.append(text)
        return changeCount
    }

    func write(payload: HistoryPastePayload) throws -> Int {
        trace.events.append("write")
        if shouldFail {
            throw HistoryPasteboardWriteError.unableToWriteText
        }
        writtenPayloads.append(payload)
        return changeCount
    }
}

private final class FakeHistoryPasteTarget: HistoryPasteTarget {
    let trace: Trace
    var isTerminated: Bool
    let activateResult: Bool
    private var activeResults: [Bool]
    private(set) var activeCheckCount = 0

    init(
        trace: Trace,
        terminated: Bool = false,
        activateResult: Bool = true,
        activeResults: [Bool] = [true]
    ) {
        self.trace = trace
        isTerminated = terminated
        self.activateResult = activateResult
        self.activeResults = activeResults
    }

    var isActive: Bool {
        activeCheckCount += 1
        if activeResults.count > 1 {
            return activeResults.removeFirst()
        }
        return activeResults.first ?? false
    }

    func activate() -> Bool {
        trace.events.append("activate")
        return activateResult
    }
}

private final class FakePasteCommandDispatcher: TaggedPasteCommandDispatching {
    let trace: Trace
    let result: Bool

    init(trace: Trace, result: Bool) {
        self.trace = trace
        self.result = result
    }

    func postTaggedCommandV() -> Bool {
        trace.events.append("dispatch")
        return result
    }
}

@MainActor
private final class FakeQipliApplication: QipliApplicationActivating {
    private var activeResults: [Bool]
    private(set) var activationRequestCount = 0
    private(set) var strongActivationRequestCount = 0
    private(set) var activeCheckCount = 0

    init(activeResults: [Bool]) {
        self.activeResults = activeResults
    }

    var isActive: Bool {
        activeCheckCount += 1
        if activeResults.count > 1 {
            return activeResults.removeFirst()
        }
        return activeResults.first ?? false
    }

    func requestActivation() {
        activationRequestCount += 1
    }

    func requestUserInitiatedActivation() {
        strongActivationRequestCount += 1
    }
}

@MainActor
private final class HistoryTableSelectionTargetSpy: HistoryTableSelectionApplying {
    struct Call: Equatable {
        let id: UUID?
        let resetViewport: Bool
    }

    private(set) var calls: [Call] = []
    struct SnapshotCall: Equatable {
        let entryIDs: [UUID]
        let revision: Int
        let selectedEntryID: UUID?
        let resetViewport: Bool
    }
    private(set) var snapshotCalls: [SnapshotCall] = []

    func applySelection(id: UUID?, resetViewport: Bool) {
        calls.append(Call(id: id, resetViewport: resetViewport))
    }

    func applySnapshot(
        entries: [HistoryEntry],
        revision: Int,
        selectedEntryID: UUID?,
        resetViewport: Bool
    ) {
        snapshotCalls.append(SnapshotCall(
            entryIDs: entries.map(\.id),
            revision: revision,
            selectedEntryID: selectedEntryID,
            resetViewport: resetViewport
        ))
    }
}

private extension Result where Success == Void, Failure == HistoryPasteFailure {
    var failureValue: HistoryPasteFailure? {
        guard case let .failure(failure) = self else { return nil }
        return failure
    }
}
