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
    private let pagingStore: HistoryPagingStoring?
    private let typedStore: TypedHistoryStoring?
    private let richTextStore: RichTextHistoryStoring?
    private let clock: HistoryClock

    init(store: HistoryStoring, clock: HistoryClock = SystemHistoryClock()) {
        self.store = store
        pagingStore = store as? HistoryPagingStoring
        typedStore = store as? TypedHistoryStoring
        richTextStore = store as? RichTextHistoryStoring
        self.clock = clock
    }

    func entries() throws -> [HistoryEntry] {
        try store.fetchCurrent(since: retentionCutoff).filter(Self.isRenderable)
    }

    var supportsPaging: Bool {
        pagingStore != nil
    }

    func page(after cursor: HistoryPageCursor? = nil) throws -> HistoryPage {
        guard let pagedStore = pagingStore else {
            return try fallbackPage(after: cursor, query: nil)
        }
        return try pagedStore.fetchPage(
            since: retentionCutoff,
            after: cursor,
            limit: Self.pageSize
        )
    }

    func searchPage(query: String, after cursor: HistoryPageCursor? = nil) throws -> HistoryPage {
        guard let pagedStore = pagingStore else {
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
        guard let pagedStore = pagingStore else {
            return try store.fetchCurrent(since: .distantPast).first { $0.id == id }
        }
        return try pagedStore.fetchEntry(id: id)
    }

    func occurrence(id: UUID) throws -> HistoryOccurrence? {
        guard let pagedStore = pagingStore else { return nil }
        return try pagedStore.fetchOccurrence(id: id)
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

    @discardableResult
    func capture(text: String) throws -> HistoryEntry? {
        try capture(.text(text))?.entry
    }

    @discardableResult
    func capture(
        text: String,
        richTextItems: [HistoryRichTextCaptureItem]
    ) throws -> HistoryRichTextCaptureResult? {
        guard let result = try capture(.richText(text: text, items: richTextItems)) else { return nil }
        return HistoryRichTextCaptureResult(
            entry: result.entry,
            richTextSaved: result.notice == nil,
            notice: result.notice
        )
    }

    @discardableResult
    func capture(imageItems: [ManagedImageCaptureItem]) throws -> HistoryEntry? {
        try capture(.images(imageItems))?.entry
    }

    @discardableResult
    func capture(referenceItems: [HistoryReferenceCaptureItem]) throws -> HistoryEntry? {
        try capture(.references(referenceItems))?.entry
    }

    @discardableResult
    func capture(
        imageItems: [ManagedImageCaptureItem],
        referenceItems: [HistoryReferenceCaptureItem]
    ) throws -> HistoryEntry? {
        try capture(.mixed(images: imageItems, references: referenceItems))?.entry
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

    private func fallbackPage(after cursor: HistoryPageCursor?, query: String?) throws -> HistoryPage {
        var entries = try entries()
        if let query, !query.isEmpty {
            let ranked = entries.compactMap { entry in
                HistorySearchRank.classify(entry: entry, query: query).map { (entry, $0) }
            }.sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1.rawValue < rhs.1.rawValue }
                if lhs.0.activityAt != rhs.0.activityAt { return lhs.0.activityAt > rhs.0.activityAt }
                return lhs.0.id.uuidString > rhs.0.id.uuidString
            }
            let afterCursor = ranked.filter { pair in
                guard let cursor else { return true }
                guard pair.1 == cursor.searchRank else {
                    return pair.1.rawValue > (cursor.searchRank?.rawValue ?? -1)
                }
                return pair.0.activityAt < cursor.activityAt
                    || (pair.0.activityAt == cursor.activityAt && pair.0.id.uuidString < cursor.id.uuidString)
            }
            let pageEntries = Array(afterCursor.prefix(Self.pageSize))
            let descriptors = pageEntries.map { entry, rank in
                HistoryOccurrenceDescriptor(
                    id: entry.id,
                    activityAt: entry.activityAt,
                    searchRank: rank,
                    textPreview: entry.isTextOnly ? HistoryPreview.text(for: entry.text) : nil,
                    representations: entry.representations,
                    imageMetadata: entry.imageMetadata,
                    referenceMetadata: entry.referenceMetadata
                )
            }
            return HistoryPage(
                descriptors: descriptors,
                nextCursor: pageEntries.last.map {
                    HistoryPageCursor(activityAt: $0.0.activityAt, id: $0.0.id, searchRank: $0.1)
                },
                hasMore: afterCursor.count > Self.pageSize
            )
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
                textPreview: entry.isTextOnly ? HistoryPreview.text(for: entry.text) : nil,
                representations: entry.representations,
                imageMetadata: entry.imageMetadata,
                referenceMetadata: entry.referenceMetadata
            )
        }
        return HistoryPage(
            descriptors: descriptors,
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

    func capture(_ capture: HistoryCapture) throws -> HistoryCaptureResult? {
        try service.capture(capture)
    }

    func capture(text: String) throws -> HistoryEntry? {
        try service.capture(text: text)
    }

    func capture(
        text: String,
        richTextItems: [HistoryRichTextCaptureItem]
    ) throws -> HistoryRichTextCaptureResult? {
        try service.capture(text: text, richTextItems: richTextItems)
    }

    func capture(imageItems: [ManagedImageCaptureItem]) throws -> HistoryEntry? {
        try service.capture(imageItems: imageItems)
    }

    @discardableResult
    func capture(referenceItems: [HistoryReferenceCaptureItem]) throws -> HistoryEntry? {
        try service.capture(referenceItems: referenceItems)
    }

    func capture(
        imageItems: [ManagedImageCaptureItem],
        referenceItems: [HistoryReferenceCaptureItem]
    ) throws -> HistoryEntry? {
        try service.capture(imageItems: imageItems, referenceItems: referenceItems)
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
