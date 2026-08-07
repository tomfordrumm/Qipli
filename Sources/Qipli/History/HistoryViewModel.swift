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

    func recordExternalText(_ text: String) {
        do {
            _ = try service.capture(text: text)
            reload()
        } catch {
            state = .error
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

    func clearAll() {
        do {
            try service.clearAll()
            allEntries = []
            query = ""
            selectedEntryID = nil
            pasteFailure = nil
            state = .empty
        } catch {
            state = .error
            selectedEntryID = nil
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
