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

    private let service: HistoryService

    init(service: HistoryService) {
        self.service = service
    }

    func reload() {
        state = .loading
        do {
            let entries = try service.entries()
            state = entries.isEmpty ? .empty : .list(entries)
        } catch {
            state = .error
        }
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
        do {
            try service.delete(id: entry.id)
            reload()
        } catch {
            state = .error
        }
    }

    func clearAll() {
        do {
            try service.clearAll()
            reload()
        } catch {
            state = .error
        }
    }
}
