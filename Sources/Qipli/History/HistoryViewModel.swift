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
            if entry.text.localizedCaseInsensitiveContains(query) {
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

    private let service: SerializedHistoryService
    private let searcher: any HistorySearching
    private let searchDebounceNanoseconds: UInt64
    private let now: () -> Date
    private var allEntries: [HistoryEntry] = []
    private var hasLoadedSnapshot = false
    private var searchGeneration = 0
    private var searchTask: Task<Void, Never>?

    init(
        service: HistoryService,
        searcher: any HistorySearching = BackgroundHistorySearcher(),
        searchDebounceNanoseconds: UInt64 = 100_000_000,
        now: @escaping () -> Date = Date.init
    ) {
        self.service = SerializedHistoryService(service: service)
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
        discardExpiredSnapshotEntries()
        query = ""
        selectedEntryID = nil
        pasteFailure = nil
        isPasteInProgress = false
        if hasLoadedSnapshot, state != .error {
            scheduleFilter(selectFirstResult: true, debounce: false)
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
        state = .loading
        do {
            allEntries = try await service.entries()
            hasLoadedSnapshot = true
            scheduleFilter(selectFirstResult: selectFirstResult, debounce: false)
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
        scheduleFilter(selectFirstResult: true, debounce: true)
    }

    func moveSelection(by offset: Int) {
        let entries = visibleEntries
        guard !entries.isEmpty else {
            selectedEntryID = nil
            return
        }
        let currentIndex = selectedEntryID.flatMap { id in entries.firstIndex { $0.id == id } } ?? 0
        selectedEntryID = entries[min(max(currentIndex + offset, 0), entries.count - 1)].id
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
        pasteFailure = nil
        isPasteInProgress = true
    }

    func endPaste() {
        isPasteInProgress = false
    }

    /// Paste dispatch already succeeded when this is called. A recency persistence
    /// failure is intentionally non-fatal: it must not report a false paste failure
    /// or cause a second dispatch.
    func markUsedAfterSuccessfulPaste(id: UUID) async {
        do {
            let activityAt = try await service.markUsed(id: id)
            guard let index = allEntries.firstIndex(where: { $0.id == id }) else { return }
            let previous = allEntries.remove(at: index)
            allEntries.insert(
                HistoryEntry(id: previous.id, text: previous.text, activityAt: activityAt),
                at: 0
            )
            scheduleFilter(selectFirstResult: false, debounce: false)
            await waitForPendingSearch()
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
        do {
            guard let entry = try await service.capture(text: text) else { return nil }
            allEntries.insert(entry, at: 0)
            hasLoadedSnapshot = true
            scheduleFilter(selectFirstResult: false, debounce: false)
            await waitForPendingSearch()
            return entry
        } catch {
            cancelSearch()
            state = .error
            return nil
        }
    }

    func delete(_ entry: HistoryEntry) async {
        let previousEntries = visibleEntries
        let deletedIndex = previousEntries.firstIndex { $0.id == entry.id }
        let selectedBeforeDelete = selectedEntryID
        do {
            try await service.delete(id: entry.id)
            allEntries.removeAll { $0.id == entry.id }
            scheduleFilter(selectFirstResult: false, debounce: false)
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
        do {
            try await service.clearAll()
            allEntries = []
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

    private func scheduleFilter(selectFirstResult: Bool, debounce: Bool) {
        searchGeneration &+= 1
        let generation = searchGeneration
        searchTask?.cancel()

        if allEntries.isEmpty {
            isSearchInProgress = false
            state = .empty
            selectedEntryID = nil
            return
        }

        guard !query.isEmpty else {
            isSearchInProgress = false
            publish(entries: allEntries, selectFirstResult: selectFirstResult)
            return
        }

        let snapshot = allEntries
        let requestedQuery = query
        let searcher = searcher
        let delay = debounce ? searchDebounceNanoseconds : 0
        isSearchInProgress = true
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

    private func publish(entries: [HistoryEntry], selectFirstResult: Bool) {
        state = .list(entries)
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

    private func discardExpiredSnapshotEntries() {
        guard hasLoadedSnapshot else { return }
        let cutoff = now().addingTimeInterval(-HistoryService.retention)
        allEntries.removeAll { $0.activityAt <= cutoff }
    }
}
