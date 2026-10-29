import Darwin
import XCTest
@testable import Qipli

final class LocalDiagnosticsTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        suite = "QipliDiagnosticsTests.\(UUID())"
        defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suite)
    }
    private func logger(bytes: Int = 1_048_576, files: Int = 10, pending: Int = 256) -> LocalDiagnostics {
        LocalDiagnostics(defaults: defaults, directory: root, maximumFileBytes: bytes,
            maximumFiles: files, maximumPending: pending)
    }
    private func enable(_ logger: LocalDiagnostics, _ enabled: Bool = true) {
        let done = expectation(description: "toggle complete")
        logger.setEnabled(enabled) { success in XCTAssertTrue(success); done.fulfill() }
        wait(for: [done], timeout: 3)
    }
    private func records() throws -> [[String: Any]] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }
            .flatMap { try Data(contentsOf: $0).split(separator: 0x0A).map { line in
                try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line)) as? [String: Any])
            } }
    }

    func testDefaultOffDoesNotCreateFilesAndPersistsOptInAcrossRelaunch() throws {
        let first = logger()
        first.record(stage: .trigger, reason: .started)
        first.flush()
        XCTAssertFalse(first.isEnabled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        enable(first)
        let second = logger()
        second.flush(); second.flush()
        XCTAssertTrue(second.isEnabled)
        enable(second, false)
        let count = try records().count
        second.record(stage: .trigger, reason: .started)
        second.flush()
        XCTAssertEqual(try records().count, count)
        XCTAssertFalse(logger().isEnabled)
    }

    func testRecordSchemaCorrelationAndPrivatePermissions() throws {
        let writer = logger()
        enable(writer)
        let id = UUID()
        writer.record(operation: id, stage: .replacement, reason: .deadline, elapsedMilliseconds: 42)
        writer.flush()
        let record = try XCTUnwrap(records().first { $0["operation"] as? String == id.uuidString })
        XCTAssertEqual(Set(record.keys), Set(["timestamp", "session", "operation", "version", "build", "stage", "reason", "elapsedMilliseconds", "schemaVersion", "sequence"]))
        XCTAssertEqual(record["stage"] as? String, "replacement")
        XCTAssertEqual(record["reason"] as? String, "deadline")
        XCTAssertEqual(record["elapsedMilliseconds"] as? Int, 42)
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: root.path)
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("diagnostics-0.jsonl").path)
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        XCTAssertEqual((fileAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testDetailedSchemaPreservesEvidenceAndDecodesOldRecords() throws {
        let writer = logger()
        enable(writer)
        let id = UUID()
        writer.record(operation: id, stage: .ax, reason: .axFailure, elapsedMilliseconds: 15,
            details: DiagnosticDetails(step: .read, api: .copyStringForRange, attribute: .stringForRange,
                check: .readLength, axError: -25204, callMicroseconds: 250, remainingMilliseconds: 485,
                rangeLocation: 10, rangeLength: 3, expected: 3, observed: 2))
        writer.record(operation: id, stage: .finished, reason: .failed)
        writer.flush()
        let record = try XCTUnwrap(records().first { $0["reason"] as? String == "axFailure" })
        XCTAssertEqual(record["schemaVersion"] as? Int, 2)
        let details = try XCTUnwrap(record["details"] as? [String: Any])
        XCTAssertEqual(Set(details.keys), Set(["step", "api", "attribute", "check", "axError", "callMicroseconds",
            "remainingMilliseconds", "rangeLocation", "rangeLength", "expected", "observed"]))
        XCTAssertEqual(details["axError"] as? Int, -25204)
        let numbers = try records().compactMap { $0["sequence"] as? Int }
        XCTAssertEqual(Set(numbers).count, numbers.count)
        let old = """
        {"timestamp":"2026-10-15T11:00:00Z","session":"00000000-0000-0000-0000-000000000001","version":"1.0.14","build":"15","stage":"wordProof","reason":"unavailable"}
        """
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DiagnosticRecord.self, from: Data(old.utf8))
        XCTAssertNil(decoded.schemaVersion)
        XCTAssertNil(decoded.details)
    }

    func testOverflowRetainsTerminalConcreteCauseWithoutLaterInput() throws {
        let clock = BlockingDiagnosticClock()
        let writer = LocalDiagnostics(defaults: defaults, directory: root, maximumPending: 1, now: { clock.date() })
        let enabled = expectation(description: "enabled")
        writer.setEnabled(true) { _ in enabled.fulfill() }
        XCTAssertEqual(clock.entered.wait(timeout: .now() + 3), .success)
        let operation = UUID()
        let trace = CorrectionDiagnosticTrace { stage, reason, details in
            writer.record(operation: operation, stage: stage, reason: reason, details: details)
        }
        trace(.trigger, .started)
        trace(.ax, .axFailure, DiagnosticDetails(step: .read, api: .copyStringForRange,
            attribute: .stringForRange, axError: -25204))
        // Generic unwind must not overwrite the specific cause.
        trace(.checkpoint, .unavailable, DiagnosticDetails(step: .read))
        trace(.wordProof, .unavailable)
        trace(.finished, .failed)
        clock.release.signal()
        wait(for: [enabled], timeout: 3)
        writer.flush()
        let rows = try records()
        let final = try XCTUnwrap(rows.first { $0["stage"] as? String == "finished" })
        let details = try XCTUnwrap(final["details"] as? [String: Any])
        let cause = try XCTUnwrap(details["lastFailure"] as? [String: Any])
        XCTAssertEqual(cause["api"] as? String, "copyStringForRange")
        XCTAssertEqual(cause["axError"] as? Int, -25204)
        let loss = try XCTUnwrap(rows.first { $0["reason"] as? String == "dropped" })
        XCTAssertEqual((loss["details"] as? [String: Any])?["droppedRecords"] as? Int, 3)
    }

    func testTriggerNeverMasksWordFailureAndSuccessfulLifecycleHasNoFailure() throws {
        let writer = logger()
        enable(writer)
        for trigger in [DiagnosticReason.leftOptionTrigger, .shortcutTrigger] {
            let id = UUID()
            let trace = CorrectionDiagnosticTrace { stage, reason, details in
                writer.record(operation: id, stage: stage, reason: reason, details: details)
            }
            trace(.trigger, trigger)
            trace(.admission, .passed)
            trace(.wordProof, .wordBlocked)
            trace(.finished, .unavailable)
            writer.flush()
            let final = try XCTUnwrap(records().first { $0["operation"] as? String == id.uuidString && $0["stage"] as? String == "finished" })
            let cause = (final["details"] as? [String: Any])?["lastFailure"] as? [String: Any]
            XCTAssertEqual(cause?["stage"] as? String, "wordProof")
            XCTAssertEqual(cause?["reason"] as? String, "wordBlocked")
        }
        let id = UUID()
        let trace = CorrectionDiagnosticTrace { stage, reason, details in
            writer.record(operation: id, stage: stage, reason: reason, details: details)
        }
        trace(.trigger, .leftOptionTrigger)
        trace(.nativePaste, .passed)
        trace(.clipboardLease, .restoreDeferred)
        trace(.clipboardLease, .restored)
        trace(.finished, .stale)
        writer.flush()
        let final = try XCTUnwrap(records().first { $0["operation"] as? String == id.uuidString && $0["stage"] as? String == "finished" })
        XCTAssertNil((final["details"] as? [String: Any])?["lastFailure"])
    }

    func testRotationBoundsEveryFileAndTotalStorage() throws {
        let writer = logger(bytes: 700, files: 3)
        enable(writer)
        for _ in 0..<30 { writer.record(operation: UUID(), stage: .finished, reason: .completed) }
        writer.flush()
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 3)
        let sizes = try files.map { try Data(contentsOf: $0).count }
        XCTAssertTrue(sizes.allSatisfy { $0 <= 700 })
        XCTAssertLessThanOrEqual(sizes.reduce(0, +), 2100)
        XCTAssertLessThan(try records().count, 31)
    }

    func testOldLogsAreRemovedWhileDisabledWithoutCreatingDirectory() throws {
        let writer = logger()
        enable(writer); enable(writer, false)
        let file = root.appendingPathComponent("diagnostics-0.jsonl")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -8 * 86400)], ofItemAtPath: file.path)
        let relaunched = logger()
        relaunched.flush()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(relaunched.isEnabled)
    }

    func testClearRemovesManagedFilesOnlyAndLoggingCanContinue() throws {
        let writer = logger()
        enable(writer)
        let unmanaged = root.appendingPathComponent("unmanaged.txt")
        try Data("synthetic fixture".utf8).write(to: unmanaged)
        for _ in 0..<256 { writer.record(stage: .trigger, reason: .started) }
        let cleared = expectation(description: "clear")
        writer.clear { success in XCTAssertTrue(success); cleared.fulfill() }
        wait(for: [cleared], timeout: 3)
        writer.flush()
        XCTAssertTrue(try records().isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: unmanaged.path))
        writer.record(stage: .finished, reason: .completed)
        writer.flush()
        XCTAssertEqual(try records().count, 1)
    }

    func testSymlinkFileIsRejectedWithoutTouchingTarget() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let target = root.appendingPathComponent("target.txt")
        let original = Data("synthetic sentinel".utf8)
        try original.write(to: target)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("diagnostics-0.jsonl"), withDestinationURL: target)
        let writer = logger()
        let done = expectation(description: "rejected")
        writer.setEnabled(true) { success in XCTAssertFalse(success); done.fulfill() }
        wait(for: [done], timeout: 3)
        writer.record(stage: .trigger, reason: .started)
        writer.flush()
        XCTAssertTrue(writer.hasFailure)
        XCTAssertEqual(try Data(contentsOf: target), original)
    }

    func testSymlinkDirectoryIsRejected() throws {
        let target = root.appendingPathExtension("target")
        defer { try? FileManager.default.removeItem(at: target) }
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root, withDestinationURL: target)
        let writer = logger()
        let done = expectation(description: "rejected")
        writer.setEnabled(true) { success in XCTAssertFalse(success); done.fulfill() }
        wait(for: [done], timeout: 3)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty)
    }

    func testAdmissionDropsOverflowWithoutBlockingCaller() throws {
        XCTAssertTrue(Thread.isMainThread)
        let clock = BlockingDiagnosticClock()
        let writer = LocalDiagnostics(defaults: defaults, directory: root, maximumPending: 1,
            now: { clock.date() })
        let enabled = expectation(description: "enabled")
        writer.setEnabled(true) { success in XCTAssertTrue(success); enabled.fulfill() }
        XCTAssertEqual(clock.entered.wait(timeout: .now() + 3), .success)
        for _ in 0..<100 { writer.record(stage: .trigger, reason: .started) }
        clock.release.signal()
        wait(for: [enabled], timeout: 3)
        writer.flush()
        XCTAssertEqual(try records().filter { $0["stage"] as? String == "trigger" }.count, 1)
        let overflow = try XCTUnwrap(records().first { $0["reason"] as? String == "dropped" })
        XCTAssertEqual((overflow["details"] as? [String: Any])?["droppedRecords"] as? Int, 99)
    }

    func testDisableInvalidatesQueuedRecordsBeforeTheyReachDisk() throws {
        let clock = BlockingDiagnosticClock()
        let writer = LocalDiagnostics(defaults: defaults, directory: root, now: { clock.date() })
        let enabled = expectation(description: "enabled")
        writer.setEnabled(true) { _ in enabled.fulfill() }
        XCTAssertEqual(clock.entered.wait(timeout: .now() + 3), .success)
        writer.record(stage: .trigger, reason: .started)
        let disabled = expectation(description: "disabled")
        writer.setEnabled(false) { success in XCTAssertTrue(success); disabled.fulfill() }
        clock.release.signal()
        wait(for: [enabled, disabled], timeout: 3)
        writer.flush()
        XCTAssertFalse(writer.isEnabled)
        XCTAssertFalse(try records().contains { $0["stage"] as? String == "trigger" })
    }

    func testOversizedRecordFailsWithoutAffectingCaller() throws {
        let writer = logger(bytes: 1)
        let done = expectation(description: "too small")
        writer.setEnabled(true) { success in XCTAssertFalse(success); done.fulfill() }
        wait(for: [done], timeout: 3)
        writer.record(stage: .trigger, reason: .started)
        writer.flush()
        XCTAssertTrue(writer.hasFailure)
        XCTAssertTrue(try records().isEmpty)
    }
}

private final class BlockingDiagnosticClock: @unchecked Sendable {
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var blocked = false
    func date() -> Date {
        let shouldBlock = lock.withLock { () -> Bool in
            guard !Thread.isMainThread, !blocked else { return false }
            blocked = true
            return true
        }
        if shouldBlock { entered.signal(); _ = release.wait(timeout: .now() + 5) }
        return Date()
    }
}
