import CryptoKit
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct HistoryImageStoragePolicy: Equatable, Sendable {
    static let production = HistoryImageStoragePolicy(
        maxImageItemBytes: 32 * 1024 * 1024,
        maxOccurrenceBytes: 64 * 1024 * 1024,
        maxTotalOriginalBytes: 1 * 1024 * 1024 * 1024,
        thumbnailCacheBytes: 128 * 1024 * 1024,
        thumbnailLongEdge: 512
    )

    let maxImageItemBytes: Int
    let maxOccurrenceBytes: Int
    let maxTotalOriginalBytes: Int
    let thumbnailCacheBytes: Int
    let thumbnailLongEdge: Int

    init(
        maxImageItemBytes: Int,
        maxOccurrenceBytes: Int,
        maxTotalOriginalBytes: Int,
        thumbnailCacheBytes: Int,
        thumbnailLongEdge: Int
    ) {
        precondition(maxImageItemBytes > 0)
        precondition(maxOccurrenceBytes >= maxImageItemBytes)
        precondition(maxTotalOriginalBytes >= maxOccurrenceBytes)
        precondition(thumbnailCacheBytes > 0)
        precondition(thumbnailLongEdge > 0)
        self.maxImageItemBytes = maxImageItemBytes
        self.maxOccurrenceBytes = maxOccurrenceBytes
        self.maxTotalOriginalBytes = maxTotalOriginalBytes
        self.thumbnailCacheBytes = thumbnailCacheBytes
        self.thumbnailLongEdge = thumbnailLongEdge
    }
}

enum HistoryImageTypePolicy {
    static let supportedTypes: Set<String> = [
        UTType.png.identifier,
        UTType.tiff.identifier,
        UTType.jpeg.identifier,
        UTType.heic.identifier,
        UTType.heif.identifier,
        UTType.gif.identifier
    ]

    static func isSupported(_ typeIdentifier: String) -> Bool {
        supportedTypes.contains(typeIdentifier)
    }
}

struct ManagedImageCaptureRepresentation: Equatable, Sendable {
    let typeIdentifier: String
    let data: Data
    let pixelWidth: Int
    let pixelHeight: Int

    init(typeIdentifier: String, data: Data, pixelWidth: Int = 0, pixelHeight: Int = 0) {
        self.typeIdentifier = typeIdentifier
        self.data = data
        // Dimension probing is deferred to ManagedImageAssetStore.commit so
        // pasteboard polling never performs image parsing on the main actor.
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

enum HistoryImageDimensions {
    static func read(from data: Data) -> (width: Int, height: Int) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber
        else { return (0, 0) }
        return (width.intValue, height.intValue)
    }
}

struct ManagedImageCaptureItem: Equatable, Sendable {
    let order: Int
    let representations: [ManagedImageCaptureRepresentation]
}

struct ManagedImageAssetManifest: Codable, Equatable, Sendable {
    let occurrenceID: UUID
    let items: [ManagedImageAssetItemManifest]
    let capturedAt: Date?
    let displayName: String?

    init(
        occurrenceID: UUID,
        items: [ManagedImageAssetItemManifest],
        capturedAt: Date? = nil,
        displayName: String? = nil
    ) {
        self.occurrenceID = occurrenceID
        self.items = items
        self.capturedAt = capturedAt
        self.displayName = displayName
    }

    var representations: [HistoryManagedImageRepresentation] {
        items.flatMap(\.representations)
    }

    var totalBytes: Int {
        representations.reduce(0) { $0 + $1.metadata.byteCount }
    }
}

enum ManagedImageNaming {
    static func name(
        capturedAt: Date,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: capturedAt
        )
        return [
            "image",
            padded(components.year ?? 0, width: 4),
            padded(components.month ?? 0, width: 2),
            padded(components.day ?? 0, width: 2),
            padded(components.hour ?? 0, width: 2),
            padded(components.minute ?? 0, width: 2),
            padded(components.second ?? 0, width: 2)
        ].joined(separator: "_")
    }

    private static func padded(_ value: Int, width: Int) -> String {
        let string = String(value)
        return String(repeating: "0", count: max(0, width - string.count)) + string
    }
}

struct ManagedImageAssetItemManifest: Codable, Equatable, Sendable {
    let id: UUID
    let order: Int
    let representations: [HistoryManagedImageRepresentation]

    init(id: UUID = UUID(), order: Int, representations: [HistoryManagedImageRepresentation]) {
        self.id = id
        self.order = order
        self.representations = representations
    }

    var totalBytes: Int {
        representations.reduce(0) { $0 + $1.metadata.byteCount }
    }
}

enum ManagedImageStoreError: LocalizedError, Equatable {
    case unsupportedRepresentation
    case emptyImage
    case imageItemTooLarge
    case occurrenceTooLarge
    case storageLimitReached
    case invalidManagedPath
    case missingAsset
    case corruptAsset
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedRepresentation: "This image format is not supported yet."
        case .emptyImage: "The copied image was empty."
        case .imageItemTooLarge: "The copied image is larger than Qipli's per-item limit."
        case .occurrenceTooLarge: "The copied image group is larger than Qipli's per-copy limit."
        case .storageLimitReached: "Qipli image storage is full. Delete older images to save this one."
        case .invalidManagedPath, .missingAsset, .corruptAsset, .writeFailed:
            "Qipli could not safely save the copied image."
        }
    }
}

protocol ManagedImageStoring: AnyObject {
    func commit(
        occurrenceID: UUID,
        items: [ManagedImageCaptureItem],
        capturedAt: Date
    ) throws -> ManagedImageAssetManifest
    func read(_ representation: HistoryManagedImageRepresentation) throws -> Data
    func validate(_ manifest: ManagedImageAssetManifest) throws
    func remove(manifest: ManagedImageAssetManifest) throws
    func removeAllOwnedAssets() throws
    func cleanupTemporaryAssets() throws
    func makeThumbnail(for manifest: ManagedImageAssetManifest) throws -> Data?
}

extension ManagedImageStoring {
    func commit(occurrenceID: UUID, items: [ManagedImageCaptureItem]) throws -> ManagedImageAssetManifest {
        try commit(occurrenceID: occurrenceID, items: items, capturedAt: Date())
    }
}

/// Owns only files below the Qipli managed image root. Paths in manifests are
/// opaque relative IDs and are always resolved through the validated root.
final class ManagedImageAssetStore: ManagedImageStoring {
    let rootURL: URL
    let policy: HistoryImageStoragePolicy
    private let fileManager: FileManager

    init(
        rootURL: URL,
        policy: HistoryImageStoragePolicy = .production,
        fileManager: FileManager = .default
    ) throws {
        self.rootURL = rootURL.standardizedFileURL
        self.policy = policy
        self.fileManager = fileManager
        try fileManager.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: self.rootURL.appendingPathComponent(".tmp", isDirectory: true),
            withIntermediateDirectories: true
        )
        try cleanupTemporaryAssets()
    }

    func commit(
        occurrenceID: UUID,
        items: [ManagedImageCaptureItem],
        capturedAt: Date
    ) throws -> ManagedImageAssetManifest {
        guard !items.isEmpty else { throw ManagedImageStoreError.emptyImage }
        var manifests: [ManagedImageAssetItemManifest] = []
        var occurrenceBytes = 0

        for item in items.sorted(by: { $0.order < $1.order }) {
            guard !item.representations.isEmpty else { throw ManagedImageStoreError.emptyImage }
            var itemBytes = 0
            var representations: [HistoryManagedImageRepresentation] = []
            for representation in item.representations {
                guard HistoryImageTypePolicy.isSupported(representation.typeIdentifier) else {
                    throw ManagedImageStoreError.unsupportedRepresentation
                }
                guard !representation.data.isEmpty else { throw ManagedImageStoreError.emptyImage }
                let dimensions = (representation.pixelWidth > 0 && representation.pixelHeight > 0)
                    ? (representation.pixelWidth, representation.pixelHeight)
                    : HistoryImageDimensions.read(from: representation.data)
                itemBytes += representation.data.count
                occurrenceBytes += representation.data.count
                guard itemBytes <= policy.maxImageItemBytes else {
                    throw ManagedImageStoreError.imageItemTooLarge
                }
                guard occurrenceBytes <= policy.maxOccurrenceBytes else {
                    throw ManagedImageStoreError.occurrenceTooLarge
                }
                let representationID = UUID()
                representations.append(HistoryManagedImageRepresentation(
                    typeIdentifier: representation.typeIdentifier,
                    relativePath: "images/\(occurrenceID.uuidString)/\(UUID().uuidString)-\(representationID.uuidString).asset",
                    metadata: HistoryImageMetadata(
                        pixelWidth: dimensions.0,
                        pixelHeight: dimensions.1,
                        byteCount: representation.data.count
                    ),
                    sha256: SHA256.hash(data: representation.data).hexString
                ))
            }
            manifests.append(ManagedImageAssetItemManifest(order: item.order, representations: representations))
        }

        guard currentOriginalBytes() + occurrenceBytes <= policy.maxTotalOriginalBytes else {
            throw ManagedImageStoreError.storageLimitReached
        }

        let tempRoot = rootURL.appendingPathComponent(".tmp/\(UUID().uuidString)", isDirectory: true)
        var committedURLs: [URL] = []
        do {
            try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
            for (item, manifestItem) in zip(items.sorted(by: { $0.order < $1.order }), manifests) {
                for (representation, manifest) in zip(item.representations, manifestItem.representations) {
                    let temporaryURL = tempRoot.appendingPathComponent(UUID().uuidString)
                    try representation.data.write(to: temporaryURL, options: [.atomic])
                    let finalURL = try managedURL(for: manifest.relativePath)
                    try fileManager.createDirectory(
                        at: finalURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try fileManager.moveItem(at: temporaryURL, to: finalURL)
                    committedURLs.append(finalURL)
                }
            }
            try fileManager.removeItem(at: tempRoot)
            return ManagedImageAssetManifest(
                occurrenceID: occurrenceID,
                items: manifests,
                capturedAt: capturedAt,
                displayName: ManagedImageNaming.name(capturedAt: capturedAt)
            )
        } catch let error as ManagedImageStoreError {
            try? fileManager.removeItem(at: tempRoot)
            for url in committedURLs { try? fileManager.removeItem(at: url) }
            throw error
        } catch {
            try? fileManager.removeItem(at: tempRoot)
            for url in committedURLs { try? fileManager.removeItem(at: url) }
            throw ManagedImageStoreError.writeFailed
        }
    }

    func read(_ representation: HistoryManagedImageRepresentation) throws -> Data {
        let url = try managedURL(for: representation.relativePath)
        guard fileManager.fileExists(atPath: url.path) else { throw ManagedImageStoreError.missingAsset }
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let fileSize = values.fileSize,
              fileSize == representation.metadata.byteCount,
              fileSize <= policy.maxOccurrenceBytes
        else { throw ManagedImageStoreError.corruptAsset }
        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw ManagedImageStoreError.corruptAsset
        }
        guard data.count == representation.metadata.byteCount,
              SHA256.hash(data: data).hexString == representation.sha256
        else { throw ManagedImageStoreError.corruptAsset }
        return data
    }

    func validate(_ manifest: ManagedImageAssetManifest) throws {
        let prefix = "images/\(manifest.occurrenceID.uuidString)/"
        guard !manifest.items.isEmpty,
              manifest.representations.allSatisfy({ $0.relativePath.hasPrefix(prefix) })
        else { throw ManagedImageStoreError.invalidManagedPath }
        for representation in manifest.representations {
            _ = try managedURL(for: representation.relativePath)
        }
    }

    func remove(manifest: ManagedImageAssetManifest) throws {
        try validate(manifest)
        for representation in manifest.representations {
            let url = try managedURL(for: representation.relativePath)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
        let occurrenceURL = rootURL.appendingPathComponent("images/\(manifest.occurrenceID.uuidString)")
        if fileManager.fileExists(atPath: occurrenceURL.path) {
            try fileManager.removeItem(at: occurrenceURL)
        }
    }

    func removeAllOwnedAssets() throws {
        let imagesURL = rootURL.appendingPathComponent("images", isDirectory: true)
        if fileManager.fileExists(atPath: imagesURL.path) {
            try fileManager.removeItem(at: imagesURL)
        }
        try fileManager.createDirectory(at: imagesURL, withIntermediateDirectories: true)
        try cleanupTemporaryAssets()
    }

    func cleanupTemporaryAssets() throws {
        let temporaryURL = rootURL.appendingPathComponent(".tmp", isDirectory: true)
        guard fileManager.fileExists(atPath: temporaryURL.path) else {
            try fileManager.createDirectory(at: temporaryURL, withIntermediateDirectories: true)
            return
        }
        for url in try fileManager.contentsOfDirectory(at: temporaryURL, includingPropertiesForKeys: nil) {
            try fileManager.removeItem(at: url)
        }
    }

    func makeThumbnail(for manifest: ManagedImageAssetManifest) throws -> Data? {
        try validate(manifest)
        guard let representation = manifest.representations.first else { return nil }
        let data = try read(representation)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ManagedImageStoreError.corruptAsset
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: policy.thumbnailLongEdge
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ManagedImageStoreError.corruptAsset
        }
        let bitmap = NSBitmapImageRep(cgImage: image)
        return bitmap.representation(using: .png, properties: [:])
    }

    private func managedURL(for relativePath: String) throws -> URL {
        guard !relativePath.isEmpty,
              !relativePath.contains(".."),
              !relativePath.hasPrefix("/"),
              relativePath.hasPrefix("images/")
        else { throw ManagedImageStoreError.invalidManagedPath }
        let url = rootURL.appendingPathComponent(relativePath).standardizedFileURL
        guard url.path.hasPrefix(rootURL.path + "/") else {
            throw ManagedImageStoreError.invalidManagedPath
        }
        var componentURL = rootURL
        for component in relativePath.split(separator: "/") {
            componentURL.appendPathComponent(String(component))
            if fileManager.fileExists(atPath: componentURL.path),
               (try? fileManager.destinationOfSymbolicLink(atPath: componentURL.path)) != nil {
                throw ManagedImageStoreError.invalidManagedPath
            }
        }
        return url
    }

    private func currentOriginalBytes() -> Int {
        let imagesURL = rootURL.appendingPathComponent("images", isDirectory: true)
        guard let enumerator = fileManager.enumerator(
            at: imagesURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        return enumerator.reduce(0) { result, item in
            guard let url = item as? URL,
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize
            else { return result }
            return result + size
        }
    }
}

private extension SHA256.Digest {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
