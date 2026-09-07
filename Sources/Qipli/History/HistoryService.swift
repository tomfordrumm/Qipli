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
    private let typedStore: TypedHistoryStoring?
    private let richTextStore: RichTextHistoryStoring?
    private let clock: HistoryClock

    init(store: HistoryStoring, clock: HistoryClock = SystemHistoryClock()) {
        self.store = store
        typedStore = store as? TypedHistoryStoring
        richTextStore = store as? RichTextHistoryStoring
        self.clock = clock
    }

    func entries() throws -> [HistoryEntry] {
        try store.fetchCurrent(since: retentionCutoff).filter(Self.isRenderable)
    }

    func page(after cursor: HistoryPageCursor? = nil) throws -> HistoryPage {
        try store.fetchPage(since: retentionCutoff, after: cursor, limit: Self.pageSize)
    }

    func searchPage(query: String, after cursor: HistoryPageCursor? = nil) throws -> HistoryPage {
        try store.searchPage(query: query, since: retentionCutoff, after: cursor, limit: Self.pageSize)
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

    func entries() throws -> [HistoryEntry] {
        try service.entries()
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

    func capture(_ capture: HistoryCapture) throws -> HistoryCaptureResult? {
        try service.capture(capture)
    }

    func pastePayload(id: UUID) throws -> HistoryPastePayload? {
        try service.pastePayload(id: id)
    }

    func thumbnailData(id: UUID) throws -> Data? {
        try service.thumbnailData(id: id)
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
