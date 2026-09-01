import Foundation

/// The representation kinds understood by the typed History catalogue.
/// S023 only persists text; the other cases reserve the stable contract used
/// by the media slices without materialising their payloads in the UI.
enum HistoryRepresentationKind: String, Codable, Equatable, Sendable {
    case text
    case url
    case inlineImage
    case fileReference
    case videoReference
}

struct HistoryRepresentationDescriptor: Equatable, Sendable {
    let kind: HistoryRepresentationKind
    let typeIdentifier: String
}

struct HistoryImageMetadata: Codable, Equatable, Sendable {
    let pixelWidth: Int
    let pixelHeight: Int
    let byteCount: Int

    init(pixelWidth: Int = 0, pixelHeight: Int = 0, byteCount: Int) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.byteCount = byteCount
    }
}

struct HistoryManagedImageRepresentation: Codable, Equatable, Sendable {
    let typeIdentifier: String
    let relativePath: String
    let metadata: HistoryImageMetadata
    let sha256: String
}

struct HistoryPasteboardRepresentationPayload: Equatable, Sendable {
    let typeIdentifier: String
    let data: Data
}

struct HistoryPasteboardItemPayload: Equatable, Sendable {
    let representations: [HistoryPasteboardRepresentationPayload]
}

struct HistoryPastePayload: Equatable, Sendable {
    let items: [HistoryPasteboardItemPayload]
}

struct HistoryPayloadItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let order: Int
    let representations: [HistoryRepresentationDescriptor]

    init(
        id: UUID = UUID(),
        order: Int,
        representations: [HistoryRepresentationDescriptor]
    ) {
        self.id = id
        self.order = order
        self.representations = representations
    }
}

/// A durable typed occurrence. Payload bytes and references are deliberately
/// absent from this value until a later media slice adds an explicit read path.
struct HistoryOccurrence: Identifiable, Equatable, Sendable {
    let id: UUID
    let items: [HistoryPayloadItem]
    let activityAt: Date
    let managedImages: [HistoryManagedImageRepresentation]

    init(
        id: UUID,
        items: [HistoryPayloadItem],
        activityAt: Date,
        managedImages: [HistoryManagedImageRepresentation] = []
    ) {
        self.id = id
        self.items = items
        self.activityAt = activityAt
        self.managedImages = managedImages
    }
}

/// The bounded value sent to the main actor for list/search rendering.
struct HistoryOccurrenceDescriptor: Identifiable, Equatable, Sendable {
    let id: UUID
    let activityAt: Date
    let textPreview: String?
    let representations: [HistoryRepresentationDescriptor]
    let imageMetadata: [HistoryImageMetadata]

    init(
        id: UUID,
        activityAt: Date,
        textPreview: String?,
        representations: [HistoryRepresentationDescriptor],
        imageMetadata: [HistoryImageMetadata] = []
    ) {
        self.id = id
        self.activityAt = activityAt
        self.textPreview = textPreview
        self.representations = representations
        self.imageMetadata = imageMetadata
    }

    var isTextOnly: Bool {
        representations.allSatisfy { $0.kind == .text }
    }
}

struct HistoryPageCursor: Equatable, Sendable {
    let activityAt: Date
    let id: UUID
}

struct HistoryPage: Equatable, Sendable {
    let descriptors: [HistoryOccurrenceDescriptor]
    /// Exact text is materialized only for this bounded text page so the
    /// existing synchronous paste bridge remains exact. Media payloads never
    /// enter this collection.
    let textEntries: [HistoryEntry]
    /// Bounded entries used by the existing History UI. Media entries contain
    /// only typed metadata and managed asset references, never image bytes.
    let entries: [HistoryEntry]
    let nextCursor: HistoryPageCursor?
    let hasMore: Bool

    init(
        descriptors: [HistoryOccurrenceDescriptor],
        textEntries: [HistoryEntry] = [],
        entries: [HistoryEntry]? = nil,
        nextCursor: HistoryPageCursor?,
        hasMore: Bool
    ) {
        self.descriptors = descriptors
        self.textEntries = textEntries
        self.entries = entries ?? textEntries
        self.nextCursor = nextCursor
        self.hasMore = hasMore
    }
}

/// A single clipboard occurrence. Equal text copied twice remains two entries.
struct HistoryEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let text: String
    /// Initial capture time, subsequently updated only after successful history paste dispatch.
    let activityAt: Date
    let representations: [HistoryRepresentationDescriptor]
    let imageMetadata: [HistoryImageMetadata]
    let managedImages: [HistoryManagedImageRepresentation]
    let managedImageItems: [ManagedImageAssetItemManifest]
    let managedImageName: String?

    init(
        id: UUID,
        text: String,
        activityAt: Date,
        representations: [HistoryRepresentationDescriptor] = [
            HistoryRepresentationDescriptor(kind: .text, typeIdentifier: "public.utf8-plain-text")
        ],
        imageMetadata: [HistoryImageMetadata] = [],
        managedImages: [HistoryManagedImageRepresentation] = [],
        managedImageItems: [ManagedImageAssetItemManifest] = [],
        managedImageName: String? = nil
    ) {
        self.id = id
        self.text = text
        self.activityAt = activityAt
        self.representations = representations
        self.imageMetadata = imageMetadata
        self.managedImages = managedImages
        self.managedImageItems = managedImageItems
        self.managedImageName = managedImageName
    }

    var isImageEntry: Bool {
        representations.contains { $0.kind == .inlineImage }
    }

    var isTextOnly: Bool {
        representations.allSatisfy { $0.kind == .text }
    }

    var displayText: String {
        if !text.isEmpty { return text }
        if isImageEntry { return managedImageName ?? "Image" }
        return "Clipboard item"
    }

    var searchableMetadata: String {
        if isTextOnly { return text }
        let dimensions = imageMetadata
            .map { "\($0.pixelWidth)x\($0.pixelHeight)" }
            .joined(separator: " ")
        return ([displayText] + representations.map(\.typeIdentifier) + [dimensions])
            .joined(separator: " ")
    }
}

enum BoundedTextPreview {
    /// Builds a display-only value without asking String for its full Character count.
    /// `didTraverse` is an internal measurement seam and must never retain payload data.
    static func text(
        for fullText: String,
        maximumCharacters: Int,
        didTraverse: ((Character) -> Void)? = nil
    ) -> String {
        precondition(maximumCharacters >= 0)
        var boundary = fullText.startIndex
        var traversed = 0
        while boundary != fullText.endIndex, traversed <= maximumCharacters {
            let character = fullText[boundary]
            didTraverse?(character)
            boundary = fullText.index(after: boundary)
            traversed += 1
        }

        guard traversed > maximumCharacters else { return fullText }
        let displayEnd = fullText.index(before: boundary)
        return String(fullText[..<displayEnd]) + "…"
    }
}

enum HistoryPreview {
    static let maximumCharacters = 240

    static func text(for fullText: String) -> String {
        BoundedTextPreview.text(for: fullText, maximumCharacters: maximumCharacters)
    }
}
