import AppKit
import Foundation
import UniformTypeIdentifiers

struct PasteboardRepresentationInventory: Equatable, Sendable {
    let itemCount: Int
    let representationCounts: [String: Int]
}

struct PasteboardTypedChange: Equatable, Sendable {
    let changeCount: Int
    let imageItems: [ManagedImageCaptureItem]
    let referenceItems: [HistoryReferenceCaptureItem]

    init(
        changeCount: Int,
        imageItems: [ManagedImageCaptureItem] = [],
        referenceItems: [HistoryReferenceCaptureItem] = []
    ) {
        self.changeCount = changeCount
        self.imageItems = imageItems
        self.referenceItems = referenceItems
    }
}

/// A payload-free probe for deciding the future typed allowlist. It reads only
/// item/type shape; it never asks NSPasteboard for a value or emits one.
enum PasteboardPlatformProbe {
    static func inventory(for pasteboard: NSPasteboard) -> PasteboardRepresentationInventory {
        inventory(for: pasteboard.pasteboardItems ?? [])
    }

    static func inventory(for items: [NSPasteboardItem]) -> PasteboardRepresentationInventory {
        var counts: [String: Int] = [:]
        for item in items {
            for type in item.types {
                counts[type.rawValue, default: 0] += 1
            }
        }
        return PasteboardRepresentationInventory(
            itemCount: items.count,
            representationCounts: counts
        )
    }
}

protocol PasteboardReading: AnyObject {
    var changeCount: Int { get }
    func textValue() -> String?
}

protocol TypedPasteboardReading: PasteboardReading {
    func typedImageChange(changeCount: Int) -> PasteboardTypedChange?
}

struct PasteboardTextChange: Equatable {
    let changeCount: Int
    let text: String
}

final class SystemPasteboardReader: TypedPasteboardReading, @unchecked Sendable {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int { pasteboard.changeCount }

    func textValue() -> String? {
        pasteboard.string(forType: .string)
    }

    /// Used by the controlled typed-capture probe. Normal polling still falls
    /// back to text only when no supported typed representation is present.
    func representationInventory() -> PasteboardRepresentationInventory {
        PasteboardPlatformProbe.inventory(for: pasteboard)
    }

    func typedImageChange(changeCount: Int) -> PasteboardTypedChange? {
        guard let items = pasteboard.pasteboardItems else { return nil }
        var imageItems: [ManagedImageCaptureItem] = []
        var referenceItems: [HistoryReferenceCaptureItem] = []
        for (index, item) in items.enumerated() {
            let representations = item.types.compactMap { type -> ManagedImageCaptureRepresentation? in
                let typeIdentifier = type.rawValue
                guard HistoryImageTypePolicy.isSupported(typeIdentifier),
                      let data = item.data(forType: type),
                      !data.isEmpty
                else { return nil }
                return ManagedImageCaptureRepresentation(typeIdentifier: typeIdentifier, data: data)
            }
            if !representations.isEmpty {
                imageItems.append(ManagedImageCaptureItem(order: index, representations: representations))
            }
            if let reference = referenceItem(for: item, order: index) {
                referenceItems.append(reference)
            }
        }
        guard !imageItems.isEmpty || !referenceItems.isEmpty else { return nil }
        return PasteboardTypedChange(
            changeCount: changeCount,
            imageItems: imageItems,
            referenceItems: referenceItems
        )
    }

    private func referenceItem(for item: NSPasteboardItem, order: Int) -> HistoryReferenceCaptureItem? {
        if let fileURL = pasteboardURL(for: item, type: .fileURL) {
            return HistoryReferenceCaptureItem(
                order: order,
                kind: Self.fileKind(for: fileURL),
                typeIdentifier: Self.fileTypeIdentifier(for: fileURL),
                url: fileURL,
                metadata: Self.fileMetadata(for: fileURL)
            )
        }

        guard let value = item.string(forType: .URL),
              let url = URL(string: value),
              Self.isSupportedWebURL(url)
        else { return nil }
        let host = url.host ?? ""
        return HistoryReferenceCaptureItem(
            order: order,
            kind: .url,
            typeIdentifier: NSPasteboard.PasteboardType.URL.rawValue,
            urlString: value,
            metadata: HistoryReferenceMetadata(
                displayName: host.isEmpty ? value : host,
                typeIdentifier: NSPasteboard.PasteboardType.URL.rawValue,
                domain: host.isEmpty ? nil : host,
                searchText: value
            )
        )
    }

    private func pasteboardURL(for item: NSPasteboardItem, type: NSPasteboard.PasteboardType) -> URL? {
        if let url = item.propertyList(forType: type) as? URL, url.isFileURL { return url }
        if let url = item.propertyList(forType: type) as? NSURL, (url as URL).isFileURL { return url as URL }
        if let string = item.propertyList(forType: type) as? String,
           let url = URL(string: string), url.isFileURL { return url }
        if let string = item.string(forType: type),
           let url = URL(string: string), url.isFileURL { return url }
        if let data = item.data(forType: type),
           let string = String(data: data, encoding: .utf8),
           let url = URL(string: string), url.isFileURL { return url }
        return nil
    }

    private static func isSupportedWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private static func fileKind(for url: URL) -> HistoryRepresentationKind {
        let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        let videoExtensions = Set(["mov", "mp4", "m4v", "avi", "mkv", "webm", "mpeg", "mpg", "wmv", "flv", "3gp"])
        return contentType?.conforms(to: .movie) == true || videoExtensions.contains(url.pathExtension.lowercased())
            ? .videoReference
            : .fileReference
    }

    private static func fileTypeIdentifier(for url: URL) -> String {
        let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        return contentType?.identifier ?? (fileKind(for: url) == .videoReference ? UTType.movie.identifier : UTType.data.identifier)
    }

    private static func fileMetadata(for url: URL) -> HistoryReferenceMetadata {
        let values = try? url.resourceValues(forKeys: [.nameKey, .fileSizeKey, .contentTypeKey])
        let name = values?.name ?? url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        let typeIdentifier = values?.contentType?.identifier ?? fileTypeIdentifier(for: url)
        let byteCount = values?.fileSize.map(Int64.init)
        let availability: HistoryReferenceAvailability = FileManager.default.isReadableFile(atPath: url.path)
            ? .available
            : .unavailable
        return HistoryReferenceMetadata(
            displayName: name,
            fileExtension: ext,
            typeIdentifier: typeIdentifier,
            byteCount: byteCount,
            searchText: [name, ext, typeIdentifier].joined(separator: " "),
            availability: availability
        )
    }
}

@MainActor
protocol PasteboardPollCancellation: AnyObject {
    func cancel()
}

@MainActor
protocol PasteboardPollScheduling: AnyObject {
    func schedule(
        interval: TimeInterval,
        tolerance: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> PasteboardPollCancellation
}

@MainActor
final class TimerPasteboardPollCancellation: PasteboardPollCancellation {
    private var timer: Timer?

    init(timer: Timer) {
        self.timer = timer
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }
}

@MainActor
final class RunLoopPasteboardPollScheduler: PasteboardPollScheduling {
    func schedule(
        interval: TimeInterval,
        tolerance: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> PasteboardPollCancellation {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated {
                action()
            }
        }
        timer.tolerance = tolerance
        RunLoop.main.add(timer, forMode: .common)
        return TimerPasteboardPollCancellation(timer: timer)
    }
}

/// Polls the system pasteboard. A suppression is tied to one exact change number, never its text.
@MainActor
final class PasteboardMonitor {
    nonisolated static let productionInterval: TimeInterval = 0.35
    nonisolated static let productionTolerance: TimeInterval = 0.05

    private let pasteboard: PasteboardReading
    private let scheduler: PasteboardPollScheduling
    private let onExternalText: (PasteboardTextChange) -> Void
    private let onExternalChange: ((PasteboardTypedChange) -> Void)?
    private var lastChangeCount: Int?
    private var ignoredChanges = Set<Int>()
    private var scheduledPoll: PasteboardPollCancellation?

    init(
        pasteboard: PasteboardReading = SystemPasteboardReader(),
        scheduler: PasteboardPollScheduling? = nil,
        onExternalText: @escaping (PasteboardTextChange) -> Void,
        onExternalChange: ((PasteboardTypedChange) -> Void)? = nil
    ) {
        self.pasteboard = pasteboard
        self.scheduler = scheduler ?? RunLoopPasteboardPollScheduler()
        self.onExternalText = onExternalText
        self.onExternalChange = onExternalChange
    }

    var currentChangeCount: Int { pasteboard.changeCount }

    func start(
        interval: TimeInterval = productionInterval,
        tolerance: TimeInterval = productionTolerance
    ) {
        guard scheduledPoll == nil else { return }
        lastChangeCount = pasteboard.changeCount
        scheduledPoll = scheduler.schedule(interval: interval, tolerance: tolerance) { [weak self] in
            self?.poll()
        }
    }

    func stop() {
        scheduledPoll?.cancel()
        scheduledPoll = nil
    }

    /// Called by future Qipli writers immediately after their pasteboard write completes.
    func registerSelfWrite(changeCount: Int) {
        ignoredChanges.insert(changeCount)
    }

    func poll() {
        let currentChangeCount = pasteboard.changeCount
        guard let lastChangeCount else {
            self.lastChangeCount = currentChangeCount
            return
        }
        guard currentChangeCount != lastChangeCount else { return }
        self.lastChangeCount = currentChangeCount

        // A newer external change makes every older expected self-write irrelevant.
        ignoredChanges = ignoredChanges.filter { $0 >= currentChangeCount }
        guard ignoredChanges.remove(currentChangeCount) == nil else { return }
        if let typedReader = pasteboard as? TypedPasteboardReading,
           let onExternalChange {
            Task { @MainActor [weak self] in
                let typedChange = await Task.detached(priority: .userInitiated) {
                    typedReader.typedImageChange(changeCount: currentChangeCount)
                }.value
                guard let self else { return }
                if let typedChange {
                    onExternalChange(typedChange)
                    return
                }
                guard let text = self.pasteboard.textValue() else { return }
                self.onExternalText(PasteboardTextChange(
                    changeCount: currentChangeCount,
                    text: text
                ))
            }
            return
        }
        guard let text = pasteboard.textValue() else { return }
        onExternalText(PasteboardTextChange(changeCount: currentChangeCount, text: text))
    }
}
