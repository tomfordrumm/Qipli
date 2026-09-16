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

enum HistoryFilterMode: Equatable, Sendable {
    case history
    case favorites

    var favoritesOnly: Bool { self == .favorites }
}

/// Owns retention policy and the only history write path.
final class HistoryService {
    static let retention: TimeInterval = 30 * 24 * 60 * 60
    static let pageSize = 500

    private let store: HistoryStoring
    private let favoriteStore: HistoryFavoriteStoring?
    private let typedStore: TypedHistoryStoring?
    private let richTextStore: RichTextHistoryStoring?
    private let stackLeaseStore: HistoryStackPayloadLeaseStoring?
    private let clock: HistoryClock

    init(store: HistoryStoring, clock: HistoryClock = SystemHistoryClock()) {
        self.store = store
        favoriteStore = store as? HistoryFavoriteStoring
        typedStore = store as? TypedHistoryStoring
        richTextStore = store as? RichTextHistoryStoring
        stackLeaseStore = store as? HistoryStackPayloadLeaseStoring
        self.clock = clock
    }

    func entries(mode: HistoryFilterMode = .history) throws -> [HistoryEntry] {
        let entries: [HistoryEntry] = if let favoriteStore {
            try favoriteStore.fetchCurrent(since: retentionCutoff, favoritesOnly: mode.favoritesOnly)
        } else if mode == .favorites {
            []
        } else {
            try store.fetchCurrent(since: retentionCutoff)
        }
        return entries.filter(Self.isRenderable)
    }

    func page(after cursor: HistoryPageCursor? = nil, mode: HistoryFilterMode = .history) throws -> HistoryPage {
        if let favoriteStore {
            return try favoriteStore.fetchPage(
                since: retentionCutoff,
                after: cursor,
                limit: Self.pageSize,
                favoritesOnly: mode.favoritesOnly
            )
        }
        if mode == .favorites {
            return HistoryPage(descriptors: [], nextCursor: nil, hasMore: false)
        }
        return try store.fetchPage(since: retentionCutoff, after: cursor, limit: Self.pageSize)
    }

    func searchPage(
        query: String,
        after cursor: HistoryPageCursor? = nil,
        mode: HistoryFilterMode = .history
    ) throws -> HistoryPage {
        if let favoriteStore {
            return try favoriteStore.searchPage(
                query: query,
                since: retentionCutoff,
                after: cursor,
                limit: Self.pageSize,
                favoritesOnly: mode.favoritesOnly
            )
        }
        if mode == .favorites {
            return HistoryPage(descriptors: [], nextCursor: nil, hasMore: false)
        }
        return try store.searchPage(query: query, since: retentionCutoff, after: cursor, limit: Self.pageSize)
    }

    func entry(id: UUID) throws -> HistoryEntry? {
        try store.fetchEntry(id: id)
    }

    func occurrence(id: UUID) throws -> HistoryOccurrence? {
        try store.fetchOccurrence(id: id)
    }

    @discardableResult
    func capture(_ capture: HistoryCapture) throws -> HistoryCaptureResult? {
        switch capture {
        case let .text(text):
            guard HistoryTextPolicy.shouldCapture(text) else { return nil }
            return HistoryCaptureResult(
                entry: try store.create(text: text, activityAt: clock.now),
                notice: nil
            )
        case let .richText(text, items):
            guard HistoryTextPolicy.shouldCapture(text),
                  let richTextStore
            else { return nil }
            let result = try richTextStore.createRichText(
                text: text,
                items: items,
                activityAt: clock.now
            )
            return HistoryCaptureResult(entry: result.entry, notice: result.notice)
        case let .images(items):
            guard !items.isEmpty,
                  let typedStore
            else { return nil }
            return HistoryCaptureResult(
                entry: try typedStore.createImage(items: items, activityAt: clock.now),
                notice: nil
            )
        case let .references(items):
            guard !items.isEmpty,
                  let typedStore
            else { return nil }
            return HistoryCaptureResult(
                entry: try typedStore.createReference(items: items, activityAt: clock.now),
                notice: nil
            )
        case let .mixed(images, references):
            guard !images.isEmpty,
                  !references.isEmpty,
                  let typedStore
            else { return nil }
            return HistoryCaptureResult(
                entry: try typedStore.createImageAndReference(
                    imageItems: images,
                    referenceItems: references,
                    activityAt: clock.now
                ),
                notice: nil
            )
        }
    }

    func pastePayload(id: UUID) throws -> HistoryPastePayload? {
        try typedStore?.pastePayload(id: id)
    }

    func thumbnailData(id: UUID) throws -> Data? {
        try typedStore?.thumbnailData(id: id)
    }

    var supportsStackPayloadLeases: Bool { stackLeaseStore != nil }

    func acquireStackPayloadLease(occurrenceID: UUID, sessionID: UUID) throws -> HistoryStackPayloadLease? {
        try stackLeaseStore?.acquireStackPayloadLease(occurrenceID: occurrenceID, sessionID: sessionID)
    }

    func releaseStackPayloadLease(_ lease: HistoryStackPayloadLease) {
        stackLeaseStore?.releaseStackPayloadLease(lease)
    }

    func revokeStackPayloadLeases(for occurrenceID: UUID) {
        stackLeaseStore?.revokeStackPayloadLeases(for: occurrenceID)
    }

    func isStackPayloadLeaseValid(_ lease: HistoryStackPayloadLease) -> Bool {
        stackLeaseStore?.isStackPayloadLeaseValid(lease) ?? true
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

    func setFavorite(id: UUID, isFavorite: Bool) throws {
        guard let favoriteStore else { throw HistoryStoreError.unavailable }
        try favoriteStore.setFavorite(id: id, isFavorite: isFavorite)
    }

    private var retentionCutoff: Date {
        clock.now.addingTimeInterval(-Self.retention)
    }

    private static func isRenderable(_ entry: HistoryEntry) -> Bool {
        entry.isTypedEntry || HistoryTextPolicy.shouldCapture(entry.text)
    }

}

/// Serializes every storage operation on a non-main actor. The synchronous
/// service remains the policy boundary; only this executor crosses into UI code.
actor SerializedHistoryService {
    private let service: HistoryService

    init(service: HistoryService) {
        self.service = service
    }

    func entries(mode: HistoryFilterMode = .history) throws -> [HistoryEntry] {
        try service.entries(mode: mode)
    }


    func page(after cursor: HistoryPageCursor? = nil, mode: HistoryFilterMode = .history) throws -> HistoryPage {
        try service.page(after: cursor, mode: mode)
    }

    func searchPage(
        query: String,
        after cursor: HistoryPageCursor? = nil,
        mode: HistoryFilterMode = .history
    ) throws -> HistoryPage {
        try service.searchPage(query: query, after: cursor, mode: mode)
    }

    func entry(id: UUID) throws -> HistoryEntry? {
        try service.entry(id: id)
    }

    func occurrence(id: UUID) throws -> HistoryOccurrence? {
        try service.occurrence(id: id)
    }

    func capture(_ capture: HistoryCapture) throws -> HistoryCaptureResult? {
        try service.capture(capture)
    }

    func pastePayload(id: UUID) throws -> HistoryPastePayload? {
        try service.pastePayload(id: id)
    }

    func thumbnailData(id: UUID) throws -> Data? {
        try service.thumbnailData(id: id)
    }

    func acquireStackPayloadLease(occurrenceID: UUID, sessionID: UUID) throws -> HistoryStackPayloadLease? {
        try service.acquireStackPayloadLease(occurrenceID: occurrenceID, sessionID: sessionID)
    }

    func releaseStackPayloadLease(_ lease: HistoryStackPayloadLease) {
        service.releaseStackPayloadLease(lease)
    }

    func isStackPayloadLeaseValid(_ lease: HistoryStackPayloadLease) -> Bool {
        service.isStackPayloadLeaseValid(lease)
    }

    func revokeStackPayloadLeases(for occurrenceID: UUID) {
        service.revokeStackPayloadLeases(for: occurrenceID)
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

    func setFavorite(id: UUID, isFavorite: Bool) throws {
        try service.setFavorite(id: id, isFavorite: isFavorite)
    }
}
