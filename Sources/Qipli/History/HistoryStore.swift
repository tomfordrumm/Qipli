import CoreData
import Foundation

protocol HistoryStoring: AnyObject {
    func fetchCurrent(since cutoff: Date) throws -> [HistoryEntry]
    func create(text: String, activityAt: Date) throws -> HistoryEntry
    func markUsed(id: UUID, activityAt: Date) throws
    func delete(id: UUID) throws
    func clearAll() throws
}

enum HistoryStoreError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "History storage is unavailable."
    }
}

/// A local-only SQLite store. No managed objects cross this boundary.
final class CoreDataHistoryStore: HistoryStoring {
    private static let entityName = "HistoryEntry"
    private let storeURL: URL
    private var container: NSPersistentContainer

    convenience init() throws {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appendingPathComponent("Qipli", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try self.init(storeURL: directory.appendingPathComponent("History.sqlite"))
    }

    init(storeURL: URL) throws {
        self.storeURL = storeURL
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

    func create(text: String, activityAt: Date) throws -> HistoryEntry {
        try contextSync { context in
            let id = UUID()
            let object = NSEntityDescription.insertNewObject(forEntityName: Self.entityName, into: context)
            object.setValue(id, forKey: "id")
            object.setValue(text, forKey: "text")
            // Keep this legacy SQLite/Core Data key so existing user stores load without migration.
            object.setValue(activityAt, forKey: "capturedAt")
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
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.undoManager = nil
    }

    private func contextSync<T>(_ body: (NSManagedObjectContext) throws -> T) throws -> T {
        var result: Result<T, Error>!
        container.viewContext.performAndWait {
            result = Result { try body(container.viewContext) }
        }
        return try result.get()
    }

    private func removeExpired(before cutoff: Date, in context: NSManagedObjectContext) throws {
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

    private static func entry(from object: NSManagedObject) -> HistoryEntry? {
        guard let id = object.value(forKey: "id") as? UUID,
              let text = object.value(forKey: "text") as? String,
              let activityAt = object.value(forKey: "capturedAt") as? Date
        else { return nil }
        return HistoryEntry(id: id, text: text, activityAt: activityAt)
    }

    private static func makeContainer() -> NSPersistentContainer {
        let model = NSManagedObjectModel()
        let entry = NSEntityDescription()
        entry.name = entityName
        entry.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        // Fetch indexes are not part of Core Data's compatibility hash by default.
        // Bump the entity hash so existing stores perform a lightweight migration
        // and receive the S018 index layout instead of keeping their legacy index.
        entry.versionHashModifier = "performance-indexes-v1"

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

        entry.properties = [id, text, capturedAt]
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
final class RetryingHistoryStore: HistoryStoring {
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

    private func store() throws -> HistoryStoring {
        if let loadedStore { return loadedStore }
        let store = try makeStore()
        loadedStore = store
        return store
    }
}
