import Foundation
@testable import Qipli

@MainActor
extension HistoryViewModel {
    var visibleEntries: [HistoryEntry] {
        visibleDescriptors.map { descriptor in
            HistoryEntry(id: descriptor.id, text: descriptor.textPreview ?? "", activityAt: descriptor.activityAt, representations: descriptor.representations, imageMetadata: descriptor.imageMetadata, referenceMetadata: descriptor.referenceMetadata)
        }
    }
}

@MainActor
extension HistoryViewModel {
    @discardableResult
    func recordExternalText(_ text: String) async -> HistoryEntry? {
        await recordExternalCapture(.text(text))
    }
    @discardableResult
    func recordExternalRichText(
        _ text: String,
        items: [HistoryRichTextCaptureItem]
    ) async -> HistoryEntry? {
        await recordExternalCapture(.richText(text: text, items: items))
    }
    @discardableResult
    func recordExternalImage(_ items: [ManagedImageCaptureItem]) async -> HistoryEntry? {
        await recordExternalCapture(.images(items))
    }
    @discardableResult
    func recordExternalReference(_ items: [HistoryReferenceCaptureItem]) async -> HistoryEntry? {
        await recordExternalCapture(.references(items))
    }
    @discardableResult
    func recordExternalMixed(
        imageItems: [ManagedImageCaptureItem],
        referenceItems: [HistoryReferenceCaptureItem]
    ) async -> HistoryEntry? {
        await recordExternalCapture(.mixed(images: imageItems, references: referenceItems))
    }
}

extension HistoryService {
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
}

@MainActor
extension StackCollectionCaptureCoordinator {
    func enqueueExternalRichText(
        _ items: [HistoryRichTextCaptureItem],
        canonicalText: String,
        observedChangeCount: Int,
        stackCaptureContext: StackCaptureContext?
    ) {
        enqueue(
            .richText(text: canonicalText, items: items),
            observedChangeCount: observedChangeCount,
            stackCaptureContext: stackCaptureContext
        )
    }
    func enqueueExternalImage(
        _ items: [ManagedImageCaptureItem],
        observedChangeCount: Int,
        stackCaptureContext: StackCaptureContext?
    ) {
        enqueue(.images(items), observedChangeCount: observedChangeCount, stackCaptureContext: stackCaptureContext)
    }
    func enqueueExternalReference(
        _ items: [HistoryReferenceCaptureItem],
        observedChangeCount: Int,
        stackCaptureContext: StackCaptureContext?
    ) {
        enqueue(.references(items), observedChangeCount: observedChangeCount, stackCaptureContext: stackCaptureContext)
    }
    func enqueueExternalMixed(
        imageItems: [ManagedImageCaptureItem],
        referenceItems: [HistoryReferenceCaptureItem],
        observedChangeCount: Int,
        stackCaptureContext: StackCaptureContext?
    ) {
        enqueue(
            .mixed(images: imageItems, references: referenceItems),
            observedChangeCount: observedChangeCount,
            stackCaptureContext: stackCaptureContext
        )
    }
}


/// Stable, payload-free performance boundaries. Operation names must never be
/// derived from clipboard text, search queries, previews, or entry identifiers.
enum PerformanceOperation: String, CaseIterable, Sendable {
    case historyFetch
    case historySearch
    case previewConstruction
    case stackTraversal
    case pasteboardPoll
}

/// A safe aggregate observation suitable for local tests and Debug tooling.
/// It deliberately has no free-form metadata field where product payload could leak.
struct PerformanceObservation: Equatable, Sendable {
    let operation: PerformanceOperation
    let itemCount: Int
    let elapsedNanoseconds: UInt64
}

struct PerformanceProbe {
    typealias Clock = () -> UInt64
    typealias Recorder = (PerformanceObservation) -> Void

    private let clock: Clock
    private let recorder: Recorder

    init(
        clock: @escaping Clock = { DispatchTime.now().uptimeNanoseconds },
        recorder: @escaping Recorder = { _ in }
    ) {
        self.clock = clock
        self.recorder = recorder
    }

    @discardableResult
    func measure<Result>(
        _ operation: PerformanceOperation,
        itemCount: Int,
        _ work: () throws -> Result
    ) rethrows -> Result {
        let startedAt = clock()
        defer {
            let finishedAt = clock()
            recorder(PerformanceObservation(
                operation: operation,
                itemCount: max(0, itemCount),
                elapsedNanoseconds: finishedAt >= startedAt ? finishedAt - startedAt : 0
            ))
        }
        return try work()
    }
}


// Test stores implement the same bounded paging protocol as production. This
// small in-memory adapter belongs only to tests, never the shipped application.
extension HistoryStoring {
    func fetchPage(since cutoff: Date, after cursor: HistoryPageCursor?, limit: Int) throws -> HistoryPage {
        try testPage(since: cutoff, after: cursor, limit: limit, query: nil)
    }

    func searchPage(query: String, since cutoff: Date, after cursor: HistoryPageCursor?, limit: Int) throws -> HistoryPage {
        try testPage(since: cutoff, after: cursor, limit: limit, query: query)
    }

    func fetchEntry(id: UUID) throws -> HistoryEntry? {
        try fetchCurrent(since: .distantPast).first { $0.id == id }
    }

    func fetchOccurrence(id: UUID) throws -> HistoryOccurrence? { nil }

    private func testPage(since cutoff: Date, after cursor: HistoryPageCursor?, limit: Int, query: String?) throws -> HistoryPage {
        let entries = try fetchCurrent(since: cutoff).filter { $0.isTypedEntry || HistoryTextPolicy.shouldCapture($0.text) }
        let ranked = entries.compactMap { entry -> (HistoryEntry, HistorySearchRank?)? in
            guard let query, !query.isEmpty else { return (entry, nil) }
            guard let rank = HistorySearchRank.classify(entry: entry, query: query) else { return nil }
            return (entry, rank)
        }.sorted {
            if $0.1 != $1.1 { return ($0.1?.rawValue ?? 0) < ($1.1?.rawValue ?? 0) }
            if $0.0.activityAt != $1.0.activityAt { return $0.0.activityAt > $1.0.activityAt }
            return $0.0.id.uuidString > $1.0.id.uuidString
        }.filter { entry, rank in
            guard let cursor else { return true }
            if rank != cursor.searchRank { return (rank?.rawValue ?? 0) > (cursor.searchRank?.rawValue ?? 0) }
            return entry.activityAt < cursor.activityAt || (entry.activityAt == cursor.activityAt && entry.id.uuidString < cursor.id.uuidString)
        }
        let descriptors = ranked.prefix(limit).map { entry, rank in
            HistoryDisplayMetadata(entry: entry).descriptor(id: entry.id, activityAt: entry.activityAt, rank: rank)
        }
        return HistoryPage(descriptors: descriptors, nextCursor: descriptors.last.map {
            HistoryPageCursor(activityAt: $0.activityAt, id: $0.id, searchRank: $0.searchRank)
        }, hasMore: ranked.count > limit)
    }
}
