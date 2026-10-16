import Darwin
import Foundation

/// No payload-bearing strings can cross this boundary.
enum DiagnosticStage: String, Codable, Sendable {
    case session, trigger, admission, capture, cycle, selection, wordProof, mapping, ax, validation, checkpoint, inputListener
    case replacement, clipboardLease, nativeCopy, nativePaste, keyReplay, unicodePaste, postcondition, layoutSwitch, finished
}

enum DiagnosticReason: String, Codable, Sendable {
    case enabled, started, leftOptionTrigger, shortcutTrigger, passed, completed, inputBusy, operationBusy, unsupportedSources
    case contextChanged, switchContextChanged, switchFailed, postSwitchContextChanged
    case wordBlocked, wordMissing, trailingSpaces, targetChanged, wordExpired, sourceChanged
    case caretBoundary, spaceBoundary, leftBoundary, rightBoundary, wordBoundary
    case permissionDenied, secureInput, unavailable, unsupported, stale, limit, deadline, verification
    case unsupportedCharacter, ambiguousSource, ambiguousDestination, unchanged, unexpected
    case mismatch, axFailure, typeMismatch, lengthMismatch, notSettable, missingCapability, denied, failed, cancelled, dropped, restored, restoreSkipped, restoreDeferred
    case tapTimeout, tapDisabled, listenerReady, listenerStopped, listenerUnavailable

    init(ax error: CorrectionAXError) {
        switch error {
        case .unavailable: self = .unavailable
        case .unsupported: self = .unsupported
        case .stale: self = .stale
        case .limit: self = .limit
        case .deadline: self = .deadline
        case .verification: self = .verification
        }
    }

    init(mapping error: CorrectionMappingError) {
        switch error {
        case .unsupportedCharacter: self = .unsupportedCharacter
        case .ambiguousSource: self = .ambiguousSource
        case .ambiguousDestination: self = .ambiguousDestination
        case .unchanged: self = .unchanged
        }
    }
}

struct DiagnosticRecord: Codable, Sendable {
    let schemaVersion: Int?
    let sequence: UInt64?
    let details: DiagnosticDetails?
    let timestamp: Date
    let session: UUID
    let operation: UUID?
    let version: String
    let build: String
    let stage: DiagnosticStage
    let reason: DiagnosticReason
    let elapsedMilliseconds: UInt64?
}

/// Bounded admission on caller threads; all filesystem work stays on one utility queue.
final class LocalDiagnostics: @unchecked Sendable {
    static let preferenceKey = "localDiagnosticsEnabled"
    private let queue = DispatchQueue(label: "com.qipli.diagnostics", qos: .utility)
    private let lock = NSLock()
    private let defaults: UserDefaults
    let directory: URL
    private let fileManager = FileManager.default
    private let session = UUID()
    private let version: String
    private let build: String
    private let now: @Sendable () -> Date
    private let maximumFileBytes: Int
    private let maximumFiles: Int
    private let retention: TimeInterval
    private let maximumPending: Int
    private var timer: DispatchSourceTimer?
    private var enabled: Bool
    private var generation: UInt64 = 0
    private var pending = 0
    private var failed = false
    private var sequence: UInt64 = 0
    private var dropped: UInt64 = 0
    private var overflowReportEpoch: UInt64?

    init(defaults: UserDefaults = .standard, directory: URL? = nil,
         maximumFileBytes: Int = 1_048_576, maximumFiles: Int = 10,
         retention: TimeInterval = 7 * 24 * 60 * 60, maximumPending: Int = 256,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.defaults = defaults
        self.directory = directory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
            .appendingPathComponent(Bundle.main.bundleIdentifier == "com.qipli.app.dev" ? "Qipli Dev" : "Qipli", isDirectory: true)
        self.maximumFileBytes = max(1, maximumFileBytes)
        self.maximumFiles = max(1, maximumFiles)
        self.retention = retention
        self.maximumPending = max(1, maximumPending)
        self.now = now
        func numeric(_ key: String) -> String {
            let value = Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "0"
            return !value.isEmpty && value.count <= 32 && value.utf8.allSatisfy { (48...57).contains($0) || $0 == 46 } ? value : "0"
        }
        version = numeric("CFBundleShortVersionString")
        build = numeric("CFBundleVersion")
        enabled = defaults.object(forKey: Self.preferenceKey) as? Bool ?? false
        queue.async { [weak self] in
            guard let self else { return }
            self.attempt {
                try self.prepareDirectory(create: self.isEnabled)
                try self.removeExpired()
                if self.isEnabled {
                    try self.append(self.makeRecord(operation: nil, stage: .session, reason: .enabled, elapsed: nil, details: Self.environmentDetails))
                }
            }
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 3600, repeating: 3600, leeway: .seconds(60))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.attempt { try self.prepareDirectory(create: false); try self.removeExpired() }
        }
        self.timer = timer
        timer.resume()
    }

    deinit { timer?.cancel() }

    var isEnabled: Bool { lock.withLock { enabled } }
    var hasFailure: Bool { lock.withLock { failed } }

    /// Completion runs after all earlier writes; no disabled records survive the epoch change.
    func setEnabled(_ value: Bool, completion: @escaping @Sendable (Bool) -> Void) {
        let epoch = lock.withLock { () -> UInt64 in
            enabled = value
            generation &+= 1
            dropped = 0
            return generation
        }
        defaults.set(value, forKey: Self.preferenceKey)
        queue.async { [self] in
            let success = attempt {
                try prepareDirectory(create: value)
                try removeExpired()
                if lock.withLock({ generation == epoch }), value {
                    try append(makeRecord(operation: nil, stage: .session, reason: .enabled, elapsed: nil, details: Self.environmentDetails))
                }
            }
            completion(success)
        }
    }

    func record(operation: UUID? = nil, stage: DiagnosticStage, reason: DiagnosticReason,
                elapsedMilliseconds: UInt64? = nil, details: DiagnosticDetails? = nil) {
        // Reserve room for operation endings. Overflow itself is reported by one
        // bounded queue task, even when no later input event arrives.
        let admission: (UInt64, UInt64)? = lock.withLock {
            guard enabled else { return nil }
            sequence &+= 1
            guard pending < maximumPending + (stage == .finished ? 8 : 0) else {
                dropped &+= 1
                if overflowReportEpoch != generation {
                    overflowReportEpoch = generation
                    let epoch = generation
                    queue.async { [self] in reportOverflow(epoch: epoch) }
                }
                return nil
            }
            pending += 1
            return (generation, sequence)
        }
        guard let (epoch, number) = admission else { return }
        let record = makeRecord(operation: operation, stage: stage, reason: reason,
            elapsed: elapsedMilliseconds, details: details, sequence: number)
        queue.async { [self] in
            defer { lock.withLock { pending -= 1 } }
            guard lock.withLock({ enabled && generation == epoch }) else { return }
            attempt { try prepareDirectory(create: true); try append(record) }
        }
    }

    private func reportOverflow(epoch: UInt64) {
        let count = lock.withLock { () -> UInt64 in
            guard overflowReportEpoch == epoch else { return 0 }
            overflowReportEpoch = nil
            guard enabled && generation == epoch else { return 0 }
            let count = dropped
            dropped = 0
            return count
        }
        guard count > 0 else { return }
        attempt {
            try prepareDirectory(create: true)
            try append(makeRecord(operation: nil, stage: .session, reason: .dropped, elapsed: nil,
                details: DiagnosticDetails(droppedRecords: count)))
        }
    }

    /// Clear only this writer's managed names. Caller may open the returned directory in Finder.
    func prepareForViewing(completion: @escaping @Sendable (Bool) -> Void) {
        queue.async { [self] in
            completion(attempt { try prepareDirectory(create: true); try removeExpired() })
        }
    }

    func clear(completion: @escaping @Sendable (Bool) -> Void) {
        lock.withLock { generation &+= 1; dropped = 0 }
        queue.async { [self] in
            completion(attempt {
                try prepareDirectory(create: false)
                for index in 0..<maximumFiles { try remove(index) }
            })
        }
    }

    /// Test/verification barrier; never called by the input pipeline.
    func flush() { queue.sync {} }

    private func makeRecord(operation: UUID?, stage: DiagnosticStage, reason: DiagnosticReason,
                            elapsed: UInt64?, details: DiagnosticDetails? = nil, sequence number: UInt64? = nil) -> DiagnosticRecord {
        let number = number ?? lock.withLock { sequence &+= 1; return sequence }
        return DiagnosticRecord(schemaVersion: 2, sequence: number, details: details, timestamp: now(), session: session, operation: operation,
            version: version, build: build, stage: stage, reason: reason, elapsedMilliseconds: elapsed)
    }

    private static var environmentDetails: DiagnosticDetails {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return DiagnosticDetails(osMajor: os.majorVersion, osMinor: os.minorVersion, osPatch: os.patchVersion)
    }

    @discardableResult private func attempt(_ action: () throws -> Void) -> Bool {
        do { try action(); lock.withLock { failed = false }; return true }
        catch { lock.withLock { failed = true }; return false }
    }

    private enum StorageError: Error { case unsafeEntry, io, oversized }

    private func file(_ index: Int) -> URL { directory.appendingPathComponent("diagnostics-\(index).jsonl") }

    private func info(_ url: URL) throws -> stat? {
        var result = stat()
        if lstat(url.path, &result) == 0 { return result }
        if errno == ENOENT { return nil }
        throw StorageError.io
    }

    private func prepareDirectory(create: Bool) throws {
        if try info(directory) == nil {
            guard create else { return }
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
        }
        guard let metadata = try info(directory), metadata.st_mode & S_IFMT == S_IFDIR,
              metadata.st_uid == getuid() else { throw StorageError.unsafeEntry }
        guard chmod(directory.path, 0o700) == 0 else { throw StorageError.io }
    }

    private func regularInfo(_ index: Int) throws -> stat? {
        guard let metadata = try info(file(index)) else { return nil }
        guard metadata.st_mode & S_IFMT == S_IFREG, metadata.st_nlink == 1,
              metadata.st_uid == getuid() else { throw StorageError.unsafeEntry }
        return metadata
    }

    private func remove(_ index: Int) throws {
        if try regularInfo(index) != nil { try fileManager.removeItem(at: file(index)) }
    }

    private func removeExpired() throws {
        for index in 0..<maximumFiles {
            if let metadata = try regularInfo(index),
               (now().timeIntervalSince1970 - Double(metadata.st_mtimespec.tv_sec) >= retention || metadata.st_size > maximumFileBytes) {
                try remove(index)
            }
        }
    }

    private func append(_ record: DiagnosticRecord) throws {
        try removeExpired()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(record)
        data.append(0x0A)
        guard data.count <= maximumFileBytes else { throw StorageError.oversized }
        // Validate the complete managed inventory before mutating it.
        for index in 0..<maximumFiles { _ = try regularInfo(index) }
        let size = try regularInfo(0)?.st_size ?? 0
        if size + Int64(data.count) > maximumFileBytes {
            try remove(maximumFiles - 1)
            if maximumFiles > 1 {
                for index in stride(from: maximumFiles - 2, through: 0, by: -1) {
                    if try regularInfo(index) != nil {
                        try fileManager.moveItem(at: file(index), to: file(index + 1))
                    }
                }
            }
        }
        let descriptor = open(file(0).path, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW | O_NONBLOCK, 0o600)
        guard descriptor >= 0 else { throw StorageError.io }
        defer { close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_nlink == 1, metadata.st_uid == getuid(), fchmod(descriptor, 0o600) == 0 else {
            throw StorageError.unsafeEntry
        }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw StorageError.io }
                offset += count
            }
        }
    }
}
