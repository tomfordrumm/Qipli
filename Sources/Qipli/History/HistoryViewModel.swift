import Foundation

enum HistoryViewState: Equatable {
    case loading
    case empty
    case list([HistoryEntry])
    case error
}

protocol HistorySearching: Sendable {
    func matches(in entries: [HistoryEntry], query: String) async -> [HistoryEntry]
}

enum HistorySearchMatcher {
    static func matches(
        in entries: [HistoryEntry],
        query: String,
        didInspect: (() -> Void)? = nil
    ) -> [HistoryEntry] {
        var matches: [HistoryEntry] = []
        matches.reserveCapacity(min(entries.count, 64))
        for entry in entries {
            guard !Task.isCancelled else { return [] }
            didInspect?()
            if entry.searchableMetadata.localizedCaseInsensitiveContains(query) {
                matches.append(entry)
            }
        }
        return matches
    }
}

actor BackgroundHistorySearcher: HistorySearching {
    func matches(in entries: [HistoryEntry], query: String) -> [HistoryEntry] {
        HistorySearchMatcher.matches(in: entries, query: query)
    }
}

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published private(set) var state: HistoryViewState = .loading
    @Published private(set) var query = ""
    @Published private(set) var selectedEntryID: UUID?
    @Published private(set) var pasteFailure: HistoryPasteFailure?
    @Published private(set) var isPasteInProgress = false
    @Published private(set) var searchFocusRequestID = 0
    @Published private(set) var presentationViewportResetRequestID = 0
    @Published private(set) var isSearchInProgress = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var thumbnailDataByEntryID: [UUID: Data] = [:]
    @Published private(set) var imageCaptureNotice: String?
    private(set) var visibleSnapshotRevision = 0
    private let thumbnailCacheBytes = HistoryImageStoragePolicy.production.thumbnailCacheBytes
    private var thumbnailCacheByteCount = 0
    private var thumbnailTasks: [UUID: Task<Void, Never>] = [:]
    private var thumbnailGeneration = 0

    private let service: SerializedHistoryService
    private let usesPaging: Bool
    private let searcher: any HistorySearching
    private let searchDebounceNanoseconds: UInt64
    private let now: () -> Date
    /// Only the pages requested by the user live here. Production Core Data
    /// search never loads the retained catalogue into this array.
    private var loadedEntries: [HistoryEntry] = []
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
        searcher: any HistorySearching = BackgroundHistorySearcher(),
        searchDebounceNanoseconds: UInt64 = 100_000_000,
        now: @escaping () -> Date = Date.init
    ) {
        self.service = SerializedHistoryService(service: service)
        usesPaging = service.supportsPaging
        self.searcher = searcher
        self.searchDebounceNanoseconds = searchDebounceNanoseconds
        self.now = now
    }

    var selectedEntry: HistoryEntry? {
        visibleEntries.first { $0.id == selectedEntryID }
    }

    var visibleEntries: [HistoryEntry] {
        guard case let .list(entries) = state else { return [] }
        return entries
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
            if usesPaging, wasFiltered {
                schedulePagedSearch(selectFirstResult: true, debounce: false)
            } else if usesPaging {
                publish(entries: loadedEntries, selectFirstResult: true)
            } else {
                scheduleLegacyFilter(selectFirstResult: true, debounce: false)
            }
        } else {
            let firstEntryID = loadedEntries.first?.id
            if selectedEntryID != firstEntryID {
                selectedEntryID = firstEntryID
            }
        }
    }

    func requestSearchFocus() {
        searchFocusRequestID &+= 1
    }

    /// A fresh History presentation is visible before this signal is requested.
    /// It deliberately remains separate from search focus and selection changes
    /// so a reusable panel can restore its list viewport without affecting retry.
    func requestPresentationViewportReset() {
        presentationViewportResetRequestID &+= 1
    }

    func reload(selectFirstResult: Bool = false) async {
        cancelSearch()
        invalidateThumbnailTasks()
        pagingGeneration &+= 1
        pageTask?.cancel()
        state = .loading
        do {
            loadedEntries = []
            pageCursor = nil
            hasMorePages = false
            let entries: [HistoryEntry]
            if usesPaging {
                let page = query.isEmpty
                    ? try await service.page()
                    : try await service.searchPage(query: query)
                entries = Self.entries(from: page)
                pageCursor = page.nextCursor
                hasMorePages = page.hasMore
            } else {
                entries = try await service.entries()
            }
            loadedEntries = entries
            hasLoadedSnapshot = true
            if usesPaging {
                publish(entries: entries, selectFirstResult: selectFirstResult)
            } else {
                scheduleLegacyFilter(selectFirstResult: selectFirstResult, debounce: false)
            }
            await waitForPendingSearch()
        } catch {
            cancelSearch()
            state = .error
            selectedEntryID = nil
        }
    }

    func updateQuery(_ query: String) {
        self.query = query
        pasteFailure = nil
        if usesPaging {
            schedulePagedSearch(selectFirstResult: true, debounce: true)
        } else {
            scheduleLegacyFilter(selectFirstResult: true, debounce: true)
        }
    }

    /// Requests exactly one next page. The table calls this when its viewport
    /// reaches the end; the generation/cursor guards make repeated scroll
    /// notifications harmless.
    func loadMore() async {
        if isLoadingMore {
            await pageTask?.value
            return
        }
        guard usesPaging,
              hasLoadedSnapshot,
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
            let nextEntries = Self.entries(from: page)
            loadedEntries.append(contentsOf: nextEntries)
            pageCursor = page.nextCursor
            hasMorePages = page.hasMore && !nextEntries.isEmpty
            publish(entries: loadedEntries, selectFirstResult: false)
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
        let entries = visibleEntries
        guard !entries.isEmpty else {
            if selectedEntryID != nil {
                selectedEntryID = nil
            }
            return
        }
        let currentIndex = selectedEntryID.flatMap { id in entries.firstIndex { $0.id == id } } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), entries.count - 1)
        let nextID = entries[nextIndex].id
        guard selectedEntryID != nextID else { return }
        selectedEntryID = nextID
    }

    func select(id: UUID) {
        guard visibleEntries.contains(where: { $0.id == id }) else { return }
        selectedEntryID = id
        pasteFailure = nil
    }

    func recordPasteFailure(_ failure: HistoryPasteFailure) {
        pasteFailure = failure
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
            guard let index = loadedEntries.firstIndex(where: { $0.id == id }) else { return }
            let previous = loadedEntries.remove(at: index)
            let updated = HistoryEntry(
                id: previous.id,
                text: previous.text,
                activityAt: activityAt,
                representations: previous.representations,
                imageMetadata: previous.imageMetadata,
                managedImages: previous.managedImages,
                managedImageItems: previous.managedImageItems,
                managedImageName: previous.managedImageName,
                referenceMetadata: previous.referenceMetadata
            )
            let insertionIndex = loadedEntries.firstIndex(where: { Self.isNewer(updated, than: $0) }) ?? loadedEntries.endIndex
            loadedEntries.insert(updated, at: insertionIndex)
            if usesPaging, hasMorePages {
                pageCursor = loadedEntries.last.map {
                    HistoryPageCursor(activityAt: $0.activityAt, id: $0.id)
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
    func recordExternalText(_ text: String) async -> HistoryEntry? {
        pagingGeneration &+= 1
        do {
            guard let entry = try await service.capture(text: text) else { return nil }
            imageCaptureNotice = nil
            loadedEntries.removeAll { $0.id == entry.id }
            let insertionIndex = usesPaging
                ? loadedEntries.firstIndex(where: { Self.isNewer(entry, than: $0) }) ?? loadedEntries.endIndex
                : loadedEntries.startIndex
            loadedEntries.insert(entry, at: insertionIndex)
            if usesPaging, loadedEntries.count > HistoryService.pageSize {
                loadedEntries.removeLast()
                hasMorePages = true
                pageCursor = loadedEntries.last.map {
                    HistoryPageCursor(activityAt: $0.activityAt, id: $0.id)
                }
            }
            hasLoadedSnapshot = true
            if usesPaging {
                if query.isEmpty {
                    publish(entries: loadedEntries, selectFirstResult: false)
                } else {
                    schedulePagedSearch(selectFirstResult: true, debounce: false)
                }
            } else {
                scheduleLegacyFilter(selectFirstResult: false, debounce: false)
            }
            await waitForPendingSearch()
            return entry
        } catch {
            cancelSearch()
            state = .error
            return nil
        }
    }

    @discardableResult
    func recordExternalImage(_ items: [ManagedImageCaptureItem]) async -> HistoryEntry? {
        pagingGeneration &+= 1
        do {
            guard let entry = try await service.capture(imageItems: items) else { return nil }
            imageCaptureNotice = nil
            loadedEntries.removeAll { $0.id == entry.id }
            loadedEntries.insert(entry, at: 0)
            if usesPaging, loadedEntries.count > HistoryService.pageSize {
                loadedEntries.removeLast()
                hasMorePages = true
                pageCursor = loadedEntries.last.map {
                    HistoryPageCursor(activityAt: $0.activityAt, id: $0.id)
                }
            }
            hasLoadedSnapshot = true
            if query.isEmpty {
                publish(entries: loadedEntries, selectFirstResult: false)
            } else {
                schedulePagedSearch(selectFirstResult: true, debounce: false)
            }
            return entry
        } catch {
            imageCaptureNotice = (error as? LocalizedError)?.errorDescription
                ?? "Qipli could not save the copied image."
            return nil
        }
    }

    @discardableResult
    func recordExternalReference(_ items: [HistoryReferenceCaptureItem]) async -> HistoryEntry? {
        pagingGeneration &+= 1
        do {
            guard let entry = try await service.capture(referenceItems: items) else { return nil }
            imageCaptureNotice = nil
            loadedEntries.removeAll { $0.id == entry.id }
            loadedEntries.insert(entry, at: 0)
            if usesPaging, loadedEntries.count > HistoryService.pageSize {
                loadedEntries.removeLast()
                hasMorePages = true
                pageCursor = loadedEntries.last.map {
                    HistoryPageCursor(activityAt: $0.activityAt, id: $0.id)
                }
            }
            hasLoadedSnapshot = true
            if query.isEmpty {
                publish(entries: loadedEntries, selectFirstResult: false)
            } else {
                schedulePagedSearch(selectFirstResult: true, debounce: false)
            }
            return entry
        } catch {
            imageCaptureNotice = (error as? LocalizedError)?.errorDescription
                ?? "Qipli could not save the copied file reference."
            return nil
        }
    }

    @discardableResult
    func recordExternalMixed(
        imageItems: [ManagedImageCaptureItem],
        referenceItems: [HistoryReferenceCaptureItem]
    ) async -> HistoryEntry? {
        pagingGeneration &+= 1
        do {
            guard let entry = try await service.capture(
                imageItems: imageItems,
                referenceItems: referenceItems
            ) else { return nil }
            imageCaptureNotice = nil
            loadedEntries.removeAll { $0.id == entry.id }
            loadedEntries.insert(entry, at: 0)
            if usesPaging, loadedEntries.count > HistoryService.pageSize {
                loadedEntries.removeLast()
                hasMorePages = true
                pageCursor = loadedEntries.last.map {
                    HistoryPageCursor(activityAt: $0.activityAt, id: $0.id)
                }
            }
            hasLoadedSnapshot = true
            if query.isEmpty {
                publish(entries: loadedEntries, selectFirstResult: false)
            } else {
                schedulePagedSearch(selectFirstResult: true, debounce: false)
            }
            return entry
        } catch {
            imageCaptureNotice = (error as? LocalizedError)?.errorDescription
                ?? "Qipli could not save the copied item."
            return nil
        }
    }

    func requestThumbnail(for entry: HistoryEntry) {
        guard entry.isImageEntry,
              thumbnailDataByEntryID[entry.id] == nil,
              thumbnailTasks[entry.id] == nil
        else { return }
        let entryID = entry.id
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
                      self.loadedEntries.contains(where: { $0.id == entryID })
                else { return }
                if let previous = self.thumbnailDataByEntryID.updateValue(data, forKey: entryID) {
                    self.thumbnailCacheByteCount -= previous.count
                }
                self.thumbnailCacheByteCount += data.count
                while self.thumbnailCacheByteCount > self.thumbnailCacheBytes,
                      let oldestID = self.thumbnailDataByEntryID.keys.first,
                      oldestID != entryID || self.thumbnailDataByEntryID.count > 1 {
                    if let removed = self.thumbnailDataByEntryID.removeValue(forKey: oldestID) {
                        self.thumbnailCacheByteCount -= removed.count
                    }
                }
                self.visibleSnapshotRevision &+= 1
            } catch {
                // Keep the row available with its image placeholder.
            }
        }
        thumbnailTasks[entryID] = task
    }

    func delete(_ entry: HistoryEntry) async {
        pagingGeneration &+= 1
        let previousEntries = visibleEntries
        let deletedIndex = previousEntries.firstIndex { $0.id == entry.id }
        let selectedBeforeDelete = selectedEntryID
        do {
            try await service.delete(id: entry.id)
            removeThumbnail(for: entry.id)
            loadedEntries.removeAll { $0.id == entry.id }
            if usesPaging {
                if hasMorePages {
                    pageCursor = loadedEntries.last.map {
                        HistoryPageCursor(activityAt: $0.activityAt, id: $0.id)
                    }
                }
                publish(entries: loadedEntries, selectFirstResult: false)
                if hasMorePages {
                    if isLoadingMore {
                        await pageTask?.value
                    }
                    await loadMore()
                }
            } else {
                scheduleLegacyFilter(selectFirstResult: false, debounce: false)
            }
            await waitForPendingSearch()

            if selectedBeforeDelete == entry.id, let deletedIndex {
                let entries = visibleEntries
                selectedEntryID = entries.isEmpty ? nil : entries[min(deletedIndex, entries.count - 1)].id
            } else if !visibleEntries.contains(where: { $0.id == selectedEntryID }) {
                selectedEntryID = visibleEntries.first?.id
            }
        } catch {
            cancelSearch()
            state = .error
            selectedEntryID = nil
        }
    }

    @discardableResult
    func clearAll() async -> Bool {
        pagingGeneration &+= 1
        do {
            try await service.clearAll()
            invalidateThumbnailTasks()
            thumbnailDataByEntryID.removeAll()
            thumbnailCacheByteCount = 0
            loadedEntries = []
            pageCursor = nil
            hasMorePages = false
            hasLoadedSnapshot = true
            cancelSearch()
            query = ""
            selectedEntryID = nil
            pasteFailure = nil
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

    private func scheduleLegacyFilter(selectFirstResult: Bool, debounce: Bool) {
        searchGeneration &+= 1
        let generation = searchGeneration
        searchTask?.cancel()

        if loadedEntries.isEmpty {
            isSearchInProgress = false
            state = .empty
            selectedEntryID = nil
            return
        }

        guard !query.isEmpty else {
            isSearchInProgress = false
            publish(entries: loadedEntries, selectFirstResult: selectFirstResult)
            return
        }

        let snapshot = loadedEntries
        let requestedQuery = query
        let searcher = searcher
        let delay = debounce ? searchDebounceNanoseconds : 0
        isSearchInProgress = true
        visibleSnapshotRevision &+= 1
        state = .list([])
        selectedEntryID = nil
        searchTask = Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
            }
            let entries = await searcher.matches(in: snapshot, query: requestedQuery)
            guard !Task.isCancelled,
                  let self,
                  generation == self.searchGeneration,
                  requestedQuery == self.query
            else { return }
            self.isSearchInProgress = false
            self.publish(entries: entries, selectFirstResult: selectFirstResult)
        }
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
        loadedEntries = []
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
                      requestedQuery == self.query,
                      !Task.isCancelled
                else { return }
                self.loadedEntries = Self.entries(from: page)
                self.pageCursor = page.nextCursor
                self.hasMorePages = page.hasMore
                self.isSearchInProgress = false
                self.publish(entries: self.loadedEntries, selectFirstResult: selectFirstResult)
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

    private func publish(entries: [HistoryEntry], selectFirstResult: Bool) {
        visibleSnapshotRevision &+= 1
        state = entries.isEmpty && query.isEmpty ? .empty : .list(entries)
        if query.isEmpty {
            hasUnpublishedSnapshotChanges = false
        }
        if selectFirstResult || !entries.contains(where: { $0.id == selectedEntryID }) {
            selectedEntryID = entries.first?.id
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
        case let .list(entries):
            !loadedEntries.isEmpty && entries.count == loadedEntries.count
        case .empty:
            loadedEntries.isEmpty
        case .loading, .error:
            false
        }
    }

    @discardableResult
    private func discardExpiredSnapshotEntries() -> Bool {
        guard hasLoadedSnapshot else { return false }
        let cutoff = now().addingTimeInterval(-HistoryService.retention)
        let expiredIDs = loadedEntries.filter { $0.activityAt <= cutoff }.map(\.id)
        let previousCount = loadedEntries.count
        loadedEntries.removeAll { $0.activityAt <= cutoff }
        for id in expiredIDs { removeThumbnail(for: id) }
        if usesPaging, loadedEntries.count != previousCount, hasMorePages {
            pageCursor = loadedEntries.last.map {
                HistoryPageCursor(activityAt: $0.activityAt, id: $0.id)
            }
        }
        return loadedEntries.count != previousCount
    }

    private func removeThumbnail(for entryID: UUID) {
        thumbnailTasks.removeValue(forKey: entryID)?.cancel()
        if let data = thumbnailDataByEntryID.removeValue(forKey: entryID) {
            thumbnailCacheByteCount -= data.count
        }
    }

    private func invalidateThumbnailTasks() {
        thumbnailGeneration &+= 1
        for task in thumbnailTasks.values { task.cancel() }
        thumbnailTasks.removeAll()
    }

    private static func entries(from page: HistoryPage) -> [HistoryEntry] {
        if !page.entries.isEmpty || page.descriptors.isEmpty {
            return page.entries
        }
        return page.descriptors.compactMap { (descriptor: HistoryOccurrenceDescriptor) -> HistoryEntry? in
            HistoryEntry(
                id: descriptor.id,
                text: descriptor.textPreview ?? "",
                activityAt: descriptor.activityAt,
                representations: descriptor.representations,
                imageMetadata: descriptor.imageMetadata,
                referenceMetadata: descriptor.referenceMetadata
            )
        }
    }

    private static func isNewer(_ lhs: HistoryEntry, than rhs: HistoryEntry) -> Bool {
        if lhs.activityAt != rhs.activityAt {
            return lhs.activityAt > rhs.activityAt
        }
        return lhs.id.uuidString > rhs.id.uuidString
    }
}
