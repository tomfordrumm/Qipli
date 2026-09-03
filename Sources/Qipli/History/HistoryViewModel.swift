import Foundation

enum HistoryViewState: Equatable {
    case loading
    case empty
    case list([HistoryOccurrenceDescriptor])
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
    @Published private(set) var isSearchInProgress = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var thumbnailDataByEntryID: [UUID: Data] = [:]
    @Published private(set) var captureNotice: String?
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
    /// Only bounded descriptors for requested pages cross onto the main actor.
    private var loadedDescriptors: [HistoryOccurrenceDescriptor] = []
    /// Compatibility storage for non-paging test/preview stores. Production
    /// Core Data never populates this dictionary.
    private var legacyEntriesByID: [UUID: HistoryEntry] = [:]
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
        guard let selectedEntryID else { return nil }
        return legacyEntriesByID[selectedEntryID]
    }

    var visibleEntries: [HistoryEntry] {
        visibleDescriptors.map { descriptor in
            legacyEntriesByID[descriptor.id] ?? Self.entry(from: descriptor)
        }
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
            if usesPaging, wasFiltered {
                schedulePagedSearch(selectFirstResult: true, debounce: false)
            } else if usesPaging {
                publish(descriptors: loadedDescriptors, selectFirstResult: true)
            } else {
                scheduleLegacyFilter(selectFirstResult: true, debounce: false)
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
            legacyEntriesByID = [:]
            pageCursor = nil
            hasMorePages = false
            let descriptors: [HistoryOccurrenceDescriptor]
            if usesPaging {
                let page = query.isEmpty
                    ? try await service.page()
                    : try await service.searchPage(query: query)
                descriptors = page.descriptors
                pageCursor = page.nextCursor
                hasMorePages = page.hasMore
            } else {
                let entries = try await service.entries()
                legacyEntriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
                descriptors = entries.map(Self.descriptor(from:))
            }
            loadedDescriptors = descriptors
            hasLoadedSnapshot = true
            if usesPaging {
                publish(descriptors: descriptors, selectFirstResult: selectFirstResult)
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
                textPreview: previous.textPreview,
                representations: previous.representations,
                imageMetadata: previous.imageMetadata,
                referenceMetadata: previous.referenceMetadata
            )
            let insertionIndex = loadedDescriptors.firstIndex(where: { Self.isNewer(updated, than: $0) })
                ?? loadedDescriptors.endIndex
            loadedDescriptors.insert(updated, at: insertionIndex)
            if let legacyEntry = legacyEntriesByID[id] {
                legacyEntriesByID[id] = HistoryEntry(
                    id: legacyEntry.id,
                    text: legacyEntry.text,
                    activityAt: activityAt,
                    representations: legacyEntry.representations,
                    imageMetadata: legacyEntry.imageMetadata,
                    managedImages: legacyEntry.managedImages,
                    managedImageItems: legacyEntry.managedImageItems,
                    managedImageName: legacyEntry.managedImageName,
                    referenceMetadata: legacyEntry.referenceMetadata,
                    hasRichText: legacyEntry.hasRichText
                )
            }
            if usesPaging, hasMorePages {
                pageCursor = loadedDescriptors.last.map {
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
        await recordExternalCapture(.text(text))
    }

    @discardableResult
    func recordExternalRichText(
        _ text: String,
        items: [HistoryRichTextCaptureItem]
    ) async -> HistoryEntry? {
        await recordExternalCapture(.richText(text: text, items: items))
    }

    @discardableResult
    func recordExternalImage(_ items: [ManagedImageCaptureItem]) async -> HistoryEntry? {
        await recordExternalCapture(.images(items))
    }

    @discardableResult
    func recordExternalReference(_ items: [HistoryReferenceCaptureItem]) async -> HistoryEntry? {
        await recordExternalCapture(.references(items))
    }

    @discardableResult
    func recordExternalMixed(
        imageItems: [ManagedImageCaptureItem],
        referenceItems: [HistoryReferenceCaptureItem]
    ) async -> HistoryEntry? {
        await recordExternalCapture(.mixed(images: imageItems, references: referenceItems))
    }

    @discardableResult
    func recordExternalCapture(_ capture: HistoryCapture) async -> HistoryEntry? {
        pagingGeneration &+= 1
        do {
            guard let result = try await service.capture(capture) else { return nil }
            captureNotice = result.notice
            let entry = result.entry
            let descriptor = Self.descriptor(from: entry)
            loadedDescriptors.removeAll { $0.id == entry.id }
            let insertionIndex = usesPaging
                ? loadedDescriptors.firstIndex(where: { Self.isNewer(descriptor, than: $0) }) ?? loadedDescriptors.endIndex
                : loadedDescriptors.startIndex
            loadedDescriptors.insert(descriptor, at: insertionIndex)
            if !usesPaging {
                legacyEntriesByID[entry.id] = entry
            }
            if usesPaging, loadedDescriptors.count > HistoryService.pageSize {
                loadedDescriptors.removeLast()
                hasMorePages = true
                pageCursor = loadedDescriptors.last.map {
                    HistoryPageCursor(activityAt: $0.activityAt, id: $0.id)
                }
            }
            hasLoadedSnapshot = true
            if usesPaging {
                if query.isEmpty {
                    publish(descriptors: loadedDescriptors, selectFirstResult: false)
                } else {
                    schedulePagedSearch(selectFirstResult: true, debounce: false)
                }
            } else {
                scheduleLegacyFilter(selectFirstResult: false, debounce: false)
            }
            await waitForPendingSearch()
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
              thumbnailDataByEntryID[entryID] == nil,
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

    func delete(id: UUID) async {
        pagingGeneration &+= 1
        let previousDescriptors = visibleDescriptors
        let deletedIndex = previousDescriptors.firstIndex { $0.id == id }
        let selectedBeforeDelete = selectedEntryID
        do {
            try await service.delete(id: id)
            removeThumbnail(for: id)
            loadedDescriptors.removeAll { $0.id == id }
            legacyEntriesByID[id] = nil
            if usesPaging {
                if hasMorePages {
                    pageCursor = loadedDescriptors.last.map {
                        HistoryPageCursor(activityAt: $0.activityAt, id: $0.id)
                    }
                }
                publish(descriptors: loadedDescriptors, selectFirstResult: false)
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
            thumbnailDataByEntryID.removeAll()
            thumbnailCacheByteCount = 0
            loadedDescriptors = []
            legacyEntriesByID = [:]
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

    private func scheduleLegacyFilter(selectFirstResult: Bool, debounce: Bool) {
        searchGeneration &+= 1
        let generation = searchGeneration
        searchTask?.cancel()

        if loadedDescriptors.isEmpty {
            isSearchInProgress = false
            state = .empty
            selectedEntryID = nil
            return
        }

        guard !query.isEmpty else {
            isSearchInProgress = false
            publish(descriptors: loadedDescriptors, selectFirstResult: selectFirstResult)
            return
        }

        let snapshot = loadedDescriptors.compactMap { legacyEntriesByID[$0.id] }
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
            self.publish(descriptors: entries.map(Self.descriptor(from:)), selectFirstResult: selectFirstResult)
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
        loadedDescriptors = []
        legacyEntriesByID = [:]
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
        for id in expiredIDs { legacyEntriesByID[id] = nil }
        for id in expiredIDs { removeThumbnail(for: id) }
        if usesPaging, loadedDescriptors.count != previousCount, hasMorePages {
            pageCursor = loadedDescriptors.last.map {
                HistoryPageCursor(activityAt: $0.activityAt, id: $0.id)
            }
        }
        return loadedDescriptors.count != previousCount
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

    private static func entry(from descriptor: HistoryOccurrenceDescriptor) -> HistoryEntry {
        HistoryEntry(
            id: descriptor.id,
            text: descriptor.textPreview ?? "",
            activityAt: descriptor.activityAt,
            representations: descriptor.representations,
            imageMetadata: descriptor.imageMetadata,
            referenceMetadata: descriptor.referenceMetadata
        )
    }

    private static func descriptor(from entry: HistoryEntry) -> HistoryOccurrenceDescriptor {
        HistoryOccurrenceDescriptor(
            id: entry.id,
            activityAt: entry.activityAt,
            textPreview: entry.isTextOnly ? HistoryPreview.text(for: entry.text) : nil,
            representations: entry.representations,
            imageMetadata: entry.imageMetadata,
            referenceMetadata: entry.referenceMetadata
        )
    }

    private static func isNewer(_ lhs: HistoryOccurrenceDescriptor, than rhs: HistoryOccurrenceDescriptor) -> Bool {
        if lhs.activityAt != rhs.activityAt {
            return lhs.activityAt > rhs.activityAt
        }
        return lhs.id.uuidString > rhs.id.uuidString
    }
}
