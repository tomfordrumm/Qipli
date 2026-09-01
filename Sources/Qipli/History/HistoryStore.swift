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

protocol ManagedImageHistoryStoring: AnyObject {
    func createImage(items: [ManagedImageCaptureItem], activityAt: Date) throws -> HistoryEntry
    func pastePayload(id: UUID) throws -> HistoryPastePayload?
    func thumbnailData(id: UUID) throws -> Data?
}

enum HistoryStoreError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "History storage is unavailable."
    }
}

/// A local-only SQLite store. No managed objects cross this boundary.
final class CoreDataHistoryStore: HistoryStoring, HistoryPagingStoring, ManagedImageHistoryStoring {
    private static let entityName = "HistoryEntry"
    private let storeURL: URL
    private let imageStore: ManagedImageStoring
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
            )
        )
    }

    init(storeURL: URL, imageStore: ManagedImageStoring? = nil) throws {
        self.storeURL = storeURL
        self.imageStore = try imageStore ?? ManagedImageAssetStore(
            rootURL: storeURL.deletingLastPathComponent().appendingPathComponent("ManagedImages", isDirectory: true)
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
            if let manifest = Self.manifest(from: object) {
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
            manifest = try imageStore.commit(occurrenceID: occurrenceID, items: items)
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
                managedImageItems: manifest.items
            )
        }
    }

    func pastePayload(id: UUID) throws -> HistoryPastePayload? {
        guard let manifest = try imageManifest(id: id) else { return nil }
        guard manifest.occurrenceID == id else { throw ManagedImageStoreError.invalidManagedPath }
        try imageStore.validate(manifest)
        let items = manifest.items
        return HistoryPastePayload(items: try items.map { item in
            HistoryPasteboardItemPayload(representations: try item.representations.map {
                HistoryPasteboardRepresentationPayload(
                    typeIdentifier: $0.typeIdentifier,
                    data: try imageStore.read($0)
                )
            })
        })
    }

    func thumbnailData(id: UUID) throws -> Data? {
        guard let manifest = try imageManifest(id: id), manifest.occurrenceID == id else { return nil }
        return try imageStore.makeThumbnail(for: manifest)
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
        let manifest = try imageManifest(id: id)
        if let manifest {
            try markImageDeletionPending(id: id)
            try imageStore.remove(manifest: manifest)
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
        try markAllImageDeletionsPending()
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
        try cleanupPendingImageDeletions()
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
        for object in expiredObjects where Self.manifest(from: object) != nil {
            object.setValue(true, forKey: "managedImageDeletionPending")
        }
        if context.hasChanges {
            try context.save()
        }
        for object in expiredObjects {
            if let manifest = Self.manifest(from: object) {
                try imageStore.remove(manifest: manifest)
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
                textEntries: pageEntries.filter(\.isTextOnly),
                entries: pageEntries,
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
        let representations: [HistoryRepresentationDescriptor]
        let imageMetadata: [HistoryImageMetadata]
        let managedImages: [HistoryManagedImageRepresentation]
        let managedImageItems: [ManagedImageAssetItemManifest]
        if let manifest {
            representations = manifest.representations.map {
                HistoryRepresentationDescriptor(kind: .inlineImage, typeIdentifier: $0.typeIdentifier)
            }
            imageMetadata = manifest.representations.map(\.metadata)
            managedImages = manifest.representations
            managedImageItems = manifest.items
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
        return HistoryEntry(
            id: id,
            text: text,
            activityAt: activityAt,
            representations: representations,
            imageMetadata: imageMetadata,
            managedImages: managedImages,
            managedImageItems: managedImageItems
        )
    }

    private func markImageDeletionPending(id: UUID) throws {
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

    private func markAllImageDeletionsPending() throws {
        try contextSync { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.entityName)
            request.predicate = NSPredicate(format: "managedImageManifest != nil")
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
            }
            context.delete(object)
        }
        if context.hasChanges {
            try context.save()
        }
    }

    private static func descriptor(from entry: HistoryEntry) -> HistoryOccurrenceDescriptor {
        return HistoryOccurrenceDescriptor(
            id: entry.id,
            activityAt: entry.activityAt,
            textPreview: entry.isTextOnly ? HistoryPreview.text(for: entry.text) : nil,
            representations: entry.representations,
            imageMetadata: entry.imageMetadata
        )
    }

    private static func isRenderable(_ entry: HistoryEntry) -> Bool {
        entry.isImageEntry || HistoryTextPolicy.shouldCapture(entry.text)
    }

    private static func manifest(from object: NSManagedObject) -> ManagedImageAssetManifest? {
        guard let encoded = object.value(forKey: "managedImageManifest") as? String,
              let data = encoded.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(ManagedImageAssetManifest.self, from: data)
    }

    private func imageManifest(id: UUID) throws -> ManagedImageAssetManifest? {
        try contextSync { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.entityName)
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            guard let object = try context.fetch(request).first else { return nil }
            return Self.manifest(from: object)
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
        entry.versionHashModifier = "performance-indexes-v1-managed-image-delete-v1"

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

        entry.properties = [id, text, capturedAt, itemKind, itemOrder, itemTypeIdentifier, managedImageManifest, managedImageDeletionPending]
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
final class RetryingHistoryStore: HistoryStoring, HistoryPagingStoring, ManagedImageHistoryStoring {
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
        guard let store = try store() as? ManagedImageHistoryStoring else { throw HistoryStoreError.unavailable }
        return try store.createImage(items: items, activityAt: activityAt)
    }

    func pastePayload(id: UUID) throws -> HistoryPastePayload? {
        guard let store = try store() as? ManagedImageHistoryStoring else { return nil }
        return try store.pastePayload(id: id)
    }

    func thumbnailData(id: UUID) throws -> Data? {
        guard let store = try store() as? ManagedImageHistoryStoring else { return nil }
        return try store.thumbnailData(id: id)
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
            textEntries: pageEntries.filter(\.isTextOnly),
            entries: pageEntries,
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
}
