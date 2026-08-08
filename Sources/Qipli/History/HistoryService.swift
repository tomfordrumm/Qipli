import Foundation

protocol HistoryClock {
    var now: Date { get }
}

struct SystemHistoryClock: HistoryClock {
    var now: Date { Date() }
}

/// Owns retention policy and the only history write path.
final class HistoryService {
    static let retention: TimeInterval = 30 * 24 * 60 * 60

    private let store: HistoryStoring
    private let clock: HistoryClock

    init(store: HistoryStoring, clock: HistoryClock = SystemHistoryClock()) {
        self.store = store
        self.clock = clock
    }

    func entries() throws -> [HistoryEntry] {
        try store.fetchCurrent(since: retentionCutoff)
    }

    @discardableResult
    func capture(text: String) throws -> HistoryEntry {
        try store.create(text: text, activityAt: clock.now)
    }

    func markUsed(id: UUID) throws {
        try store.markUsed(id: id, activityAt: clock.now)
    }

    func delete(id: UUID) throws {
        try store.delete(id: id)
    }

    func clearAll() throws {
        try store.clearAll()
    }

    private var retentionCutoff: Date {
        clock.now.addingTimeInterval(-Self.retention)
    }
}
