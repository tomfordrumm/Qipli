import Foundation

protocol HistoryClock {
    var now: Date { get }
}

struct SystemHistoryClock: HistoryClock {
    var now: Date { Date() }
}

enum HistoryTextPolicy {
    static func shouldCapture(_ text: String) -> Bool {
        text.contains { !$0.isWhitespace }
    }
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
        try store.fetchCurrent(since: retentionCutoff).filter {
            HistoryTextPolicy.shouldCapture($0.text)
        }
    }

    @discardableResult
    func capture(text: String) throws -> HistoryEntry? {
        guard HistoryTextPolicy.shouldCapture(text) else { return nil }
        return try store.create(text: text, activityAt: clock.now)
    }

    @discardableResult
    func markUsed(id: UUID) throws -> Date {
        let activityAt = clock.now
        try store.markUsed(id: id, activityAt: activityAt)
        return activityAt
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

/// Serializes every storage operation on a non-main actor. The synchronous
/// service remains the policy boundary; only this executor crosses into UI code.
actor SerializedHistoryService {
    private let service: HistoryService

    init(service: HistoryService) {
        self.service = service
    }

    func entries() throws -> [HistoryEntry] {
        try service.entries()
    }

    func capture(text: String) throws -> HistoryEntry? {
        try service.capture(text: text)
    }

    func markUsed(id: UUID) throws -> Date {
        try service.markUsed(id: id)
    }

    func delete(id: UUID) throws {
        try service.delete(id: id)
    }

    func clearAll() throws {
        try service.clearAll()
    }
}
