import Foundation

enum HistoryViewState: Equatable {
    case loading
    case empty
    case list([HistoryEntry])
    case error
}

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published private(set) var state: HistoryViewState = .loading
    @Published private(set) var query = ""
    @Published private(set) var selectedEntryID: UUID?
    @Published private(set) var pasteFailure: HistoryPasteFailure?
    @Published private(set) var searchFocusRequestID = 0
    @Published private(set) var presentationViewportResetRequestID = 0

    private let service: HistoryService
    private var allEntries: [HistoryEntry] = []

    init(service: HistoryService) {
        self.service = service
    }

    var selectedEntry: HistoryEntry? {
        visibleEntries.first { $0.id == selectedEntryID }
    }

    var visibleEntries: [HistoryEntry] {
        guard case let .list(entries) = state else { return [] }
        return entries
    }

    func prepareForPresentation() {
        query = ""
        selectedEntryID = nil
        pasteFailure = nil
        reload(selectFirstResult: true)
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

    func reload(selectFirstResult: Bool = false) {
        state = .loading
        do {
            allEntries = try service.entries()
            applyFilter(selectFirstResult: selectFirstResult)
        } catch {
            state = .error
            selectedEntryID = nil
        }
    }

    func updateQuery(_ query: String) {
        self.query = query
        pasteFailure = nil
        applyFilter(selectFirstResult: true)
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

    /// Paste dispatch already succeeded when this is called. A recency persistence
    /// failure is intentionally non-fatal: it must not report a false paste failure
    /// or cause a second dispatch.
    func markUsedAfterSuccessfulPaste(id: UUID) {
        try? service.markUsed(id: id)
    }

    /// Captures first so optional consumers, such as Paste Stack collection, can
    /// safely reference the durable History occurrence rather than creating a
    /// separate in-memory-only value.
    @discardableResult
    func recordExternalText(_ text: String) -> HistoryEntry? {
        do {
            guard let entry = try service.capture(text: text) else { return nil }
            reload()
            return entry
        } catch {
            state = .error
            return nil
        }
    }

    func delete(_ entry: HistoryEntry) {
        let previousEntries = visibleEntries
        let deletedIndex = previousEntries.firstIndex { $0.id == entry.id }
        let selectedBeforeDelete = selectedEntryID
        do {
            try service.delete(id: entry.id)
            allEntries.removeAll { $0.id == entry.id }
            applyFilter(selectFirstResult: false)

            if selectedBeforeDelete == entry.id, let deletedIndex {
                let entries = visibleEntries
                selectedEntryID = entries.isEmpty ? nil : entries[min(deletedIndex, entries.count - 1)].id
            } else if !visibleEntries.contains(where: { $0.id == selectedEntryID }) {
                selectedEntryID = visibleEntries.first?.id
            }
        } catch {
            state = .error
            selectedEntryID = nil
        }
    }

    @discardableResult
    func clearAll() -> Bool {
        do {
            try service.clearAll()
            allEntries = []
            query = ""
            selectedEntryID = nil
            pasteFailure = nil
            state = .empty
            return true
        } catch {
            state = .error
            selectedEntryID = nil
            return false
        }
    }

    private func applyFilter(selectFirstResult: Bool) {
        let entries: [HistoryEntry]
        if query.isEmpty {
            entries = allEntries
        } else {
            entries = allEntries.filter { $0.text.localizedCaseInsensitiveContains(query) }
        }

        if allEntries.isEmpty {
            state = .empty
            selectedEntryID = nil
            return
        }

        state = .list(entries)
        if selectFirstResult || !entries.contains(where: { $0.id == selectedEntryID }) {
            selectedEntryID = entries.first?.id
        }
    }
}
