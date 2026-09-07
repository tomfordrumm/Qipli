import Foundation

enum HistoryViewState: Equatable {
    case loading
    case empty
    case list([HistoryOccurrenceDescriptor])
    case error
}

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published private(set) var state: HistoryViewState = .loading
    @Published private(set) var query = ""
    @Published private(set) var selectedEntryID: UUID?
    @Published private(set) var pasteFailure: HistoryPasteFailure?
    @Published private(set) var isPasteInProgress = false
    @Published private(set) var searchFocusRequestID = 0
    @Published private(set) var isSearchInProgress = false
    @Published private(set) var isLoadingMore = false
    var thumbnailDataByEntryID: [UUID: Data] { thumbnailCache.values }
    @Published private(set) var thumbnailUpdateRevisionsByEntryID: [UUID: Int] = [:]
    @Published private(set) var captureNotice: String?
    private(set) var visibleSnapshotRevision = 0
    private var thumbnailCache = HistoryThumbnailCache(byteLimit: HistoryImageStoragePolicy.production.thumbnailCacheBytes)
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var thumbnailTasks: [UUID: Task<Void, Never>] = [:]
    private var thumbnailGeneration = 0
    private var thumbnailUpdateRevision = 0

    private let service: SerializedHistoryService
    private let searchDebounceNanoseconds: UInt64
    private let now: () -> Date
    /// Only bounded descriptors for requested pages cross onto the main actor.
    private var loadedDescriptors: [HistoryOccurrenceDescriptor] = []
    private var pageCursor: HistoryPageCursor?
    private var hasMorePages = false
    private var hasLoadedSnapshot = false
    private var hasUnpublishedSnapshotChanges = false
    private var searchGeneration = 0
    private var pagingGeneration = 0
    private var searchTask: Task<Void, Never>?
    private var pageTask: Task<Void, Never>?
    private var pageTaskToken: UUID?

    init(
        service: HistoryService,
        searchDebounceNanoseconds: UInt64 = 100_000_000,
        now: @escaping () -> Date = Date.init
    ) {
        self.service = SerializedHistoryService(service: service)
        self.searchDebounceNanoseconds = searchDebounceNanoseconds
        self.now = now
        let pressure = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        pressure.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in self?.releaseThumbnailCache() }
        }
        pressure.resume()
        memoryPressureSource = pressure
    }

    deinit { memoryPressureSource?.cancel() }

    func thumbnailData(for entryID: UUID) -> Data? {
        thumbnailCache.value(for: entryID)
    }

    func releaseThumbnailCache() {
        invalidateThumbnailTasks()
        thumbnailCache.removeAll()
        thumbnailUpdateRevisionsByEntryID = [:]
    }

    /// Metadata-only projection for transient card presentations. Exact text
    /// remains behind the selected-paste lookup boundary.
    var visibleDescriptors: [HistoryOccurrenceDescriptor] {
        guard case let .list(descriptors) = state else { return [] }
        return descriptors
    }

    func prepareForPresentation() {
        let removedExpiredEntries = discardExpiredSnapshotEntries()
        let wasFiltered = !query.isEmpty
        if wasFiltered {
            query = ""
        }
        if pasteFailure != nil {
            pasteFailure = nil
        }
        if isPasteInProgress {
            isPasteInProgress = false
        }
        guard hasLoadedSnapshot, state != .error else { return }

        if removedExpiredEntries || wasFiltered || hasUnpublishedSnapshotChanges || !hasCurrentUnfilteredState {
            if wasFiltered {
                schedulePagedSearch(selectFirstResult: true, debounce: false)
            } else {
                publish(descriptors: loadedDescriptors, selectFirstResult: true)
            }
        } else {
            let firstEntryID = loadedDescriptors.first?.id
            if selectedEntryID != firstEntryID {
                selectedEntryID = firstEntryID
            }
        }
    }

    func requestSearchFocus() {
        searchFocusRequestID &+= 1
    }

    func reload(selectFirstResult: Bool = false) async {
        cancelSearch()
        invalidateThumbnailTasks()
        pagingGeneration &+= 1
        pageTask?.cancel()
        captureNotice = nil
        state = .loading
        do {
            loadedDescriptors = []
            pageCursor = nil
            hasMorePages = false
            let page = query.isEmpty
                ? try await service.page()
                : try await service.searchPage(query: query)
            pageCursor = page.nextCursor
            hasMorePages = page.hasMore
            loadedDescriptors = page.descriptors
            hasLoadedSnapshot = true
            publish(descriptors: page.descriptors, selectFirstResult: selectFirstResult)
            await waitForPendingSearch()
        } catch {
            cancelSearch()
            state = .error
            selectedEntryID = nil
        }
    }

    func updateQuery(_ query: String) {
        guard self.query != query else { return }
        self.query = query
        pasteFailure = nil
        schedulePagedSearch(selectFirstResult: true, debounce: true)
    }

    /// Requests exactly one next page. The table calls this when its viewport
    /// reaches the end; the generation/cursor guards make repeated scroll
    /// notifications harmless.
    func loadMore() async {
        if isLoadingMore {
            await pageTask?.value
            return
        }
        guard hasLoadedSnapshot,
              hasMorePages,
              !isLoadingMore,
              let cursor = pageCursor
        else { return }

        let generation = pagingGeneration
        let requestedQuery = query
        let pageTaskToken = UUID()
        isLoadingMore = true
        self.pageTaskToken = pageTaskToken
        let task = Task { @MainActor [weak self] in
            defer { self?.finishPageTask(pageTaskToken) }
            await self?.performLoadMore(
                after: cursor,
                query: requestedQuery,
                generation: generation
            )
        }
        pageTask = task
        await task.value
    }

    private func performLoadMore(
        after cursor: HistoryPageCursor,
        query requestedQuery: String,
        generation: Int
    ) async {
        guard !Task.isCancelled else { return }
        do {
            let page = requestedQuery.isEmpty
                ? try await service.page(after: cursor)
                : try await service.searchPage(query: requestedQuery, after: cursor)
            guard !Task.isCancelled,
                  generation == pagingGeneration,
                  requestedQuery == query
            else { return }
            let nextDescriptors = page.descriptors
            loadedDescriptors.append(contentsOf: nextDescriptors)
            pageCursor = page.nextCursor
            hasMorePages = page.hasMore && !nextDescriptors.isEmpty
            publish(descriptors: loadedDescriptors, selectFirstResult: false)
        } catch {
            // Keep the already visible page. A later scroll can retry the same
            // cursor without claiming that existing History disappeared.
        }
    }

    private func finishPageTask(_ token: UUID) {
        guard pageTaskToken == token else { return }
        pageTaskToken = nil
        pageTask = nil
        isLoadingMore = false
    }

    func moveSelection(by offset: Int) {
        let descriptors = visibleDescriptors
        guard !descriptors.isEmpty else {
            if selectedEntryID != nil {
                selectedEntryID = nil
            }
            return
        }
        let currentIndex = selectedEntryID.flatMap { id in descriptors.firstIndex { $0.id == id } } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), descriptors.count - 1)
        let nextID = descriptors[nextIndex].id
        guard selectedEntryID != nextID else { return }
        selectedEntryID = nextID
    }

    func select(id: UUID) {
        guard visibleDescriptors.contains(where: { $0.id == id }) else { return }
        guard selectedEntryID != id else { return }
        selectedEntryID = id
        pasteFailure = nil
    }

    func recordPasteFailure(_ failure: HistoryPasteFailure) {
        pasteFailure = failure
    }

    /// Materializes one exact occurrence only when the presentation has
    /// committed to a paste action. The shelf itself receives descriptors.
    func entryForPaste(id: UUID) async -> Result<HistoryEntry, HistoryPasteFailure> {
        do {
            guard let entry = try await service.entry(id: id) else {
                return .failure(.entryUnavailable)
            }
            return .success(entry)
        } catch {
            return .failure(.entryUnavailable)
        }
    }

    func recordCaptureRejection(_ message: String) {
        captureNotice = message
    }

    func clearPasteFailure() {
        pasteFailure = nil
    }

    func beginPaste() {
        guard !isPasteInProgress else { return }
        pasteFailure = nil
        isPasteInProgress = true
    }

    func endPaste() {
        guard isPasteInProgress else { return }
        isPasteInProgress = false
    }

    /// Paste dispatch already succeeded when this is called. A recency persistence
    /// failure is intentionally non-fatal: it must not report a false paste failure
    /// or cause a second dispatch. The durable snapshot is updated immediately,
    /// but the visible snapshot is intentionally left untouched. Publishing recency
    /// while a reusable panel is closing can visibly move the selected row to index zero.
    func markUsedAfterSuccessfulPaste(id: UUID) async {
        pagingGeneration &+= 1
        do {
            let activityAt = try await service.markUsed(id: id)
            guard let index = loadedDescriptors.firstIndex(where: { $0.id == id }) else { return }
            let previous = loadedDescriptors.remove(at: index)
            let updated = HistoryOccurrenceDescriptor(
                id: previous.id,
                activityAt: activityAt,
                searchRank: previous.searchRank,
                textPreview: previous.textPreview,
                representations: previous.representations,
                imageMetadata: previous.imageMetadata,
                referenceMetadata: previous.referenceMetadata
            )
            let insertionIndex = loadedDescriptors.firstIndex(where: { Self.isNewer(updated, than: $0) })
                ?? loadedDescriptors.endIndex
            loadedDescriptors.insert(updated, at: insertionIndex)

            if hasMorePages {
                let previousSearchRank = pageCursor?.searchRank
                pageCursor = loadedDescriptors.last.map {
                    HistoryPageCursor(
                        activityAt: $0.activityAt,
                        id: $0.id,
                        searchRank: $0.searchRank ?? previousSearchRank
                    )
                }
            }
            hasUnpublishedSnapshotChanges = true
        } catch {
            // Paste already succeeded. Keep the last durable snapshot and do not
            // turn a recency-only persistence failure into a false paste failure.
        }
    }

    /// Captures first so optional consumers, such as Paste Stack collection, can
    /// safely reference the durable History occurrence rather than creating a
    /// separate in-memory-only value.
    @discardableResult
    func recordExternalCapture(_ capture: HistoryCapture) async -> HistoryEntry? {
        pagingGeneration &+= 1
        do {
            guard let result = try await service.capture(capture) else { return nil }
            captureNotice = result.notice
            let entry = result.entry
            let descriptor = Self.descriptor(from: entry)
            loadedDescriptors.removeAll { $0.id == entry.id }
            let insertionIndex = loadedDescriptors.firstIndex(where: { Self.isNewer(descriptor, than: $0) }) ?? loadedDescriptors.endIndex
            loadedDescriptors.insert(descriptor, at: insertionIndex)

            if loadedDescriptors.count > HistoryService.pageSize {
                loadedDescriptors.removeLast()
                hasMorePages = true
                pageCursor = loadedDescriptors.last.map {
                    HistoryPageCursor(activityAt: $0.activityAt, id: $0.id)
                }
            }
            hasLoadedSnapshot = true
            if query.isEmpty {
                publish(descriptors: loadedDescriptors, selectFirstResult: false)
            } else {
                schedulePagedSearch(selectFirstResult: true, debounce: false)
            }
            return entry
        } catch {
            captureNotice = (error as? LocalizedError)?.errorDescription ?? capture.failureMessage
            if case .text = capture {
                cancelSearch()
                state = .error
            }
            return nil
        }
    }

    func requestThumbnail(for entry: HistoryEntry) {
        requestThumbnail(forEntryID: entry.id, isImage: entry.isImageEntry)
    }

    func requestThumbnail(forEntryID entryID: UUID) {
        let isImage = visibleDescriptors.first(where: { $0.id == entryID })?.representations.contains {
            $0.kind == .inlineImage
        } == true
        requestThumbnail(forEntryID: entryID, isImage: isImage)
    }

    private func requestThumbnail(forEntryID entryID: UUID, isImage: Bool) {
        guard isImage,
              thumbnailCache.value(for: entryID) == nil,
              thumbnailTasks[entryID] == nil
        else { return }
        let generation = thumbnailGeneration
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.thumbnailGeneration == generation {
                    self.thumbnailTasks[entryID] = nil
                }
            }
            do {
                guard let data = try await self.service.thumbnailData(id: entryID), !Task.isCancelled else { return }
                guard generation == self.thumbnailGeneration,
                      self.loadedDescriptors.contains(where: { $0.id == entryID })
                else { return }
                let evictedIDs = self.thumbnailCache.insert(data, for: entryID)
                self.thumbnailUpdateRevision &+= 1
                var revisions = self.thumbnailUpdateRevisionsByEntryID
                for id in evictedIDs { revisions[id] = nil }
                revisions[entryID] = self.thumbnailUpdateRevision
                self.thumbnailUpdateRevisionsByEntryID = revisions
            } catch {
                // Keep the row available with its image placeholder.
            }
        }
        thumbnailTasks[entryID] = task
    }

    func delete(id: UUID) async {
        pagingGeneration &+= 1
        let previousDescriptors = visibleDescriptors
        let deletedIndex = previousDescriptors.firstIndex { $0.id == id }
        let selectedBeforeDelete = selectedEntryID
        do {
            try await service.delete(id: id)
            removeThumbnail(for: id)
            loadedDescriptors.removeAll { $0.id == id }

            if hasMorePages {
                let previousSearchRank = pageCursor?.searchRank
                pageCursor = loadedDescriptors.last.map {
                    HistoryPageCursor(
                        activityAt: $0.activityAt,
                        id: $0.id,
                        searchRank: $0.searchRank ?? previousSearchRank
                    )
                }
            }
            publish(descriptors: loadedDescriptors, selectFirstResult: false)
            if hasMorePages {
                if isLoadingMore {
                    await pageTask?.value
                }
                await loadMore()
            }

            await waitForPendingSearch()

            if selectedBeforeDelete == id, let deletedIndex {
                let descriptors = visibleDescriptors
                selectedEntryID = descriptors.isEmpty ? nil : descriptors[min(deletedIndex, descriptors.count - 1)].id
            } else if !visibleDescriptors.contains(where: { $0.id == selectedEntryID }) {
                selectedEntryID = visibleDescriptors.first?.id
            }
        } catch {
            cancelSearch()
            state = .error
            selectedEntryID = nil
        }
    }

    func delete(_ entry: HistoryEntry) async {
        await delete(id: entry.id)
    }

    @discardableResult
    func clearAll() async -> Bool {
        pagingGeneration &+= 1
        do {
            try await service.clearAll()
            invalidateThumbnailTasks()
            thumbnailCache.removeAll()
            thumbnailUpdateRevisionsByEntryID = [:]
            loadedDescriptors = []
            pageCursor = nil
            hasMorePages = false
            hasLoadedSnapshot = true
            cancelSearch()
            query = ""
            selectedEntryID = nil
            pasteFailure = nil
            captureNotice = nil
            isPasteInProgress = false
            state = .empty
            return true
        } catch {
            cancelSearch()
            state = .error
            selectedEntryID = nil
            return false
        }
    }

    func waitForPendingSearch() async {
        await searchTask?.value
    }

    private func schedulePagedSearch(selectFirstResult: Bool, debounce: Bool) {
        searchGeneration &+= 1
        pagingGeneration &+= 1
        let generation = searchGeneration
        searchTask?.cancel()
        pageTask?.cancel()
        let requestedQuery = query
        let delay = debounce ? searchDebounceNanoseconds : 0

        isSearchInProgress = true
        isLoadingMore = false
        loadedDescriptors = []
        pageCursor = nil
        hasMorePages = false
        visibleSnapshotRevision &+= 1
        state = .list([])
        selectedEntryID = nil
        searchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
            }
            do {
                let page = requestedQuery.isEmpty
                    ? try await self.service.page()
                    : try await self.service.searchPage(query: requestedQuery)
                guard !Task.isCancelled,
                      generation == self.searchGeneration,
                      requestedQuery == self.query
                else { return }
                self.loadedDescriptors = page.descriptors
                self.pageCursor = page.nextCursor
                self.hasMorePages = page.hasMore
                self.isSearchInProgress = false
                self.publish(descriptors: self.loadedDescriptors, selectFirstResult: selectFirstResult)
            } catch {
                guard generation == self.searchGeneration,
                      requestedQuery == self.query
                else { return }
                self.isSearchInProgress = false
                self.state = .error
                self.selectedEntryID = nil
            }
        }
    }

    private func publish(descriptors: [HistoryOccurrenceDescriptor], selectFirstResult: Bool) {
        visibleSnapshotRevision &+= 1
        state = descriptors.isEmpty && query.isEmpty ? .empty : .list(descriptors)
        if query.isEmpty {
            hasUnpublishedSnapshotChanges = false
        }
        if selectFirstResult || !descriptors.contains(where: { $0.id == selectedEntryID }) {
            selectedEntryID = descriptors.first?.id
        }
    }

    private func cancelSearch() {
        searchGeneration &+= 1
        searchTask?.cancel()
        searchTask = nil
        isSearchInProgress = false
    }

    private var hasCurrentUnfilteredState: Bool {
        guard !hasUnpublishedSnapshotChanges else { return false }
        return switch state {
        case let .list(descriptors):
            !loadedDescriptors.isEmpty && descriptors.count == loadedDescriptors.count
        case .empty:
            loadedDescriptors.isEmpty
        case .loading, .error:
            false
        }
    }

    @discardableResult
    private func discardExpiredSnapshotEntries() -> Bool {
        guard hasLoadedSnapshot else { return false }
        let cutoff = now().addingTimeInterval(-HistoryService.retention)
        let expiredIDs = loadedDescriptors.filter { $0.activityAt <= cutoff }.map(\.id)
        let previousCount = loadedDescriptors.count
        loadedDescriptors.removeAll { $0.activityAt <= cutoff }
        for id in expiredIDs { removeThumbnail(for: id) }
        if loadedDescriptors.count != previousCount, hasMorePages {
            let previousSearchRank = pageCursor?.searchRank
            pageCursor = loadedDescriptors.last.map {
                HistoryPageCursor(
                    activityAt: $0.activityAt,
                    id: $0.id,
                    searchRank: $0.searchRank ?? previousSearchRank
                )
            }
        }
        return loadedDescriptors.count != previousCount
    }

    private func removeThumbnail(for entryID: UUID) {
        thumbnailTasks.removeValue(forKey: entryID)?.cancel()
        thumbnailUpdateRevisionsByEntryID[entryID] = nil
        thumbnailCache.remove(entryID)
    }

    private func invalidateThumbnailTasks() {
        thumbnailGeneration &+= 1
        for task in thumbnailTasks.values { task.cancel() }
        thumbnailTasks.removeAll()
    }

    private static func descriptor(from entry: HistoryEntry) -> HistoryOccurrenceDescriptor {
        HistoryDisplayMetadata(entry: entry).descriptor(id: entry.id, activityAt: entry.activityAt)
    }

    private static func isNewer(_ lhs: HistoryOccurrenceDescriptor, than rhs: HistoryOccurrenceDescriptor) -> Bool {
        if lhs.activityAt != rhs.activityAt {
            return lhs.activityAt > rhs.activityAt
        }
        return lhs.id.uuidString > rhs.id.uuidString
    }
}

/// Encoded thumbnails only. Native collection items own their visible decoded
/// images; this cache does not keep decoded images for offscreen history.
struct HistoryThumbnailCache {
    let byteLimit: Int
    private(set) var values: [UUID: Data] = [:]
    private(set) var byteCount = 0
    private var access: [UUID: UInt64] = [:]
    private var revision: UInt64 = 0

    init(byteLimit: Int) {
        precondition(byteLimit > 0)
        self.byteLimit = byteLimit
    }

    mutating func value(for id: UUID) -> Data? {
        guard let value = values[id] else { return nil }
        revision &+= 1
        access[id] = revision
        return value
    }

    @discardableResult
    mutating func insert(_ data: Data, for id: UUID) -> [UUID] {
        remove(id)
        guard data.count <= byteLimit else { return [id] }
        var evicted: [UUID] = []
        while byteCount + data.count > byteLimit, let oldest = access.min(by: { $0.value < $1.value })?.key {
            remove(oldest)
            evicted.append(oldest)
        }
        values[id] = data
        byteCount += data.count
        revision &+= 1
        access[id] = revision
        return evicted
    }

    mutating func remove(_ id: UUID) {
        if let removed = values.removeValue(forKey: id) { byteCount -= removed.count }
        access[id] = nil
    }

    mutating func removeAll() {
        values.removeAll()
        access.removeAll()
        byteCount = 0
    }
}
