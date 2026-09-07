import CryptoKit
import Foundation

/// Shared filesystem boundary for every History-owned payload. It centralizes
/// root containment, symlink rejection, directory creation, and temporary-file
/// cleanup so image and rich-text stores cannot drift on path safety.
struct ManagedAssetDirectory {
    enum Error: Swift.Error {
        case invalidPath
    }

    let rootURL: URL
    let fileManager: FileManager

    init(rootURL: URL, fileManager: FileManager) {
        self.rootURL = rootURL.standardizedFileURL
        self.fileManager = fileManager
    }

    func ensureDirectory(_ url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        guard isDirectory(url), !isSymbolicLink(url) else { throw Error.invalidPath }
    }

    func url(for relativePath: String, requiredPrefix: String) throws -> URL {
        guard !relativePath.isEmpty,
              !relativePath.contains(".."),
              !relativePath.hasPrefix("/"),
              relativePath.hasPrefix(requiredPrefix)
        else { throw Error.invalidPath }

        let url = rootURL.appendingPathComponent(relativePath).standardizedFileURL
        guard url.path.hasPrefix(rootURL.path + "/") else { throw Error.invalidPath }

        var componentURL = rootURL
        for component in relativePath.split(separator: "/") {
            componentURL.appendPathComponent(String(component))
            if fileManager.fileExists(atPath: componentURL.path), isSymbolicLink(componentURL) {
                throw Error.invalidPath
            }
        }
        return url
    }

    func removeContents(of directoryURL: URL) throws {
        try ensureDirectory(directoryURL)
        for url in try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) {
            try fileManager.removeItem(at: url)
        }
    }

    func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    func isSymbolicLink(_ url: URL) -> Bool {
        (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
    }
}

extension SHA256.Digest {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}

/// One writer owns each asset tree. Reconcile once, then account successful
/// commits/deletions. Unknown cleanup or failed writes invalidate the total.
final class ManagedAssetByteCounter {
    private let directory: ManagedAssetDirectory
    private var cachedBytes: Int?
    private(set) var reconciliationCount = 0

    init(rootURL: URL, fileManager: FileManager) {
        directory = ManagedAssetDirectory(rootURL: rootURL, fileManager: fileManager)
    }

    func bytes() throws -> Int {
        if let cachedBytes { return cachedBytes }
        reconciliationCount += 1
        guard directory.fileManager.fileExists(atPath: directory.rootURL.path) else {
            cachedBytes = 0
            return 0
        }
        try directory.ensureDirectory(directory.rootURL)
        var scanError: Swift.Error?
        guard let enumerator = directory.fileManager.enumerator(
            at: directory.rootURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, error in scanError = error; return false }
        ) else { throw ManagedAssetDirectory.Error.invalidPath }
        var total = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            if values.isDirectory == true {
                if enumerator.level != 1 || UUID(uuidString: url.lastPathComponent) == nil {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values.isRegularFile == true, url.pathExtension == "asset",
                  enumerator.level == 2,
                  UUID(uuidString: url.deletingLastPathComponent().lastPathComponent) != nil else { continue }
            guard let size = values.fileSize else { throw ManagedAssetDirectory.Error.invalidPath }
            total += size
        }
        if let scanError { throw scanError }
        cachedBytes = total
        return total
    }

    func didCommit(bytes: Int) {
        if let cachedBytes { self.cachedBytes = cachedBytes + bytes }
    }

    func removeFile(at url: URL) throws {
        guard directory.fileManager.fileExists(atPath: url.path) else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            try directory.fileManager.removeItem(at: url)
            if let cachedBytes, let size { self.cachedBytes = max(0, cachedBytes - size) }
            else { invalidate() }
        } catch {
            invalidate()
            throw error
        }
    }

    func invalidate() { cachedBytes = nil }
}
