import CryptoKit
import Foundation

struct HistoryRichTextCaptureResult: Equatable, Sendable {
    let entry: HistoryEntry
    let richTextSaved: Bool
    let notice: String?
}

protocol RichTextHistoryStoring: AnyObject {
    func createRichText(
        text: String,
        items: [HistoryRichTextCaptureItem],
        activityAt: Date
    ) throws -> HistoryRichTextCaptureResult
}

protocol HistoryRichTextAssetStoring: AnyObject {
    func commit(
        occurrenceID: UUID,
        items: [HistoryRichTextCaptureItem],
        capturedAt: Date
    ) throws -> HistoryRichTextManifest
    func read(_ representation: HistoryRichTextRepresentationManifest) throws -> Data
    func validate(_ manifest: HistoryRichTextManifest) throws
    func remove(manifest: HistoryRichTextManifest) throws
    func removeAllOwnedAssets() throws
    func removeOwnedAssets(for occurrenceID: UUID) throws
    func cleanupTemporaryAssets() throws
    func cleanupOrphanAssets(knownOccurrenceIDs: Set<UUID>) throws
}

enum HistoryRichTextStoreError: LocalizedError, Equatable {
    case emptyRepresentation
    case representationTooLarge
    case occurrenceTooLarge
    case storageLimitReached
    case invalidManagedPath
    case missingAsset
    case corruptAsset
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .emptyRepresentation:
            return "The copied formatted text was empty."
        case .representationTooLarge:
            return "The copied formatting is larger than Qipli's per-format limit."
        case .occurrenceTooLarge:
            return "The copied formatting is larger than Qipli's per-copy limit."
        case .storageLimitReached:
            return "Qipli formatted-text storage is full."
        case .invalidManagedPath, .missingAsset, .corruptAsset, .writeFailed:
            return "Qipli could not safely save the copied formatting."
        }
    }
}

/// Stores raw RTF/HTML bytes below a Qipli-owned root. Manifests contain only
/// opaque IDs, so source paths, URLs and markup never become storage paths.
final class HistoryRichTextAssetStore: HistoryRichTextAssetStoring {
    let rootURL: URL
    let policy: HistoryRichTextStoragePolicy
    private let fileManager: FileManager
    private let assetDirectory: ManagedAssetDirectory

    init(
        rootURL: URL,
        policy: HistoryRichTextStoragePolicy = .production,
        fileManager: FileManager = .default
    ) throws {
        let assetDirectory = ManagedAssetDirectory(rootURL: rootURL, fileManager: fileManager)
        self.rootURL = assetDirectory.rootURL
        self.policy = policy
        self.fileManager = fileManager
        self.assetDirectory = assetDirectory
        try ensureManagedDirectory(self.rootURL)
        try ensureManagedDirectory(self.rootURL.appendingPathComponent(".tmp", isDirectory: true))
        try ensureManagedDirectory(self.rootURL.appendingPathComponent("rich", isDirectory: true))
        try cleanupTemporaryAssets()
    }

    func commit(
        occurrenceID: UUID,
        items: [HistoryRichTextCaptureItem],
        capturedAt: Date
    ) throws -> HistoryRichTextManifest {
        let sortedItems = items.sorted { $0.order < $1.order }
        guard !sortedItems.isEmpty else { throw HistoryRichTextStoreError.emptyRepresentation }
        var manifests: [HistoryRichTextItemManifest] = []
        var occurrenceBytes = 0

        for item in sortedItems {
            var representations: [HistoryRichTextRepresentationManifest] = []
            for representation in item.representations {
                guard HistoryRichTextTypePolicy.isSupported(representation.typeIdentifier),
                      !representation.data.isEmpty
                else { throw HistoryRichTextStoreError.emptyRepresentation }
                guard representation.data.count <= policy.maxRepresentationBytes else {
                    throw HistoryRichTextStoreError.representationTooLarge
                }
                occurrenceBytes += representation.data.count
                guard occurrenceBytes <= policy.maxOccurrenceBytes else {
                    throw HistoryRichTextStoreError.occurrenceTooLarge
                }
                let representationID = UUID()
                representations.append(HistoryRichTextRepresentationManifest(
                    typeIdentifier: representation.typeIdentifier,
                    relativePath: "rich/\(occurrenceID.uuidString)/\(representationID.uuidString).asset",
                    byteCount: representation.data.count,
                    sha256: SHA256.hash(data: representation.data).hexString
                ))
            }
            guard !representations.isEmpty else { throw HistoryRichTextStoreError.emptyRepresentation }
            manifests.append(HistoryRichTextItemManifest(
                id: UUID(),
                order: item.order,
                canonicalText: item.canonicalText,
                representations: representations
            ))
        }

        guard currentBytes() + occurrenceBytes <= policy.maxTotalBytes else {
            throw HistoryRichTextStoreError.storageLimitReached
        }

        let manifest = HistoryRichTextManifest(
            occurrenceID: occurrenceID,
            items: manifests,
            capturedAt: capturedAt
        )
        let tempRoot = rootURL.appendingPathComponent(".tmp/\(UUID().uuidString)", isDirectory: true)
        var committedURLs: [URL] = []
        do {
            try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
            for (item, manifestItem) in zip(sortedItems, manifests) {
                for (representation, manifestRepresentation) in zip(item.representations, manifestItem.representations) {
                    let temporaryURL = tempRoot.appendingPathComponent(UUID().uuidString)
                    try representation.data.write(to: temporaryURL, options: [.atomic])
                    let finalURL = try managedURL(for: manifestRepresentation.relativePath)
                    try fileManager.createDirectory(
                        at: finalURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try fileManager.moveItem(at: temporaryURL, to: finalURL)
                    committedURLs.append(finalURL)
                }
            }
            try fileManager.removeItem(at: tempRoot)
            return manifest
        } catch {
            try? fileManager.removeItem(at: tempRoot)
            for url in committedURLs { try? fileManager.removeItem(at: url) }
            throw (error as? HistoryRichTextStoreError) ?? .writeFailed
        }
    }

    func read(_ representation: HistoryRichTextRepresentationManifest) throws -> Data {
        let url = try managedURL(for: representation.relativePath)
        guard fileManager.fileExists(atPath: url.path) else {
            throw HistoryRichTextStoreError.missingAsset
        }
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              values.fileSize == representation.byteCount,
              representation.byteCount <= policy.maxRepresentationBytes
        else { throw HistoryRichTextStoreError.corruptAsset }
        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch { throw HistoryRichTextStoreError.corruptAsset }
        guard data.count == representation.byteCount,
              SHA256.hash(data: data).hexString == representation.sha256
        else { throw HistoryRichTextStoreError.corruptAsset }
        return data
    }

    func validate(_ manifest: HistoryRichTextManifest) throws {
        let prefix = "rich/\(manifest.occurrenceID.uuidString)/"
        guard !manifest.items.isEmpty,
              !manifest.representations.isEmpty,
              manifest.representations.allSatisfy({
                  HistoryRichTextTypePolicy.isSupported($0.typeIdentifier) && $0.relativePath.hasPrefix(prefix)
              })
        else { throw HistoryRichTextStoreError.invalidManagedPath }
        guard manifest.totalBytes <= policy.maxOccurrenceBytes else {
            throw HistoryRichTextStoreError.corruptAsset
        }
        guard manifest.representations.allSatisfy({
            $0.byteCount > 0 && $0.byteCount <= policy.maxRepresentationBytes
        }) else {
            throw HistoryRichTextStoreError.corruptAsset
        }
        for representation in manifest.representations {
            _ = try managedURL(for: representation.relativePath)
        }
    }

    func remove(manifest: HistoryRichTextManifest) throws {
        try validate(manifest)
        for representation in manifest.representations {
            let url = try managedURL(for: representation.relativePath)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
        try removeEmptyOccurrenceDirectory(for: manifest.occurrenceID)
    }

    func removeAllOwnedAssets() throws {
        let richURL = rootURL.appendingPathComponent("rich", isDirectory: true)
        try ensureManagedDirectory(richURL)
        for url in try fileManager.contentsOfDirectory(at: richURL, includingPropertiesForKeys: nil) {
            guard UUID(uuidString: url.lastPathComponent) != nil,
                  isDirectory(url),
                  !isSymbolicLink(url)
            else { continue }
            try fileManager.removeItem(at: url)
        }
        try cleanupTemporaryAssets()
    }

    func removeOwnedAssets(for occurrenceID: UUID) throws {
        let url = rootURL.appendingPathComponent("rich/\(occurrenceID.uuidString)", isDirectory: true)
        guard fileManager.fileExists(atPath: url.path), isDirectory(url), !isSymbolicLink(url) else { return }
        try fileManager.removeItem(at: url)
    }

    func cleanupTemporaryAssets() throws {
        let temporaryURL = rootURL.appendingPathComponent(".tmp", isDirectory: true)
        do { try assetDirectory.removeContents(of: temporaryURL) }
        catch { throw HistoryRichTextStoreError.invalidManagedPath }
    }

    func cleanupOrphanAssets(knownOccurrenceIDs: Set<UUID>) throws {
        let richURL = rootURL.appendingPathComponent("rich", isDirectory: true)
        try ensureManagedDirectory(richURL)
        for url in try fileManager.contentsOfDirectory(at: richURL, includingPropertiesForKeys: nil) {
            guard let occurrenceID = UUID(uuidString: url.lastPathComponent),
                  isDirectory(url),
                  !isSymbolicLink(url),
                  !knownOccurrenceIDs.contains(occurrenceID)
            else { continue }
            try fileManager.removeItem(at: url)
        }
    }

    private func managedURL(for relativePath: String) throws -> URL {
        do { return try assetDirectory.url(for: relativePath, requiredPrefix: "rich/") }
        catch { throw HistoryRichTextStoreError.invalidManagedPath }
    }

    private func ensureManagedDirectory(_ url: URL) throws {
        do { try assetDirectory.ensureDirectory(url) }
        catch { throw HistoryRichTextStoreError.invalidManagedPath }
    }

    private func removeEmptyOccurrenceDirectory(for occurrenceID: UUID) throws {
        let url = rootURL.appendingPathComponent("rich/\(occurrenceID.uuidString)")
        guard fileManager.fileExists(atPath: url.path), isDirectory(url), !isSymbolicLink(url),
              try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).isEmpty
        else { return }
        try fileManager.removeItem(at: url)
    }

    private func currentBytes() -> Int {
        let richURL = rootURL.appendingPathComponent("rich", isDirectory: true)
        guard isDirectory(richURL), !isSymbolicLink(richURL),
              let enumerator = fileManager.enumerator(at: richURL, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
        else { return 0 }
        return enumerator.reduce(0) { result, item in
            guard let url = item as? URL,
                  url.pathExtension == "asset",
                  UUID(uuidString: url.deletingLastPathComponent().lastPathComponent) != nil,
                  !isSymbolicLink(url.deletingLastPathComponent()),
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize
            else { return result }
            return result + size
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        assetDirectory.isDirectory(url)
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        assetDirectory.isSymbolicLink(url)
    }
}
