import Foundation

enum HistoryRichTextTypePolicy {
    static let supportedTypes: [String] = ["public.rtf", "public.html"]

    static func isSupported(_ typeIdentifier: String) -> Bool {
        supportedTypes.contains(typeIdentifier)
    }
}

struct HistoryRichTextStoragePolicy: Equatable, Sendable {
    static let production = HistoryRichTextStoragePolicy(
        maxRepresentationBytes: 16 * 1024 * 1024,
        maxOccurrenceBytes: 32 * 1024 * 1024,
        maxTotalBytes: 512 * 1024 * 1024
    )

    let maxRepresentationBytes: Int
    let maxOccurrenceBytes: Int
    let maxTotalBytes: Int

    init(maxRepresentationBytes: Int, maxOccurrenceBytes: Int, maxTotalBytes: Int) {
        precondition(maxRepresentationBytes > 0)
        precondition(maxOccurrenceBytes >= maxRepresentationBytes)
        precondition(maxTotalBytes >= maxOccurrenceBytes)
        self.maxRepresentationBytes = maxRepresentationBytes
        self.maxOccurrenceBytes = maxOccurrenceBytes
        self.maxTotalBytes = maxTotalBytes
    }
}

struct HistoryRichTextCaptureRepresentation: Equatable, Sendable {
    let typeIdentifier: String
    let data: Data
}

struct HistoryRichTextCaptureItem: Equatable, Sendable {
    let order: Int
    let canonicalText: String?
    let representations: [HistoryRichTextCaptureRepresentation]

    init(
        order: Int,
        canonicalText: String? = nil,
        representations: [HistoryRichTextCaptureRepresentation]
    ) {
        self.order = order
        self.canonicalText = canonicalText
        self.representations = representations
    }
}

struct HistoryRichTextRepresentationManifest: Codable, Equatable, Sendable {
    let typeIdentifier: String
    let relativePath: String
    let byteCount: Int
    let sha256: String
}

struct HistoryRichTextItemManifest: Codable, Equatable, Sendable {
    let id: UUID
    let order: Int
    let canonicalText: String?
    let representations: [HistoryRichTextRepresentationManifest]

    init(
        id: UUID,
        order: Int,
        canonicalText: String? = nil,
        representations: [HistoryRichTextRepresentationManifest]
    ) {
        self.id = id
        self.order = order
        self.canonicalText = canonicalText
        self.representations = representations
    }
}

struct HistoryRichTextManifest: Codable, Equatable, Sendable {
    let occurrenceID: UUID
    let items: [HistoryRichTextItemManifest]
    let capturedAt: Date

    var representations: [HistoryRichTextRepresentationManifest] {
        items.flatMap(\.representations)
    }

    var totalBytes: Int {
        representations.reduce(0) { $0 + $1.byteCount }
    }
}

/// The representation kinds understood by the typed History catalogue.
/// Typed History keeps text, URLs, managed images, and local references in a
/// stable occurrence contract while payload bytes stay outside UI descriptors.
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

enum HistoryReferenceAvailability: String, Codable, Equatable, Sendable {
    case available
    case unavailable
}

struct HistoryReferenceMetadata: Codable, Equatable, Sendable {
    let displayName: String
    let fileExtension: String
    let typeIdentifier: String
    let byteCount: Int64?
    let domain: String?
    let searchText: String
    let availability: HistoryReferenceAvailability

    init(
        displayName: String,
        fileExtension: String = "",
        typeIdentifier: String,
        byteCount: Int64? = nil,
        domain: String? = nil,
        searchText: String,
        availability: HistoryReferenceAvailability = .available
    ) {
        self.displayName = displayName
        self.fileExtension = fileExtension
        self.typeIdentifier = typeIdentifier
        self.byteCount = byteCount
        self.domain = domain
        self.searchText = searchText
        self.availability = availability
    }
}

struct HistoryReferenceCaptureItem: Equatable, Sendable {
    let order: Int
    let kind: HistoryRepresentationKind
    let typeIdentifier: String
    let url: URL?
    let urlString: String?
    let metadata: HistoryReferenceMetadata

    init(
        order: Int,
        kind: HistoryRepresentationKind,
        typeIdentifier: String,
        url: URL? = nil,
        urlString: String? = nil,
        metadata: HistoryReferenceMetadata
    ) {
        self.order = order
        self.kind = kind
        self.typeIdentifier = typeIdentifier
        self.url = url
        self.urlString = urlString
        self.metadata = metadata
    }
}

struct HistoryReferenceItemManifest: Codable, Equatable, Sendable {
    let id: UUID
    let order: Int
    let kind: HistoryRepresentationKind
    let typeIdentifier: String
    let bookmarkData: Data?
    let urlString: String?
    let metadata: HistoryReferenceMetadata
}

struct HistoryReferenceManifest: Codable, Equatable, Sendable {
    let occurrenceID: UUID
    let items: [HistoryReferenceItemManifest]
    let capturedAt: Date
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

/// The normalized input to History. Clipboard routing decides the variant once;
/// persistence, UI updates, and Paste Stack collection share the same value.
enum HistoryCapture: Equatable, Sendable {
    case text(String)
    case richText(text: String, items: [HistoryRichTextCaptureItem])
    case images([ManagedImageCaptureItem])
    case references([HistoryReferenceCaptureItem])
    case mixed(images: [ManagedImageCaptureItem], references: [HistoryReferenceCaptureItem])

    var stackText: String? {
        switch self {
        case let .text(text), let .richText(text, _): text
        case .images, .references, .mixed: nil
        }
    }

    var failureMessage: String {
        switch self {
        case .text: "Qipli could not save the copied text."
        case .richText: "Qipli could not save the copied formatted text."
        case .images: "Qipli could not save the copied image."
        case .references: "Qipli could not save the copied file reference."
        case .mixed: "Qipli could not save the copied item."
        }
    }
}

struct HistoryCaptureResult: Equatable, Sendable {
    let entry: HistoryEntry
    let notice: String?
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

/// A durable typed occurrence. Payload bytes and bookmark data are deliberately
/// absent from this value until an explicit selected-paste read path.
struct HistoryOccurrence: Identifiable, Equatable, Sendable {
    let id: UUID
    let items: [HistoryPayloadItem]
    let activityAt: Date
    let managedImages: [HistoryManagedImageRepresentation]
    let referenceMetadata: [HistoryReferenceMetadata]

    init(
        id: UUID,
        items: [HistoryPayloadItem],
        activityAt: Date,
        managedImages: [HistoryManagedImageRepresentation] = [],
        referenceMetadata: [HistoryReferenceMetadata] = []
    ) {
        self.id = id
        self.items = items
        self.activityAt = activityAt
        self.managedImages = managedImages
        self.referenceMetadata = referenceMetadata
    }
}

/// The bounded value sent to the main actor for list/search rendering.
struct HistoryOccurrenceDescriptor: Identifiable, Equatable, Sendable {
    let id: UUID
    let activityAt: Date
    let searchRank: HistorySearchRank?
    let textPreview: String?
    let representations: [HistoryRepresentationDescriptor]
    let imageMetadata: [HistoryImageMetadata]
    let referenceMetadata: [HistoryReferenceMetadata]

    init(
        id: UUID,
        activityAt: Date,
        searchRank: HistorySearchRank? = nil,
        textPreview: String?,
        representations: [HistoryRepresentationDescriptor],
        imageMetadata: [HistoryImageMetadata] = [],
        referenceMetadata: [HistoryReferenceMetadata] = []
    ) {
        self.id = id
        self.activityAt = activityAt
        self.searchRank = searchRank
        self.textPreview = textPreview
        self.representations = representations
        self.imageMetadata = imageMetadata
        self.referenceMetadata = referenceMetadata
    }

    var isTextOnly: Bool {
        representations.allSatisfy { $0.kind == .text }
    }
}

enum HistorySearchRank: Int, CaseIterable, Equatable, Sendable {
    case exactOrPrefixURL = 0
    case otherTypedURL = 1
    case otherMatch = 2

    static func classify(entry: HistoryEntry, query: String) -> Self? {
        guard !query.isEmpty,
              entry.searchableMetadata.localizedCaseInsensitiveContains(query)
        else { return nil }

        let isTypedURL = entry.representations.contains { $0.kind == .url }
        guard isTypedURL else { return .otherMatch }

        let urlValues = entry.referenceMetadata
            .filter { $0.typeIdentifier == "public.url" }
            .flatMap { metadata in
            [metadata.domain, metadata.searchText]
                .compactMap { $0 }
        }
        if urlValues.contains(where: { isExactOrPrefix($0, query: query) }) {
            return .exactOrPrefixURL
        }
        return .otherTypedURL
    }

    private static func isExactOrPrefix(_ value: String, query: String) -> Bool {
        value.localizedCaseInsensitiveCompare(query) == .orderedSame
            || value.range(of: query, options: [.caseInsensitive, .anchored]) != nil
    }
}

struct HistoryPageCursor: Equatable, Sendable {
    let activityAt: Date
    let id: UUID
    let searchRank: HistorySearchRank?

    init(activityAt: Date, id: UUID, searchRank: HistorySearchRank? = nil) {
        self.activityAt = activityAt
        self.id = id
        self.searchRank = searchRank
    }
}

struct HistoryPage: Equatable, Sendable {
    let descriptors: [HistoryOccurrenceDescriptor]
    let nextCursor: HistoryPageCursor?
    let hasMore: Bool

    init(
        descriptors: [HistoryOccurrenceDescriptor],
        nextCursor: HistoryPageCursor?,
        hasMore: Bool
    ) {
        self.descriptors = descriptors
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
    let referenceMetadata: [HistoryReferenceMetadata]
    /// Rich text remains text-primary. This flag is the explicit materialization
    /// capability used by the selected-paste path.
    let hasRichText: Bool

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
        managedImageName: String? = nil,
        referenceMetadata: [HistoryReferenceMetadata] = [],
        hasRichText: Bool = false
    ) {
        self.id = id
        self.text = text
        self.activityAt = activityAt
        self.representations = representations
        self.imageMetadata = imageMetadata
        self.managedImages = managedImages
        self.managedImageItems = managedImageItems
        self.managedImageName = managedImageName
        self.referenceMetadata = referenceMetadata
        self.hasRichText = hasRichText
    }

    var isImageEntry: Bool {
        representations.contains { $0.kind == .inlineImage }
    }

    var isReferenceEntry: Bool {
        representations.contains { $0.kind == .url || $0.kind == .fileReference || $0.kind == .videoReference }
    }

    var isTypedEntry: Bool {
        !isTextOnly || hasRichText
    }

    var isTextOnly: Bool {
        representations.allSatisfy { $0.kind == .text }
    }

    var displayText: String {
        if !text.isEmpty { return text }
        if isImageEntry { return managedImageName ?? "Image" }
        if isReferenceEntry {
            let names = referenceMetadata.map { metadata in
                if metadata.typeIdentifier == "public.url", !metadata.searchText.isEmpty {
                    return metadata.searchText
                }
                return metadata.displayName
            }.filter { !$0.isEmpty }
            if let first = names.first {
                let label = names.count == 1 ? first : "\(first) + \(names.count - 1) more"
                return referenceMetadata.contains { $0.availability == .unavailable }
                    ? "Unavailable: \(label)"
                    : label
            }
        }
        return "Clipboard item"
    }

    var searchableMetadata: String {
        if isTextOnly { return text }
        let dimensions = imageMetadata
            .map { "\($0.pixelWidth)x\($0.pixelHeight)" }
            .joined(separator: " ")
        let referenceFields = referenceMetadata.flatMap {
            [$0.searchText, $0.displayName, $0.fileExtension, $0.typeIdentifier, $0.domain ?? "", $0.availability.rawValue]
        }
        return ([displayText] + representations.map(\.typeIdentifier) + [dimensions] + referenceFields)
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
