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
    static let pageSize = 500

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

    var supportsPaging: Bool {
        store is HistoryPagingStoring
    }

    func page(after cursor: HistoryPageCursor? = nil) throws -> HistoryPage {
        guard let pagedStore = store as? HistoryPagingStoring else {
            return try fallbackPage(after: cursor, query: nil)
        }
        return try pagedStore.fetchPage(
            since: retentionCutoff,
            after: cursor,
            limit: Self.pageSize
        )
    }

    func searchPage(query: String, after cursor: HistoryPageCursor? = nil) throws -> HistoryPage {
        guard let pagedStore = store as? HistoryPagingStoring else {
            return try fallbackPage(after: cursor, query: query)
        }
        return try pagedStore.searchPage(
            query: query,
            since: retentionCutoff,
            after: cursor,
            limit: Self.pageSize
        )
    }

    func entry(id: UUID) throws -> HistoryEntry? {
        guard let pagedStore = store as? HistoryPagingStoring else {
            return try store.fetchCurrent(since: .distantPast).first { $0.id == id }
        }
        return try pagedStore.fetchEntry(id: id)
    }

    func occurrence(id: UUID) throws -> HistoryOccurrence? {
        guard let pagedStore = store as? HistoryPagingStoring else { return nil }
        return try pagedStore.fetchOccurrence(id: id)
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

    private func fallbackPage(after cursor: HistoryPageCursor?, query: String?) throws -> HistoryPage {
        var entries = try entries()
        if let query, !query.isEmpty {
            entries = HistorySearchMatcher.matches(in: entries, query: query)
        }
        if let cursor {
            entries = entries.filter {
                $0.activityAt < cursor.activityAt ||
                    ($0.activityAt == cursor.activityAt && $0.id.uuidString < cursor.id.uuidString)
            }
        }
        let pageEntries = Array(entries.prefix(Self.pageSize))
        let descriptors = pageEntries.map { entry in
            HistoryOccurrenceDescriptor(
                id: entry.id,
                activityAt: entry.activityAt,
                textPreview: HistoryPreview.text(for: entry.text),
                representations: [
                    HistoryRepresentationDescriptor(
                        kind: .text,
                        typeIdentifier: "public.utf8-plain-text"
                    )
                ]
            )
        }
        return HistoryPage(
            descriptors: descriptors,
            textEntries: pageEntries,
            nextCursor: pageEntries.last.map {
                HistoryPageCursor(activityAt: $0.activityAt, id: $0.id)
            },
            hasMore: entries.count > Self.pageSize
        )
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

    var supportsPaging: Bool {
        service.supportsPaging
    }

    func page(after cursor: HistoryPageCursor? = nil) throws -> HistoryPage {
        try service.page(after: cursor)
    }

    func searchPage(query: String, after cursor: HistoryPageCursor? = nil) throws -> HistoryPage {
        try service.searchPage(query: query, after: cursor)
    }

    func entry(id: UUID) throws -> HistoryEntry? {
        try service.entry(id: id)
    }

    func occurrence(id: UUID) throws -> HistoryOccurrence? {
        try service.occurrence(id: id)
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
