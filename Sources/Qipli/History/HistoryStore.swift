import CoreData
import Foundation

protocol HistoryStoring: AnyObject {
    func fetchCurrent(since cutoff: Date) throws -> [HistoryEntry]
    func create(text: String, activityAt: Date) throws -> HistoryEntry
    func markUsed(id: UUID, activityAt: Date) throws
    func delete(id: UUID) throws
    func clearAll() throws
}

protocol HistoryPagingStoring: AnyObject {
    func fetchPage(since cutoff: Date, after cursor: HistoryPageCursor?, limit: Int) throws -> HistoryPage
    func searchPage(
        query: String,
        since cutoff: Date,
        after cursor: HistoryPageCursor?,
        limit: Int
    ) throws -> HistoryPage
    func fetchEntry(id: UUID) throws -> HistoryEntry?
    func fetchOccurrence(id: UUID) throws -> HistoryOccurrence?
}

protocol TypedHistoryStoring: AnyObject {
    func createImage(items: [ManagedImageCaptureItem], activityAt: Date) throws -> HistoryEntry
    func createReference(items: [HistoryReferenceCaptureItem], activityAt: Date) throws -> HistoryEntry
    func createImageAndReference(
        imageItems: [ManagedImageCaptureItem],
        referenceItems: [HistoryReferenceCaptureItem],
        activityAt: Date
    ) throws -> HistoryEntry
    func pastePayload(id: UUID) throws -> HistoryPastePayload?
    func thumbnailData(id: UUID) throws -> Data?
}


enum HistoryStoreError: LocalizedError, Equatable {
    case unavailable
    case referenceUnavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "History storage is unavailable."
        case .referenceUnavailable:
            return "The original file is no longer available. The History entry was kept."
        }
    }
}

/// A local-only SQLite store. No managed objects cross this boundary.
final class CoreDataHistoryStore: HistoryStoring, HistoryPagingStoring, TypedHistoryStoring, RichTextHistoryStoring {
    private enum ImageManifestRecord {
        case absent
        case valid(ManagedImageAssetManifest)
        case corrupt
    }

    private enum RichTextManifestRecord {
        case absent
        case valid(HistoryRichTextManifest)
        case corrupt
    }

    private static let entityName = "HistoryEntry"
    private let storeURL: URL
    private let imageStore: ManagedImageStoring
    private let richTextStore: HistoryRichTextAssetStoring
    private var container: NSPersistentContainer
    private var context: NSManagedObjectContext!

    convenience init() throws {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appendingPathComponent("Qipli", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try self.init(
            storeURL: directory.appendingPathComponent("History.sqlite"),
            imageStore: ManagedImageAssetStore(
                rootURL: directory.appendingPathComponent("ManagedImages", isDirectory: true)
            ),
            richTextStore: try HistoryRichTextAssetStore(
                rootURL: directory.appendingPathComponent("RichText", isDirectory: true)
            )
        )
    }

    init(
        storeURL: URL,
        imageStore: ManagedImageStoring? = nil,
        richTextStore: HistoryRichTextAssetStoring? = nil
    ) throws {
        self.storeURL = storeURL
        self.imageStore = try imageStore ?? ManagedImageAssetStore(
            rootURL: storeURL.deletingLastPathComponent().appendingPathComponent("ManagedImages", isDirectory: true)
        )
        self.richTextStore = try richTextStore ?? HistoryRichTextAssetStore(
            rootURL: storeURL.deletingLastPathComponent().appendingPathComponent("RichText", isDirectory: true)
        )
        container = Self.makeContainer()
        try loadStore()
    }

    func fetchCurrent(since cutoff: Date) throws -> [HistoryEntry] {
        try contextSync { context in
            try self.removeExpired(before: cutoff, in: context)
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.entityName)
            request.predicate = NSPredicate(format: "capturedAt > %@", cutoff as NSDate)
            request.sortDescriptors = [
                NSSortDescriptor(key: "capturedAt", ascending: false),
                NSSortDescriptor(key: "id", ascending: false),
            ]
            return try context.fetch(request).compactMap(Self.entry(from:))
        }
    }

    func fetchPage(since cutoff: Date, after cursor: HistoryPageCursor?, limit: Int) throws -> HistoryPage {
        try pageRequest(cutoff: cutoff, cursor: cursor, limit: limit) {
            Self.isRenderable($0)
        }
    }

    func searchPage(
        query: String,
        since cutoff: Date,
        after cursor: HistoryPageCursor?,
        limit: Int
    ) throws -> HistoryPage {
        guard !query.isEmpty else {
            return try fetchPage(since: cutoff, after: cursor, limit: limit)
        }
        return try pageRequest(cutoff: cutoff, cursor: cursor, limit: limit) {
            Self.isRenderable($0) &&
                $0.searchableMetadata.localizedCaseInsensitiveContains(query)
        }
    }

    func fetchEntry(id: UUID) throws -> HistoryEntry? {
        try contextSync { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.entityName)
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            return try context.fetch(request).compactMap(Self.entry(from:)).first
        }
    }

    func fetchOccurrence(id: UUID) throws -> HistoryOccurrence? {
        try contextSync { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.entityName)
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            guard let object = try context.fetch(request).first,
                  let entry = Self.entry(from: object)
            else { return nil }
            if let richManifest = Self.richTextManifest(from: object) {
                return HistoryOccurrence(
                    id: entry.id,
                    items: richManifest.items.sorted { $0.order < $1.order }.map { item in
                        HistoryPayloadItem(
                            id: item.id,
                            order: item.order,
                            representations: [
                                HistoryRepresentationDescriptor(
                                    kind: .text,
                                    typeIdentifier: "public.utf8-plain-text"
                                )
                            ] + item.representations.map {
                                HistoryRepresentationDescriptor(kind: .text, typeIdentifier: $0.typeIdentifier)
                            }
                        )
                    },
                    activityAt: entry.activityAt
                )
            }
            let imageManifest = Self.manifest(from: object)
            let referenceManifest = Self.referenceManifest(from: object)
            if let imageManifest, let referenceManifest {
                let imageItemsByOrder = Dictionary(grouping: imageManifest.items, by: \.order)
                let referenceItemsByOrder = Dictionary(grouping: referenceManifest.items, by: \.order)
                let orders = Set(imageItemsByOrder.keys).union(referenceItemsByOrder.keys).sorted()
                return HistoryOccurrence(
                    id: entry.id,
                    items: orders.flatMap { order in
                        imageItemsByOrder[order, default: []].map { item in
                            HistoryPayloadItem(
                                id: item.id,
                                order: item.order,
                                representations: item.representations.map {
                                    HistoryRepresentationDescriptor(kind: .inlineImage, typeIdentifier: $0.typeIdentifier)
                                }
                            )
                        } + referenceItemsByOrder[order, default: []].map { item in
                            HistoryPayloadItem(
                                id: item.id,
                                order: item.order,
                                representations: [HistoryRepresentationDescriptor(
                                    kind: item.kind,
                                    typeIdentifier: item.typeIdentifier
                                )]
                            )
                        }
                    },
                    activityAt: entry.activityAt,
                    managedImages: imageManifest.representations,
                    referenceMetadata: referenceManifest.items.map(\.metadata)
                )
            }
            if let manifest = imageManifest {
                return HistoryOccurrence(
                    id: entry.id,
                    items: manifest.items.map { item in
                        HistoryPayloadItem(
                            id: item.id,
                            order: item.order,
                            representations: item.representations.map {
                                HistoryRepresentationDescriptor(kind: .inlineImage, typeIdentifier: $0.typeIdentifier)
                            }
                        )
                    },
                    activityAt: entry.activityAt,
                    managedImages: manifest.representations
                )
            }
            if let manifest = referenceManifest {
                return HistoryOccurrence(
                    id: entry.id,
                    items: manifest.items.map { item in
                        HistoryPayloadItem(
                            id: item.id,
                            order: item.order,
                            representations: [HistoryRepresentationDescriptor(
                                kind: item.kind,
                                typeIdentifier: item.typeIdentifier
                            )]
                        )
                    },
                    activityAt: entry.activityAt,
                    referenceMetadata: manifest.items.map(\.metadata)
                )
            }
            let kind = HistoryRepresentationKind(
                rawValue: object.value(forKey: "itemKind") as? String ?? HistoryRepresentationKind.text.rawValue
            ) ?? .text
            let typeIdentifier = object.value(forKey: "itemTypeIdentifier") as? String ?? "public.utf8-plain-text"
            return HistoryOccurrence(
                id: entry.id,
                items: [HistoryPayloadItem(
                    id: entry.id,
                    order: object.value(forKey: "itemOrder") as? Int ?? 0,
                    representations: [HistoryRepresentationDescriptor(
                        kind: kind,
                        typeIdentifier: typeIdentifier
                    )]
                )],
                activityAt: entry.activityAt,
                managedImages: entry.managedImages
            )
        }
    }

    func createImage(items: [ManagedImageCaptureItem], activityAt: Date) throws -> HistoryEntry {
        let occurrenceID = UUID()
        let manifest: ManagedImageAssetManifest
        do {
            manifest = try imageStore.commit(
                occurrenceID: occurrenceID,
                items: items,
                capturedAt: activityAt
            )
        } catch {
            throw error
        }
        do {
            return try createImage(manifest: manifest, activityAt: activityAt)
        } catch {
            try? imageStore.remove(manifest: manifest)
            throw error
        }
    }

    private func createImage(manifest: ManagedImageAssetManifest, activityAt: Date) throws -> HistoryEntry {
        let encodedManifest: String
        do {
            encodedManifest = String(data: try JSONEncoder().encode(manifest), encoding: .utf8) ?? ""
        } catch {
            throw ManagedImageStoreError.writeFailed
        }
        guard !encodedManifest.isEmpty else { throw ManagedImageStoreError.writeFailed }
        return try contextSync { context in
            let object = NSEntityDescription.insertNewObject(forEntityName: Self.entityName, into: context)
            object.setValue(manifest.occurrenceID, forKey: "id")
            object.setValue("", forKey: "text")
            object.setValue(activityAt, forKey: "capturedAt")
            object.setValue(HistoryRepresentationKind.inlineImage.rawValue, forKey: "itemKind")
            object.setValue(manifest.items.first?.order ?? 0, forKey: "itemOrder")
            object.setValue(manifest.representations.first?.typeIdentifier, forKey: "itemTypeIdentifier")
            object.setValue(encodedManifest, forKey: "managedImageManifest")
            do {
                try context.save()
            } catch {
                throw ManagedImageStoreError.writeFailed
            }
            return Self.entry(from: object) ?? HistoryEntry(
                id: manifest.occurrenceID,
                text: "",
                activityAt: activityAt,
                representations: [HistoryRepresentationDescriptor(kind: .inlineImage, typeIdentifier: manifest.representations.first?.typeIdentifier ?? "public.image")],
                imageMetadata: manifest.representations.map(\.metadata),
                managedImages: manifest.representations,
                managedImageItems: manifest.items,
                managedImageName: manifest.displayName
            )
        }
    }

    func createReference(items: [HistoryReferenceCaptureItem], activityAt: Date) throws -> HistoryEntry {
        guard !items.isEmpty else { throw HistoryStoreError.unavailable }
        let occurrenceID = UUID()
        let manifest = HistoryReferenceManifest(
            occurrenceID: occurrenceID,
            items: try items.sorted { $0.order < $1.order }.map { item in
                let bookmarkData: Data?
                if item.kind == .url {
                    bookmarkData = nil
                } else {
                    guard let url = item.url else { throw HistoryStoreError.referenceUnavailable }
                    bookmarkData = try url.bookmarkData(options: [])
                }
                return HistoryReferenceItemManifest(
                    id: UUID(),
                    order: item.order,
                    kind: item.kind,
                    typeIdentifier: item.typeIdentifier,
                    bookmarkData: bookmarkData,
                    urlString: item.urlString,
                    metadata: item.metadata
                )
            },
            capturedAt: activityAt
        )
        let encoded = try JSONEncoder().encode(manifest)
        guard let encodedManifest = String(data: encoded, encoding: .utf8) else {
            throw HistoryStoreError.unavailable
        }
        return try contextSync { context in
            let object = NSEntityDescription.insertNewObject(forEntityName: Self.entityName, into: context)
            object.setValue(occurrenceID, forKey: "id")
            object.setValue("", forKey: "text")
            object.setValue(activityAt, forKey: "capturedAt")
            object.setValue(items.count == 1 ? items[0].kind.rawValue : HistoryRepresentationKind.fileReference.rawValue, forKey: "itemKind")
            object.setValue(items.map(\.order).min() ?? 0, forKey: "itemOrder")
            object.setValue(items.first?.typeIdentifier, forKey: "itemTypeIdentifier")
            object.setValue(encodedManifest, forKey: "referenceManifest")
            do {
                try context.save()
            } catch {
                throw HistoryStoreError.unavailable
            }
            return Self.entry(from: object) ?? HistoryEntry(
                id: occurrenceID,
                text: "",
                activityAt: activityAt,
                representations: manifest.items.map {
                    HistoryRepresentationDescriptor(kind: $0.kind, typeIdentifier: $0.typeIdentifier)
                },
                referenceMetadata: manifest.items.map(\.metadata)
            )
        }
    }

    func createImageAndReference(
        imageItems: [ManagedImageCaptureItem],
        referenceItems: [HistoryReferenceCaptureItem],
        activityAt: Date
    ) throws -> HistoryEntry {
        guard !imageItems.isEmpty, !referenceItems.isEmpty else {
            throw HistoryStoreError.unavailable
        }
        let occurrenceID = UUID()
        let imageManifest: ManagedImageAssetManifest
        do {
            imageManifest = try imageStore.commit(
                occurrenceID: occurrenceID,
                items: imageItems,
                capturedAt: activityAt
            )
        } catch {
            throw error
        }
        do {
            let referenceManifest = try makeReferenceManifest(
                occurrenceID: occurrenceID,
                items: referenceItems,
                capturedAt: activityAt
            )
            return try createTyped(
                imageManifest: imageManifest,
                referenceManifest: referenceManifest,
                activityAt: activityAt
            )
        } catch {
            try? imageStore.remove(manifest: imageManifest)
            throw error
        }
    }

    private func createTyped(
        imageManifest: ManagedImageAssetManifest,
        referenceManifest: HistoryReferenceManifest,
        activityAt: Date
    ) throws -> HistoryEntry {
        let imageEncoded = try JSONEncoder().encode(imageManifest)
        let referenceEncoded = try JSONEncoder().encode(referenceManifest)
        guard let imageString = String(data: imageEncoded, encoding: .utf8),
              let referenceString = String(data: referenceEncoded, encoding: .utf8)
        else { throw HistoryStoreError.unavailable }
        return try contextSync { context in
            let object = NSEntityDescription.insertNewObject(forEntityName: Self.entityName, into: context)
            object.setValue(imageManifest.occurrenceID, forKey: "id")
            object.setValue("", forKey: "text")
            object.setValue(activityAt, forKey: "capturedAt")
            object.setValue(HistoryRepresentationKind.inlineImage.rawValue, forKey: "itemKind")
            object.setValue(min(imageManifest.items.first?.order ?? .max, referenceManifest.items.first?.order ?? .max), forKey: "itemOrder")
            object.setValue(imageManifest.representations.first?.typeIdentifier, forKey: "itemTypeIdentifier")
            object.setValue(imageString, forKey: "managedImageManifest")
            object.setValue(referenceString, forKey: "referenceManifest")
            try context.save()
            return Self.entry(from: object) ?? HistoryEntry(
                id: imageManifest.occurrenceID,
                text: "",
                activityAt: activityAt,
                representations: [],
                imageMetadata: imageManifest.representations.map(\.metadata),
                managedImages: imageManifest.representations,
                managedImageItems: imageManifest.items,
                managedImageName: imageManifest.displayName,
                referenceMetadata: referenceManifest.items.map(\.metadata)
            )
        }
    }

    private func makeReferenceManifest(
        occurrenceID: UUID,
        items: [HistoryReferenceCaptureItem],
        capturedAt: Date
    ) throws -> HistoryReferenceManifest {
        HistoryReferenceManifest(
            occurrenceID: occurrenceID,
            items: try items.sorted { $0.order < $1.order }.map { item in
                let bookmarkData: Data?
                if item.kind == .url {
                    bookmarkData = nil
                } else {
                    guard let url = item.url else { throw HistoryStoreError.referenceUnavailable }
                    bookmarkData = try url.bookmarkData(options: [])
                }
                return HistoryReferenceItemManifest(
                    id: UUID(),
                    order: item.order,
                    kind: item.kind,
                    typeIdentifier: item.typeIdentifier,
                    bookmarkData: bookmarkData,
                    urlString: item.urlString,
                    metadata: item.metadata
                )
            },
            capturedAt: capturedAt
        )
    }

    func pastePayload(id: UUID) throws -> HistoryPastePayload? {
        let richRecord = try richTextManifestRecord(id: id)
        if case .corrupt = richRecord {
            throw HistoryRichTextStoreError.corruptAsset
        }
        if case let .valid(richManifest) = richRecord {
            try richTextStore.validate(richManifest)
            let sortedItems = richManifest.items.sorted { $0.order < $1.order }
            let payloadItems = try sortedItems.enumerated().map { index, item in
                var representations: [HistoryPasteboardRepresentationPayload] = []
                let fallbackText: String? = if let canonicalText = item.canonicalText {
                    canonicalText
                } else if index == 0 {
                    try fetchEntry(id: id)?.text
                } else {
                    nil
                }
                if let fallbackText {
                    representations.append(HistoryPasteboardRepresentationPayload(
                        typeIdentifier: "public.utf8-plain-text",
                        data: Data(fallbackText.utf8)
                    ))
                }
                representations.append(contentsOf: try item.representations.map { representation in
                    HistoryPasteboardRepresentationPayload(
                        typeIdentifier: representation.typeIdentifier,
                        data: try richTextStore.read(representation)
                    )
                })
                return HistoryPasteboardItemPayload(representations: representations)
            }
            return HistoryPastePayload(items: payloadItems)
        }
        let imageRecord = try imageManifestRecord(id: id)
        if case .corrupt = imageRecord {
            throw ManagedImageStoreError.corruptAsset
        }
        let imageManifest: ManagedImageAssetManifest? = switch imageRecord {
        case .absent, .corrupt: nil
        case let .valid(manifest): manifest
        }
        let referenceManifest = try referenceManifest(id: id)
        guard imageManifest?.occurrenceID == id || referenceManifest?.occurrenceID == id else { return nil }

        let imagePayloadItems: [(order: Int, payload: [HistoryPasteboardRepresentationPayload])]
        if let imageManifest {
            try imageStore.validate(imageManifest)
            imagePayloadItems = try imageManifest.items.sorted { $0.order < $1.order }.map { item in
                (item.order, try item.representations.map {
                    HistoryPasteboardRepresentationPayload(
                        typeIdentifier: $0.typeIdentifier,
                        data: try imageStore.read($0)
                    )
                })
            }
        } else {
            imagePayloadItems = []
        }

        let referencePayloadItems: [(order: Int, payload: [HistoryPasteboardRepresentationPayload])]
        if let referenceManifest {
            referencePayloadItems = try resolvedReferencePayloadItems(for: referenceManifest)
        } else {
            referencePayloadItems = []
        }
        let payloadByOrder = Dictionary(grouping: imagePayloadItems + referencePayloadItems, by: \.order)
        let payloadItems = payloadByOrder.keys.sorted().map { order in
            HistoryPasteboardItemPayload(representations: payloadByOrder[order, default: []].flatMap(\.payload))
        }
        return HistoryPastePayload(items: payloadItems)
    }

    private func resolvedReferencePayloadItems(
        for manifest: HistoryReferenceManifest
    ) throws -> [(order: Int, payload: [HistoryPasteboardRepresentationPayload])] {
        var updatedItems: [HistoryReferenceItemManifest] = []
        var payloadItems: [(order: Int, payload: [HistoryPasteboardRepresentationPayload])] = []
        var referenceUnavailable = false
        for item in manifest.items.sorted(by: { $0.order < $1.order }) {
            if item.kind == .url {
                guard let urlString = item.urlString,
                      let url = URL(string: urlString),
                      Self.isSupportedWebURL(url)
                else {
                    referenceUnavailable = true
                    updatedItems.append(Self.unavailableReferenceItem(item))
                    continue
                }
                payloadItems.append((item.order, [
                    HistoryPasteboardRepresentationPayload(
                        typeIdentifier: item.typeIdentifier,
                        data: Data(urlString.utf8)
                    )
                ]))
                updatedItems.append(item)
                continue
            }
            guard let bookmarkData = item.bookmarkData else {
                referenceUnavailable = true
                updatedItems.append(Self.unavailableReferenceItem(item))
                continue
            }
            var stale = false
            guard let resolvedURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ),
            FileManager.default.isReadableFile(atPath: resolvedURL.path)
            else {
                referenceUnavailable = true
                updatedItems.append(Self.unavailableReferenceItem(item))
                continue
            }
            let refreshedBookmark = stale
                ? ((try? resolvedURL.bookmarkData(options: [])) ?? item.bookmarkData)
                : item.bookmarkData
            let refreshedMetadata = Self.referenceMetadata(
                existing: item.metadata,
                resolvedURL: resolvedURL
            )
            updatedItems.append(HistoryReferenceItemManifest(
                id: item.id,
                order: item.order,
                kind: item.kind,
                typeIdentifier: item.typeIdentifier,
                bookmarkData: refreshedBookmark,
                urlString: item.urlString,
                metadata: refreshedMetadata
            ))
            payloadItems.append((item.order, [
                HistoryPasteboardRepresentationPayload(
                    typeIdentifier: "public.file-url",
                    data: Data(resolvedURL.absoluteString.utf8)
                )
            ]))
        }
        if updatedItems != manifest.items {
            try saveReferenceManifest(HistoryReferenceManifest(
                occurrenceID: manifest.occurrenceID,
                items: updatedItems,
                capturedAt: manifest.capturedAt
            ))
        }
        if referenceUnavailable { throw HistoryStoreError.referenceUnavailable }
        return payloadItems
    }

    func thumbnailData(id: UUID) throws -> Data? {
        let imageRecord = try imageManifestRecord(id: id)
        guard case let .valid(manifest) = imageRecord, manifest.occurrenceID == id else {
            if case .corrupt = imageRecord { throw ManagedImageStoreError.corruptAsset }
            return nil
        }
        return try imageStore.makeThumbnail(for: manifest)
    }

    func createRichText(
        text: String,
        items: [HistoryRichTextCaptureItem],
        activityAt: Date
    ) throws -> HistoryRichTextCaptureResult {
        let occurrenceID = UUID()
        do {
            let manifest = try richTextStore.commit(
                occurrenceID: occurrenceID,
                items: items,
                capturedAt: activityAt
            )
            do {
                let entry = try create(text: text, richTextManifest: manifest, activityAt: activityAt)
                return HistoryRichTextCaptureResult(entry: entry, richTextSaved: true, notice: nil)
            } catch {
                try? richTextStore.remove(manifest: manifest)
                throw error
            }
        } catch {
            let entry = try create(text: text, activityAt: activityAt)
            return HistoryRichTextCaptureResult(
                entry: entry,
                richTextSaved: false,
                notice: "Formatting was not saved; plain text was kept."
            )
        }
    }

    func create(text: String, activityAt: Date) throws -> HistoryEntry {
        try contextSync { context in
            let id = UUID()
            let object = NSEntityDescription.insertNewObject(forEntityName: Self.entityName, into: context)
            object.setValue(id, forKey: "id")
            object.setValue(text, forKey: "text")
            // Keep this legacy SQLite/Core Data key so existing user stores load without migration.
            object.setValue(activityAt, forKey: "capturedAt")
            object.setValue(HistoryRepresentationKind.text.rawValue, forKey: "itemKind")
            object.setValue(0, forKey: "itemOrder")
            object.setValue("public.utf8-plain-text", forKey: "itemTypeIdentifier")
            try context.save()
            return HistoryEntry(id: id, text: text, activityAt: activityAt)
        }
    }

    private func create(
        text: String,
        richTextManifest: HistoryRichTextManifest,
        activityAt: Date
    ) throws -> HistoryEntry {
        let encoded = try JSONEncoder().encode(richTextManifest)
        guard let encodedManifest = String(data: encoded, encoding: .utf8) else {
            throw HistoryStoreError.unavailable
        }
        return try contextSync { context in
            let id = richTextManifest.occurrenceID
            let object = NSEntityDescription.insertNewObject(forEntityName: Self.entityName, into: context)
            object.setValue(id, forKey: "id")
            object.setValue(text, forKey: "text")
            object.setValue(activityAt, forKey: "capturedAt")
            object.setValue(HistoryRepresentationKind.text.rawValue, forKey: "itemKind")
            object.setValue(0, forKey: "itemOrder")
            object.setValue("public.utf8-plain-text", forKey: "itemTypeIdentifier")
            object.setValue(encodedManifest, forKey: "richTextManifest")
            do {
                try context.save()
            } catch {
                context.rollback()
                throw HistoryStoreError.unavailable
            }
            return Self.entry(from: object) ?? HistoryEntry(
                id: id,
                text: text,
                activityAt: activityAt,
                representations: [HistoryRepresentationDescriptor(kind: .text, typeIdentifier: "public.utf8-plain-text")],
                hasRichText: true
            )
        }
    }

    func markUsed(id: UUID, activityAt: Date) throws {
        try contextSync { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.entityName)
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            for object in try context.fetch(request) {
                // See create(_:activityAt:): the persisted key intentionally remains `capturedAt`.
                object.setValue(activityAt, forKey: "capturedAt")
            }
            if context.hasChanges {
                try context.save()
            }
        }
    }

    func delete(id: UUID) throws {
        let imageRecord = try imageManifestRecord(id: id)
        let richRecord = try richTextManifestRecord(id: id)
        let hasManagedAssets: Bool = {
            switch (imageRecord, richRecord) {
            case (.absent, .absent): return false
            default: return true
            }
        }()
        if hasManagedAssets {
            try markAssetDeletionPending(id: id)
            switch imageRecord {
            case let .valid(manifest): try imageStore.remove(manifest: manifest)
            case .corrupt: try imageStore.removeOwnedAssets(for: id)
            case .absent: break
            }
            switch richRecord {
            case let .valid(manifest): try richTextStore.remove(manifest: manifest)
            case .corrupt: try richTextStore.removeOwnedAssets(for: id)
            case .absent: break
            }
            try removePendingImageEntry(id: id)
            return
        }
        try contextSync { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.entityName)
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            for object in try context.fetch(request) {
                context.delete(object)
            }
            if context.hasChanges {
                try context.save()
            }
        }
    }

    /// Destroys Qipli-managed SQLite data and recreates an empty store. It never touches NSPasteboard.
    func clearAll() throws {
        try markAllAssetDeletionsPending()
        try imageStore.removeAllOwnedAssets()
        try contextSync { context in
            context.reset()
            if context.hasChanges {
                try context.save()
            }
        }
        let coordinator = container.persistentStoreCoordinator
        if let persistentStore = coordinator.persistentStores.first {
            try coordinator.remove(persistentStore)
        }
        try coordinator.destroyPersistentStore(at: storeURL, ofType: NSSQLiteStoreType, options: nil)
        let fileManager = FileManager.default
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: storeURL.path + suffix)
            if fileManager.fileExists(atPath: sidecar.path) {
                try fileManager.removeItem(at: sidecar)
            }
        }
        container = Self.makeContainer()
        try loadStore()
    }

    /// Releases the SQLite connection. Used by temporary-store tests; normal app shutdown relies on process teardown.
    func close() {
        try? contextSync { $0.reset() }
        let coordinator = container.persistentStoreCoordinator
        for persistentStore in coordinator.persistentStores {
            try? coordinator.remove(persistentStore)
        }
    }

    private func loadStore() throws {
        try imageStore.cleanupTemporaryAssets()
        try richTextStore.cleanupTemporaryAssets()
        var loadError: Error?
        let description = NSPersistentStoreDescription(url: storeURL)
        description.type = NSSQLiteStoreType
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError { throw loadError }
        context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.undoManager = nil
        try backfillManagedImageNames()
        try cleanupPendingImageDeletions()
        try cleanupOrphanImageAssets()
        try cleanupOrphanRichTextAssets()
    }

    private func backfillManagedImageNames() throws {
        try contextSync { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.entityName)
            request.predicate = NSPredicate(
                format: "managedImageManifest != nil AND managedImageDeletionPending != YES"
            )
            for object in try context.fetch(request) {
                guard let manifest = Self.manifest(from: object),
                      manifest.displayName == nil,
                      let capturedAt = object.value(forKey: "capturedAt") as? Date
                else { continue }
                let upgradedManifest = ManagedImageAssetManifest(
                    occurrenceID: manifest.occurrenceID,
                    items: manifest.items,
                    capturedAt: capturedAt,
                    displayName: ManagedImageNaming.name(capturedAt: capturedAt)
                )
                guard let data = try? JSONEncoder().encode(upgradedManifest),
                      let encoded = String(data: data, encoding: .utf8)
                else { continue }
                object.setValue(encoded, forKey: "managedImageManifest")
            }
            if context.hasChanges {
                try context.save()
            }
        }
    }

    private func contextSync<T>(_ body: (NSManagedObjectContext) throws -> T) throws -> T {
        var result: Result<T, Error>!
        context.performAndWait {
            result = Result { try body(context) }
        }
        return try result.get()
    }

    private func removeExpired(before cutoff: Date, in context: NSManagedObjectContext) throws {
        try cleanupPendingImageDeletions(in: context)
        let manifestRequest = NSFetchRequest<NSManagedObject>(entityName: Self.entityName)
        manifestRequest.predicate = NSPredicate(format: "capturedAt <= %@", cutoff as NSDate)
        let expiredObjects = try context.fetch(manifestRequest)
        for object in expiredObjects where Self.manifest(from: object) != nil || Self.richTextManifest(from: object) != nil {
            object.setValue(true, forKey: "managedImageDeletionPending")
        }
        if context.hasChanges {
            try context.save()
        }
        for object in expiredObjects {
            if let manifest = Self.manifest(from: object) {
                try imageStore.remove(manifest: manifest)
            }
            if let manifest = Self.richTextManifest(from: object) {
                try richTextStore.remove(manifest: manifest)
            } else if object.value(forKey: "richTextManifest") as? String != nil {
                if let id = object.value(forKey: "id") as? UUID {
                    try richTextStore.removeOwnedAssets(for: id)
                }
            }
        }
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: Self.entityName)
        request.predicate = NSPredicate(format: "capturedAt <= %@", cutoff as NSDate)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        deleteRequest.resultType = .resultTypeObjectIDs
        guard let result = try context.execute(deleteRequest) as? NSBatchDeleteResult,
              let deletedObjectIDs = result.result as? [NSManagedObjectID],
              !deletedObjectIDs.isEmpty
        else { return }

        NSManagedObjectContext.mergeChanges(
            fromRemoteContextSave: [NSDeletedObjectsKey: deletedObjectIDs],
            into: [context]
        )
        if context.hasChanges {
            context.processPendingChanges()
        }
    }

    private func pageRequest(
        cutoff: Date,
        cursor: HistoryPageCursor?,
        limit: Int,
        accepts: (HistoryEntry) -> Bool
    ) throws -> HistoryPage {
        precondition((1...HistoryService.pageSize).contains(limit))
        return try contextSync { context in
            try self.removeExpired(before: cutoff, in: context)
            var scanCursor = cursor
            var matchedEntries: [HistoryEntry] = []
            var exhausted = false

            while matchedEntries.count <= limit, !exhausted {
                let request = NSFetchRequest<NSManagedObject>(entityName: Self.entityName)
                request.fetchLimit = limit + 1
                request.predicate = Self.cursorPredicate(cutoff: cutoff, cursor: scanCursor)
                request.sortDescriptors = [
                    NSSortDescriptor(key: "capturedAt", ascending: false),
                    NSSortDescriptor(key: "id", ascending: false),
                ]
                let objects = try context.fetch(request)
                guard !objects.isEmpty else { break }
                for object in objects {
                    if let entry = Self.entry(from: object), accepts(entry) {
                        matchedEntries.append(entry)
                        if matchedEntries.count > limit { break }
                    }
                }
                if let last = objects.last, let lastEntry = Self.entry(from: last) {
                    scanCursor = HistoryPageCursor(activityAt: lastEntry.activityAt, id: lastEntry.id)
                }
                exhausted = objects.count <= limit
            }

            let pageEntries = Array(matchedEntries.prefix(limit))
            let descriptors = pageEntries.map(Self.descriptor(from:))
            let nextCursor = descriptors.last.map {
                HistoryPageCursor(activityAt: $0.activityAt, id: $0.id)
            }
            return HistoryPage(
                descriptors: descriptors,
                nextCursor: nextCursor,
                hasMore: matchedEntries.count > limit
            )
        }
    }

    private static func cursorPredicate(cutoff: Date, cursor: HistoryPageCursor?) -> NSPredicate {
        let retention = NSPredicate(format: "capturedAt > %@", cutoff as NSDate)
        guard let cursor else { return retention }
        let afterCursor = NSPredicate(
            format: "capturedAt < %@ OR (capturedAt == %@ AND id < %@)",
            cursor.activityAt as NSDate,
            cursor.activityAt as NSDate,
            cursor.id as CVarArg
        )
        return NSCompoundPredicate(andPredicateWithSubpredicates: [retention, afterCursor])
    }

    private static func entry(from object: NSManagedObject) -> HistoryEntry? {
        if object.value(forKey: "managedImageDeletionPending") as? Bool == true {
            return nil
        }
        guard let id = object.value(forKey: "id") as? UUID,
              let text = object.value(forKey: "text") as? String,
              let activityAt = object.value(forKey: "capturedAt") as? Date
        else { return nil }
        let manifest = Self.manifest(from: object)
        let referenceManifest = Self.referenceManifest(from: object)
        let richTextManifest = Self.richTextManifest(from: object)
        let representations: [HistoryRepresentationDescriptor]
        let imageMetadata: [HistoryImageMetadata]
        let managedImages: [HistoryManagedImageRepresentation]
        let managedImageItems: [ManagedImageAssetItemManifest]
        if let richTextManifest {
            representations = [HistoryRepresentationDescriptor(
                kind: .text,
                typeIdentifier: "public.utf8-plain-text"
            )] + richTextManifest.representations.map {
                HistoryRepresentationDescriptor(kind: .text, typeIdentifier: $0.typeIdentifier)
            }
            imageMetadata = []
            managedImages = []
            managedImageItems = []
        } else if manifest != nil || referenceManifest != nil {
            let imageItemsByOrder = Dictionary(
                grouping: manifest?.items ?? [],
                by: \.order
            )
            let referenceItemsByOrder = Dictionary(
                grouping: referenceManifest?.items ?? [],
                by: \.order
            )
            let orders = Set(imageItemsByOrder.keys).union(referenceItemsByOrder.keys).sorted()
            representations = orders.flatMap { order in
                imageItemsByOrder[order, default: []].flatMap { item in
                    item.representations.map {
                        HistoryRepresentationDescriptor(kind: .inlineImage, typeIdentifier: $0.typeIdentifier)
                    }
                } + referenceItemsByOrder[order, default: []].map {
                    HistoryRepresentationDescriptor(kind: $0.kind, typeIdentifier: $0.typeIdentifier)
                }
            }
            imageMetadata = manifest?.representations.map(\.metadata) ?? []
            managedImages = manifest?.representations ?? []
            managedImageItems = manifest?.items ?? []
        } else {
            let kind = HistoryRepresentationKind(
                rawValue: object.value(forKey: "itemKind") as? String ?? HistoryRepresentationKind.text.rawValue
            ) ?? .text
            representations = [HistoryRepresentationDescriptor(
                kind: kind,
                typeIdentifier: object.value(forKey: "itemTypeIdentifier") as? String ?? "public.utf8-plain-text"
            )]
            imageMetadata = []
            managedImages = []
            managedImageItems = []
        }
        let managedImageName = manifest?.displayName
        return HistoryEntry(
            id: id,
            text: text,
            activityAt: activityAt,
            representations: representations,
            imageMetadata: imageMetadata,
            managedImages: managedImages,
            managedImageItems: managedImageItems,
            managedImageName: managedImageName,
            referenceMetadata: referenceManifest?.items.map(\.metadata) ?? [],
            hasRichText: object.value(forKey: "richTextManifest") as? String != nil
        )
    }

    private func markAssetDeletionPending(id: UUID) throws {
        try contextSync { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.entityName)
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            guard let object = try context.fetch(request).first else { return }
            object.setValue(true, forKey: "managedImageDeletionPending")
            if context.hasChanges {
                try context.save()
            }
        }
    }

    private func markAllAssetDeletionsPending() throws {
        try contextSync { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.entityName)
            request.predicate = NSPredicate(format: "managedImageManifest != nil OR richTextManifest != nil")
            for object in try context.fetch(request) {
                object.setValue(true, forKey: "managedImageDeletionPending")
            }
            if context.hasChanges {
                try context.save()
            }
        }
    }

    private func removePendingImageEntry(id: UUID) throws {
        try contextSync { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.entityName)
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            guard let object = try context.fetch(request).first else { return }
            context.delete(object)
            try context.save()
        }
    }

    private func cleanupPendingImageDeletions() throws {
        try contextSync { context in
            try cleanupPendingImageDeletions(in: context)
        }
    }

    private func cleanupPendingImageDeletions(in context: NSManagedObjectContext) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: Self.entityName)
        request.predicate = NSPredicate(format: "managedImageDeletionPending == YES")
        for object in try context.fetch(request) {
            if let manifest = Self.manifest(from: object) {
                try imageStore.remove(manifest: manifest)
            } else if let id = object.value(forKey: "id") as? UUID {
                try imageStore.removeOwnedAssets(for: id)
            }
            if let manifest = Self.richTextManifest(from: object) {
                try richTextStore.remove(manifest: manifest)
            } else if let id = object.value(forKey: "id") as? UUID {
                try richTextStore.removeOwnedAssets(for: id)
            }
            context.delete(object)
        }
        if context.hasChanges {
            try context.save()
        }
    }

    private func cleanupOrphanImageAssets() throws {
        try contextSync { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.entityName)
            request.predicate = NSPredicate(format: "managedImageManifest != nil")
            let knownOccurrenceIDs = Set(
                try context.fetch(request).compactMap { $0.value(forKey: "id") as? UUID }
            )
            try imageStore.cleanupOrphanAssets(knownOccurrenceIDs: knownOccurrenceIDs)
        }
    }

    private func cleanupOrphanRichTextAssets() throws {
        try contextSync { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.entityName)
            request.predicate = NSPredicate(format: "richTextManifest != nil")
            let knownOccurrenceIDs = Set(
                try context.fetch(request).compactMap { $0.value(forKey: "id") as? UUID }
            )
            try richTextStore.cleanupOrphanAssets(knownOccurrenceIDs: knownOccurrenceIDs)
        }
    }

    private static func descriptor(from entry: HistoryEntry) -> HistoryOccurrenceDescriptor {
        return HistoryOccurrenceDescriptor(
            id: entry.id,
            activityAt: entry.activityAt,
            textPreview: entry.isTextOnly ? HistoryPreview.text(for: entry.text) : nil,
            representations: entry.representations,
            imageMetadata: entry.imageMetadata,
            referenceMetadata: entry.referenceMetadata
        )
    }

    private static func isRenderable(_ entry: HistoryEntry) -> Bool {
        entry.isTypedEntry || HistoryTextPolicy.shouldCapture(entry.text)
    }

    private static func isSupportedWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private static func unavailableReferenceItem(_ item: HistoryReferenceItemManifest) -> HistoryReferenceItemManifest {
        HistoryReferenceItemManifest(
            id: item.id,
            order: item.order,
            kind: item.kind,
            typeIdentifier: item.typeIdentifier,
            bookmarkData: item.bookmarkData,
            urlString: item.urlString,
            metadata: HistoryReferenceMetadata(
                displayName: item.metadata.displayName,
                fileExtension: item.metadata.fileExtension,
                typeIdentifier: item.metadata.typeIdentifier,
                byteCount: item.metadata.byteCount,
                domain: item.metadata.domain,
                searchText: item.metadata.searchText,
                availability: .unavailable
            )
        )
    }

    private static func referenceMetadata(
        existing: HistoryReferenceMetadata,
        resolvedURL: URL
    ) -> HistoryReferenceMetadata {
        let values = try? resolvedURL.resourceValues(forKeys: [.nameKey, .fileSizeKey, .contentTypeKey])
        let name = resolvedURL.lastPathComponent.isEmpty
            ? (values?.name ?? existing.displayName)
            : resolvedURL.lastPathComponent
        let fileExtension = resolvedURL.pathExtension.lowercased()
        let typeIdentifier = values?.contentType?.identifier ?? existing.typeIdentifier
        let byteCount = values?.fileSize.map(Int64.init) ?? existing.byteCount
        return HistoryReferenceMetadata(
            displayName: name,
            fileExtension: fileExtension,
            typeIdentifier: typeIdentifier,
            byteCount: byteCount,
            searchText: [name, fileExtension, typeIdentifier].joined(separator: " "),
            availability: .available
        )
    }

    private static func manifest(from object: NSManagedObject) -> ManagedImageAssetManifest? {
        guard let encoded = object.value(forKey: "managedImageManifest") as? String,
              let data = encoded.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(ManagedImageAssetManifest.self, from: data)
    }

    private static func referenceManifest(from object: NSManagedObject) -> HistoryReferenceManifest? {
        guard let encoded = object.value(forKey: "referenceManifest") as? String,
              let data = encoded.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(HistoryReferenceManifest.self, from: data)
    }

    private static func richTextManifest(from object: NSManagedObject) -> HistoryRichTextManifest? {
        guard let encoded = object.value(forKey: "richTextManifest") as? String,
              let data = encoded.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(HistoryRichTextManifest.self, from: data)
    }

    private func imageManifestRecord(id: UUID) throws -> ImageManifestRecord {
        try contextSync { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.entityName)
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            guard let object = try context.fetch(request).first,
                  let encoded = object.value(forKey: "managedImageManifest") as? String
            else { return .absent }
            guard let data = encoded.data(using: .utf8),
                  let manifest = try? JSONDecoder().decode(ManagedImageAssetManifest.self, from: data)
            else { return .corrupt }
            return .valid(manifest)
        }
    }

    private func referenceManifest(id: UUID) throws -> HistoryReferenceManifest? {
        try contextSync { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.entityName)
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            guard let object = try context.fetch(request).first else { return nil }
            return Self.referenceManifest(from: object)
        }
    }

    private func richTextManifestRecord(id: UUID) throws -> RichTextManifestRecord {
        try contextSync { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.entityName)
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            guard let object = try context.fetch(request).first,
                  let encoded = object.value(forKey: "richTextManifest") as? String
            else { return .absent }
            guard let data = encoded.data(using: .utf8),
                  let manifest = try? JSONDecoder().decode(HistoryRichTextManifest.self, from: data)
            else { return .corrupt }
            return .valid(manifest)
        }
    }

    private func saveReferenceManifest(_ manifest: HistoryReferenceManifest) throws {
        let data = try JSONEncoder().encode(manifest)
        guard let encoded = String(data: data, encoding: .utf8) else {
            throw HistoryStoreError.unavailable
        }
        try contextSync { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.entityName)
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "id == %@", manifest.occurrenceID as CVarArg)
            guard let object = try context.fetch(request).first else { return }
            object.setValue(encoded, forKey: "referenceManifest")
            if context.hasChanges { try context.save() }
        }
    }

    private static func makeContainer() -> NSPersistentContainer {
        let model = NSManagedObjectModel()
        let entry = NSEntityDescription()
        entry.name = entityName
        entry.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        // Fetch indexes are not part of Core Data's compatibility hash by default.
        // Bump the entity hash so existing stores perform a lightweight migration
        // and receive the S018 index layout instead of keeping their legacy index.
        entry.versionHashModifier = "performance-indexes-v1-managed-image-delete-v1-reference-v1-rich-text-v1"

        let id = NSAttributeDescription()
        id.name = "id"
        id.attributeType = .UUIDAttributeType
        id.isOptional = false

        let text = NSAttributeDescription()
        text.name = "text"
        text.attributeType = .stringAttributeType
        text.isOptional = false

        let capturedAt = NSAttributeDescription()
        capturedAt.name = "capturedAt"
        capturedAt.attributeType = .dateAttributeType
        capturedAt.isOptional = false

        let itemKind = NSAttributeDescription()
        itemKind.name = "itemKind"
        itemKind.attributeType = .stringAttributeType
        itemKind.isOptional = true

        let itemOrder = NSAttributeDescription()
        itemOrder.name = "itemOrder"
        itemOrder.attributeType = .integer32AttributeType
        itemOrder.isOptional = true

        let itemTypeIdentifier = NSAttributeDescription()
        itemTypeIdentifier.name = "itemTypeIdentifier"
        itemTypeIdentifier.attributeType = .stringAttributeType
        itemTypeIdentifier.isOptional = true

        let managedImageManifest = NSAttributeDescription()
        managedImageManifest.name = "managedImageManifest"
        managedImageManifest.attributeType = .stringAttributeType
        managedImageManifest.isOptional = true

        let managedImageDeletionPending = NSAttributeDescription()
        managedImageDeletionPending.name = "managedImageDeletionPending"
        managedImageDeletionPending.attributeType = .booleanAttributeType
        managedImageDeletionPending.isOptional = true

        let referenceManifest = NSAttributeDescription()
        referenceManifest.name = "referenceManifest"
        referenceManifest.attributeType = .stringAttributeType
        referenceManifest.isOptional = true

        let richTextManifest = NSAttributeDescription()
        richTextManifest.name = "richTextManifest"
        richTextManifest.attributeType = .stringAttributeType
        richTextManifest.isOptional = true

        entry.properties = [id, text, capturedAt, itemKind, itemOrder, itemTypeIdentifier, managedImageManifest, managedImageDeletionPending, referenceManifest, richTextManifest]
        let idIndex = NSFetchIndexDescription(
            name: "idIndex",
            elements: [NSFetchIndexElementDescription(property: id, collationType: .binary)]
        )
        let activityOrderIndex = NSFetchIndexDescription(
            name: "activityOrderIndex",
            elements: [
                NSFetchIndexElementDescription(property: capturedAt, collationType: .binary),
                NSFetchIndexElementDescription(property: id, collationType: .binary),
            ]
        )
        entry.indexes = [idIndex, activityOrderIndex]
        model.entities = [entry]
        return NSPersistentContainer(name: "QipliHistory", managedObjectModel: model)
    }
}

/// Delays opening the default store until it is needed, so a transient launch-time failure can be retried.
final class RetryingHistoryStore: HistoryStoring, HistoryPagingStoring, TypedHistoryStoring, RichTextHistoryStoring {
    private let makeStore: () throws -> HistoryStoring
    private var loadedStore: HistoryStoring?

    init(makeStore: @escaping () throws -> HistoryStoring) {
        self.makeStore = makeStore
    }

    func fetchCurrent(since cutoff: Date) throws -> [HistoryEntry] {
        try store().fetchCurrent(since: cutoff)
    }

    func create(text: String, activityAt: Date) throws -> HistoryEntry {
        try store().create(text: text, activityAt: activityAt)
    }

    func markUsed(id: UUID, activityAt: Date) throws {
        try store().markUsed(id: id, activityAt: activityAt)
    }

    func delete(id: UUID) throws {
        try store().delete(id: id)
    }

    func clearAll() throws {
        try store().clearAll()
    }

    func fetchPage(since cutoff: Date, after cursor: HistoryPageCursor?, limit: Int) throws -> HistoryPage {
        guard let pagedStore = try store() as? HistoryPagingStoring else {
            return try fallbackPage(since: cutoff, after: cursor, limit: limit, query: nil)
        }
        return try pagedStore.fetchPage(since: cutoff, after: cursor, limit: limit)
    }

    func searchPage(
        query: String,
        since cutoff: Date,
        after cursor: HistoryPageCursor?,
        limit: Int
    ) throws -> HistoryPage {
        guard let pagedStore = try store() as? HistoryPagingStoring else {
            return try fallbackPage(since: cutoff, after: cursor, limit: limit, query: query)
        }
        return try pagedStore.searchPage(query: query, since: cutoff, after: cursor, limit: limit)
    }

    func fetchEntry(id: UUID) throws -> HistoryEntry? {
        guard let pagedStore = try store() as? HistoryPagingStoring else {
            return try store().fetchCurrent(since: .distantPast).first { $0.id == id }
        }
        return try pagedStore.fetchEntry(id: id)
    }

    func fetchOccurrence(id: UUID) throws -> HistoryOccurrence? {
        guard let pagedStore = try store() as? HistoryPagingStoring else { return nil }
        return try pagedStore.fetchOccurrence(id: id)
    }

    func createImage(items: [ManagedImageCaptureItem], activityAt: Date) throws -> HistoryEntry {
        try typedStore().createImage(items: items, activityAt: activityAt)
    }

    func createReference(items: [HistoryReferenceCaptureItem], activityAt: Date) throws -> HistoryEntry {
        try typedStore().createReference(items: items, activityAt: activityAt)
    }

    func createImageAndReference(
        imageItems: [ManagedImageCaptureItem],
        referenceItems: [HistoryReferenceCaptureItem],
        activityAt: Date
    ) throws -> HistoryEntry {
        try typedStore().createImageAndReference(
            imageItems: imageItems,
            referenceItems: referenceItems,
            activityAt: activityAt
        )
    }

    func createRichText(
        text: String,
        items: [HistoryRichTextCaptureItem],
        activityAt: Date
    ) throws -> HistoryRichTextCaptureResult {
        guard let store = try store() as? RichTextHistoryStoring else {
            throw HistoryStoreError.unavailable
        }
        return try store.createRichText(text: text, items: items, activityAt: activityAt)
    }

    func pastePayload(id: UUID) throws -> HistoryPastePayload? {
        try typedStore().pastePayload(id: id)
    }

    func thumbnailData(id: UUID) throws -> Data? {
        try typedStore().thumbnailData(id: id)
    }

    private func fallbackPage(
        since cutoff: Date,
        after cursor: HistoryPageCursor?,
        limit: Int,
        query: String?
    ) throws -> HistoryPage {
        var entries = try store().fetchCurrent(since: cutoff)
        if let query, !query.isEmpty {
            entries = HistorySearchMatcher.matches(in: entries, query: query)
        }
        if let cursor {
            entries = entries.filter {
                $0.activityAt < cursor.activityAt ||
                    ($0.activityAt == cursor.activityAt && $0.id.uuidString < cursor.id.uuidString)
            }
        }
        let hasMore = entries.count > limit
        let pageEntries = Array(entries.prefix(limit))
        let descriptors = pageEntries.map {
            HistoryOccurrenceDescriptor(
                id: $0.id,
                activityAt: $0.activityAt,
                textPreview: HistoryPreview.text(for: $0.text),
                representations: [
                    HistoryRepresentationDescriptor(
                        kind: .text,
                        typeIdentifier: "public.utf8-plain-text"
                    )
                ]
            )
        }
        let nextCursor = pageEntries.last.map { HistoryPageCursor(activityAt: $0.activityAt, id: $0.id) }
        return HistoryPage(
            descriptors: descriptors,
            nextCursor: nextCursor,
            hasMore: hasMore
        )
    }

    private func store() throws -> HistoryStoring {
        if let loadedStore { return loadedStore }
        let store = try makeStore()
        loadedStore = store
        return store
    }

    private func typedStore() throws -> TypedHistoryStoring {
        guard let typedStore = try store() as? TypedHistoryStoring else {
            throw HistoryStoreError.unavailable
        }
        return typedStore
    }
}
