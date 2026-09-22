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
    private let clock: HistoryClock

    init(store: HistoryStoring, clock: HistoryClock = SystemHistoryClock()) {
        self.store = store
        self.clock = clock
    }

    /// Reads only display metadata in small pages, independent of panel filters.
    func recentDescriptors() throws -> [HistoryOccurrenceDescriptor] {
        var result: [HistoryOccurrenceDescriptor] = []
        var cursor: HistoryPageCursor?
        repeat {
            let page = try store.fetchPage(since: retentionCutoff, after: cursor, limit: 5)
            result.append(contentsOf: page.descriptors.filter {
                !$0.isTextOnly || HistoryTextPolicy.shouldCapture($0.textPreview ?? "")
            }.prefix(5 - result.count))
            guard result.count < 5, page.hasMore, let next = page.nextCursor, next != cursor else { break }
            cursor = next
        } while true
        return result
    }

    func page(after cursor: HistoryPageCursor? = nil, mode: HistoryFilterMode = .history) throws -> HistoryPage {
        try store.fetchPage(since: retentionCutoff, after: cursor, limit: Self.pageSize, favoritesOnly: mode.favoritesOnly)
    }

    func searchPage(query: String, after cursor: HistoryPageCursor? = nil, mode: HistoryFilterMode = .history) throws -> HistoryPage {
        try store.searchPage(query: query, since: retentionCutoff, after: cursor, limit: Self.pageSize, favoritesOnly: mode.favoritesOnly)
    }

    func entry(id: UUID) throws -> HistoryEntry? {
        try store.fetchEntry(id: id)
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
            guard HistoryTextPolicy.shouldCapture(text) else { return nil }
            let result = try store.createRichText(
                text: text,
                items: items,
                activityAt: clock.now
            )
            return HistoryCaptureResult(entry: result.entry, notice: result.notice)
        case let .images(items):
            guard !items.isEmpty else { return nil }
            return HistoryCaptureResult(
                entry: try store.createImage(items: items, activityAt: clock.now),
                notice: nil
            )
        case let .references(items):
            guard !items.isEmpty else { return nil }
            return HistoryCaptureResult(
                entry: try store.createReference(items: items, activityAt: clock.now),
                notice: nil
            )
        case let .mixed(images, references):
            guard !images.isEmpty,
                  !references.isEmpty
            else { return nil }
            return HistoryCaptureResult(
                entry: try store.createImageAndReference(
                    imageItems: images,
                    referenceItems: references,
                    activityAt: clock.now
                ),
                notice: nil
            )
        }
    }

    func pastePayload(id: UUID) throws -> HistoryPastePayload? {
        try store.pastePayload(id: id)
    }

    func thumbnailData(id: UUID) throws -> Data? {
        try store.thumbnailData(id: id)
    }

    func acquireStackPayloadLease(occurrenceID: UUID, sessionID: UUID) throws -> HistoryStackPayloadLease? {
        try store.acquireStackPayloadLease(occurrenceID: occurrenceID, sessionID: sessionID)
    }

    func releaseStackPayloadLease(_ lease: HistoryStackPayloadLease) {
        store.releaseStackPayloadLease(lease)
    }

    func revokeStackPayloadLeases(for occurrenceID: UUID) {
        store.revokeStackPayloadLeases(for: occurrenceID)
    }

    func isStackPayloadLeaseValid(_ lease: HistoryStackPayloadLease) -> Bool {
        store.isStackPayloadLeaseValid(lease)
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
        try store.setFavorite(id: id, isFavorite: isFavorite)
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

    func recentDescriptors() throws -> [HistoryOccurrenceDescriptor] {
        try service.recentDescriptors()
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
