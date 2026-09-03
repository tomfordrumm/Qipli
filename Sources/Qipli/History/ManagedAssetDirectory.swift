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
