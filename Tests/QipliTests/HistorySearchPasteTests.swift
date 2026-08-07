import XCTest
@testable import Qipli

@MainActor
final class HistoryViewModelSearchTests: XCTestCase {
    func testLocalizedCaseInsensitiveSearchSelectsFirstResultAndKeepsStoredText() throws {
        let first = makeEntry("first", offset: 1)
        let matching = makeEntry("Äpfel", offset: 2)
        let other = makeEntry("other", offset: 3)
        let store = InMemoryHistoryStore(entries: [other, matching, first])
        let viewModel = HistoryViewModel(service: HistoryService(store: store))

        viewModel.reload(selectFirstResult: true)
        viewModel.updateQuery("äP")

        XCTAssertEqual(viewModel.visibleEntries, [matching])
        XCTAssertEqual(viewModel.selectedEntryID, matching.id)
        XCTAssertEqual(store.entries.first { $0.id == matching.id }?.text, "Äpfel")
    }

    func testSelectionMovesWithinVisibleResultsAndResetsAfterQueryChange() {
        let first = makeEntry("alpha", offset: 1)
        let second = makeEntry("alphabet", offset: 2)
        let third = makeEntry("beta", offset: 3)
        let viewModel = HistoryViewModel(service: HistoryService(store: InMemoryHistoryStore(entries: [first, second, third])))

        viewModel.reload(selectFirstResult: true)
        viewModel.moveSelection(by: 1)
        XCTAssertEqual(viewModel.selectedEntryID, second.id)

        viewModel.updateQuery("alpha")
        XCTAssertEqual(viewModel.selectedEntryID, first.id)
        viewModel.moveSelection(by: 100)
        XCTAssertEqual(viewModel.selectedEntryID, second.id)
        viewModel.moveSelection(by: -100)
        XCTAssertEqual(viewModel.selectedEntryID, first.id)
    }

    func testDeletingSelectedFilteredEntrySelectsNearestVisibleEntry() {
        let first = makeEntry("needle one", offset: 1)
        let second = makeEntry("needle two", offset: 2)
        let third = makeEntry("needle three", offset: 3)
        let store = InMemoryHistoryStore(entries: [first, second, third])
        let viewModel = HistoryViewModel(service: HistoryService(store: store))

        viewModel.reload(selectFirstResult: true)
        viewModel.updateQuery("needle")
        viewModel.select(id: second.id)
        viewModel.delete(second)

        XCTAssertEqual(viewModel.visibleEntries.map(\.id), [first.id, third.id])
        XCTAssertEqual(viewModel.selectedEntryID, third.id)
        XCTAssertFalse(store.entries.contains { $0.id == second.id })
    }

    private func makeEntry(_ text: String, offset: TimeInterval) -> HistoryEntry {
        HistoryEntry(id: UUID(), text: text, capturedAt: Date.now.addingTimeInterval(offset))
    }
}

@MainActor
final class HistoryPasteExecutorTests: XCTestCase {
    func testSuccessfulPasteRegistersExactFinalChangeAndDispatchesAfterTargetActivation() {
        let trace = Trace()
        let writer = FakeHistoryPasteboardWriter(changeCount: 41, trace: trace)
        let target = FakeHistoryPasteTarget(trace: trace)
        let dispatcher = FakePasteCommandDispatcher(trace: trace, result: true)
        var registeredChanges: [Int] = []
        let executor = makeExecutor(writer: writer, dispatcher: dispatcher, register: { registeredChanges.append($0) })
        let entry = HistoryEntry(id: UUID(), text: "line α\nline β", capturedAt: .now)
        var result: Result<Void, HistoryPasteFailure>?

        executor.paste(entry: entry, target: target, closePanel: { trace.events.append("close") }) {
            result = $0
        }

        XCTAssertEqual(writer.writtenTexts, [entry.text])
        XCTAssertEqual(registeredChanges, [41])
        XCTAssertEqual(trace.events, ["write", "close", "activate", "dispatch"])
        XCTAssertNoThrow(try result?.get())
    }

    func testMissingPermissionDoesNotWriteClipboardOrClaimSuccess() {
        let trace = Trace()
        let writer = FakeHistoryPasteboardWriter(changeCount: 6, trace: trace)
        let dispatcher = FakePasteCommandDispatcher(trace: trace, result: true)
        let executor = makeExecutor(permission: .denied, writer: writer, dispatcher: dispatcher, register: { _ in })
        var result: Result<Void, HistoryPasteFailure>?

        executor.paste(entry: sampleEntry, target: FakeHistoryPasteTarget(trace: trace), closePanel: { trace.events.append("close") }) {
            result = $0
        }

        XCTAssertEqual(result?.failureValue, .accessibilityRequired)
        XCTAssertTrue(trace.events.isEmpty)
    }

    func testUnavailableTargetDoesNotWriteClipboardOrClosePanel() {
        let trace = Trace()
        let writer = FakeHistoryPasteboardWriter(changeCount: 7, trace: trace)
        let dispatcher = FakePasteCommandDispatcher(trace: trace, result: true)
        let executor = makeExecutor(writer: writer, dispatcher: dispatcher, register: { _ in })
        let target = FakeHistoryPasteTarget(trace: trace, terminated: true)
        var result: Result<Void, HistoryPasteFailure>?

        executor.paste(entry: sampleEntry, target: target, closePanel: { trace.events.append("close") }) {
            result = $0
        }

        XCTAssertEqual(result?.failureValue, .targetUnavailable)
        XCTAssertTrue(trace.events.isEmpty)
    }

    func testActivationFailureKeepsHistoryAvailableAndDoesNotDispatch() {
        let trace = Trace()
        let writer = FakeHistoryPasteboardWriter(changeCount: 8, trace: trace)
        let dispatcher = FakePasteCommandDispatcher(trace: trace, result: true)
        let executor = makeExecutor(writer: writer, dispatcher: dispatcher, register: { _ in })
        let target = FakeHistoryPasteTarget(trace: trace, activateResult: false)
        var result: Result<Void, HistoryPasteFailure>?

        executor.paste(entry: sampleEntry, target: target, closePanel: { trace.events.append("close") }) {
            result = $0
        }

        XCTAssertEqual(result?.failureValue, .targetUnavailable)
        XCTAssertEqual(trace.events, ["write", "close", "activate"])
    }

    func testDispatchFailureIsVisibleAndDoesNotDeleteTheEntry() {
        let trace = Trace()
        let writer = FakeHistoryPasteboardWriter(changeCount: 9, trace: trace)
        let dispatcher = FakePasteCommandDispatcher(trace: trace, result: false)
        let executor = makeExecutor(writer: writer, dispatcher: dispatcher, register: { _ in })
        var result: Result<Void, HistoryPasteFailure>?

        executor.paste(entry: sampleEntry, target: FakeHistoryPasteTarget(trace: trace), closePanel: { trace.events.append("close") }) {
            result = $0
        }

        XCTAssertEqual(result?.failureValue, .commandDispatchFailed)
        XCTAssertEqual(trace.events, ["write", "close", "activate", "dispatch"])
    }

    func testPasteWaitsForTargetToBecomeActiveBeforeDispatching() {
        let trace = Trace()
        let writer = FakeHistoryPasteboardWriter(changeCount: 10, trace: trace)
        let dispatcher = FakePasteCommandDispatcher(trace: trace, result: true)
        let target = FakeHistoryPasteTarget(trace: trace, activeResults: [false, true])
        let executor = makeExecutor(writer: writer, dispatcher: dispatcher, register: { _ in })
        var result: Result<Void, HistoryPasteFailure>?

        executor.paste(entry: sampleEntry, target: target, closePanel: { trace.events.append("close") }) {
            result = $0
        }

        XCTAssertNoThrow(try result?.get())
        XCTAssertEqual(trace.events, ["write", "close", "activate", "dispatch"])
        XCTAssertEqual(target.activeCheckCount, 2)
    }

    func testPasteFailsWithoutDispatchWhenTargetNeverBecomesActive() {
        let trace = Trace()
        let writer = FakeHistoryPasteboardWriter(changeCount: 11, trace: trace)
        let dispatcher = FakePasteCommandDispatcher(trace: trace, result: true)
        let target = FakeHistoryPasteTarget(trace: trace, activeResults: [false, false, false])
        let executor = makeExecutor(writer: writer, dispatcher: dispatcher, register: { _ in })
        var result: Result<Void, HistoryPasteFailure>?

        executor.paste(entry: sampleEntry, target: target, closePanel: { trace.events.append("close") }) {
            result = $0
        }

        XCTAssertEqual(result?.failureValue, .targetUnavailable)
        XCTAssertEqual(trace.events, ["write", "close", "activate"])
        XCTAssertEqual(target.activeCheckCount, 3)
    }

    func testCancelCanReactivateCapturedTargetWithoutWritingOrDispatching() {
        let trace = Trace()
        let target = FakeHistoryPasteTarget(trace: trace)

        XCTAssertTrue(HistoryFocusRestorer.returnToCapturedTarget(target))

        XCTAssertEqual(trace.events, ["activate"])
    }

    private var sampleEntry: HistoryEntry {
        HistoryEntry(id: UUID(), text: "safe fixture", capturedAt: .now)
    }

    private func makeExecutor(
        permission: AccessibilityPermissionState = .granted,
        writer: FakeHistoryPasteboardWriter,
        dispatcher: FakePasteCommandDispatcher,
        register: @escaping (Int) -> Void
    ) -> HistoryPasteExecutor {
        HistoryPasteExecutor(
            permissionService: FakeHistoryPermissionService(state: permission),
            pasteboardWriter: writer,
            registerSelfWrite: register,
            commandDispatcher: dispatcher,
            scheduleAfterActivation: { $0() }
        )
    }
}

private final class InMemoryHistoryStore: HistoryStoring {
    var entries: [HistoryEntry]

    init(entries: [HistoryEntry] = []) {
        self.entries = entries
    }

    func fetchCurrent(since cutoff: Date) throws -> [HistoryEntry] {
        entries.filter { $0.capturedAt > cutoff }
    }

    func create(text: String, capturedAt: Date) throws -> HistoryEntry {
        let entry = HistoryEntry(id: UUID(), text: text, capturedAt: capturedAt)
        entries.append(entry)
        return entry
    }

    func delete(id: UUID) throws {
        entries.removeAll { $0.id == id }
    }

    func clearAll() throws {
        entries = []
    }
}

private final class FakeHistoryPermissionService: AccessibilityPermissionChecking {
    var state: AccessibilityPermissionState

    init(state: AccessibilityPermissionState) {
        self.state = state
    }

    func refresh() -> AccessibilityPermissionState { state }
    func requestAccess() -> AccessibilityPermissionState { state }
    func openSystemSettings() {}
}

private final class Trace {
    var events: [String] = []
}

private final class FakeHistoryPasteboardWriter: HistoryPasteboardWriting {
    let changeCount: Int
    let trace: Trace
    private(set) var writtenTexts: [String] = []

    init(changeCount: Int, trace: Trace) {
        self.changeCount = changeCount
        self.trace = trace
    }

    func write(text: String) throws -> Int {
        trace.events.append("write")
        writtenTexts.append(text)
        return changeCount
    }
}

private final class FakeHistoryPasteTarget: HistoryPasteTarget {
    let trace: Trace
    var isTerminated: Bool
    let activateResult: Bool
    private var activeResults: [Bool]
    private(set) var activeCheckCount = 0

    init(
        trace: Trace,
        terminated: Bool = false,
        activateResult: Bool = true,
        activeResults: [Bool] = [true]
    ) {
        self.trace = trace
        isTerminated = terminated
        self.activateResult = activateResult
        self.activeResults = activeResults
    }

    var isActive: Bool {
        activeCheckCount += 1
        if activeResults.count > 1 {
            return activeResults.removeFirst()
        }
        return activeResults.first ?? false
    }

    func activate() -> Bool {
        trace.events.append("activate")
        return activateResult
    }
}

private final class FakePasteCommandDispatcher: TaggedPasteCommandDispatching {
    let trace: Trace
    let result: Bool

    init(trace: Trace, result: Bool) {
        self.trace = trace
        self.result = result
    }

    func postTaggedCommandV() -> Bool {
        trace.events.append("dispatch")
        return result
    }
}

private extension Result where Success == Void, Failure == HistoryPasteFailure {
    var failureValue: HistoryPasteFailure? {
        guard case let .failure(failure) = self else { return nil }
        return failure
    }
}
