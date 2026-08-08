import AppKit
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
        let first = makeEntry("alpha", offset: 3)
        let second = makeEntry("alphabet", offset: 2)
        let third = makeEntry("beta", offset: 1)
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
        let first = makeEntry("needle one", offset: 3)
        let second = makeEntry("needle two", offset: 2)
        let third = makeEntry("needle three", offset: 1)
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

    func testPromotionStorageFailureDoesNotClaimPasteFailureOrChangeOccurrence() {
        let entry = makeEntry("stable", offset: 1)
        let store = InMemoryHistoryStore(entries: [entry], markUsedError: HistoryStoreError.unavailable)
        let viewModel = HistoryViewModel(service: HistoryService(store: store))

        viewModel.reload(selectFirstResult: true)
        viewModel.markUsedAfterSuccessfulPaste(id: entry.id)

        XCTAssertEqual(viewModel.selectedEntry, entry)
        XCTAssertNil(viewModel.pasteFailure)
        XCTAssertEqual(store.entries, [entry])
    }

    func testFreshPresentationViewportResetSignalIsIndependentFromSearchFocus() {
        let first = makeEntry("first", offset: 2)
        let second = makeEntry("second", offset: 1)
        let viewModel = HistoryViewModel(service: HistoryService(store: InMemoryHistoryStore(entries: [first, second])))

        viewModel.prepareForPresentation()
        viewModel.requestPresentationViewportReset()

        XCTAssertEqual(viewModel.selectedEntryID, first.id)
        XCTAssertEqual(viewModel.presentationViewportResetRequestID, 1)
        XCTAssertEqual(viewModel.searchFocusRequestID, 0)

        viewModel.requestSearchFocus()
        XCTAssertEqual(viewModel.presentationViewportResetRequestID, 1)
        XCTAssertEqual(viewModel.searchFocusRequestID, 1)
    }

    private func makeEntry(_ text: String, offset: TimeInterval) -> HistoryEntry {
        HistoryEntry(id: UUID(), text: text, activityAt: Date.now.addingTimeInterval(offset))
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
        let entry = HistoryEntry(id: UUID(), text: "line α\nline β", activityAt: .now)
        var result: Result<Void, HistoryPasteFailure>?

        executor.paste(entry: entry, target: target, closePanel: { trace.events.append("close") }) { result = $0 }

        XCTAssertEqual(writer.writtenTexts, [entry.text])
        XCTAssertEqual(registeredChanges, [41])
        XCTAssertEqual(trace.events, ["write", "activate", "close", "dispatch"])
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
        var completionCount = 0

        executor.paste(entry: sampleEntry, target: target, closePanel: { trace.events.append("close") }) {
            result = $0
            completionCount += 1
        }

        XCTAssertEqual(result?.failureValue, .targetUnavailable)
        XCTAssertEqual(trace.events, ["write", "activate"])
        XCTAssertEqual(writer.writtenTexts.count, 1)
        XCTAssertEqual(completionCount, 1)
    }

    func testDispatchFailureIsVisibleAndDoesNotDeleteTheEntry() {
        let trace = Trace()
        let writer = FakeHistoryPasteboardWriter(changeCount: 9, trace: trace)
        let dispatcher = FakePasteCommandDispatcher(trace: trace, result: false)
        let executor = makeExecutor(writer: writer, dispatcher: dispatcher, register: { _ in })
        var result: Result<Void, HistoryPasteFailure>?

        executor.paste(entry: sampleEntry, target: FakeHistoryPasteTarget(trace: trace), closePanel: { trace.events.append("close") }) { result = $0 }

        XCTAssertEqual(result?.failureValue, .commandDispatchFailed)
        XCTAssertEqual(trace.events, ["write", "activate", "close", "dispatch"])
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
        XCTAssertEqual(trace.events, ["write", "activate", "close", "dispatch"])
        XCTAssertEqual(target.activeCheckCount, 2)
    }

    func testPasteFailsWithoutDispatchWhenTargetNeverBecomesActive() {
        let trace = Trace()
        let writer = FakeHistoryPasteboardWriter(changeCount: 11, trace: trace)
        let dispatcher = FakePasteCommandDispatcher(trace: trace, result: true)
        let target = FakeHistoryPasteTarget(trace: trace, activeResults: [false, false, false])
        let executor = makeExecutor(writer: writer, dispatcher: dispatcher, register: { _ in })
        var result: Result<Void, HistoryPasteFailure>?
        var completionCount = 0

        executor.paste(entry: sampleEntry, target: target, closePanel: { trace.events.append("close") }) {
            result = $0
            completionCount += 1
        }

        XCTAssertEqual(result?.failureValue, .targetUnavailable)
        XCTAssertEqual(trace.events, ["write", "activate"])
        XCTAssertEqual(target.activeCheckCount, 3)
        XCTAssertEqual(writer.writtenTexts.count, 1)
        XCTAssertEqual(completionCount, 1)
    }

    func testCancelCanReactivateCapturedTargetWithoutWritingOrDispatching() {
        let trace = Trace()
        let target = FakeHistoryPasteTarget(trace: trace)

        XCTAssertTrue(HistoryFocusRestorer.returnToCapturedTarget(target))

        XCTAssertEqual(trace.events, ["activate"])
    }

    private var sampleEntry: HistoryEntry {
        HistoryEntry(id: UUID(), text: "safe fixture", activityAt: .now)
    }

    private func makeExecutor(
        permission: AccessibilityPermissionState = .granted,
        writer: FakeHistoryPasteboardWriter,
        dispatcher: FakePasteCommandDispatcher,
        activationWaitPolicy: HistoryTargetActivationWaitPolicy = HistoryTargetActivationWaitPolicy(
            retryInterval: 0.1,
            timeout: 0.2
        ),
        register: @escaping (Int) -> Void
    ) -> HistoryPasteExecutor {
        let clock = FakeActivationClock()
        return HistoryPasteExecutor(
            permissionService: FakeHistoryPermissionService(state: permission),
            pasteboardWriter: writer,
            registerSelfWrite: register,
            commandDispatcher: dispatcher,
            activationWaitPolicy: activationWaitPolicy,
            scheduleAfterActivation: { interval, work in
                clock.advance(by: interval)
                work()
            },
            now: { clock.now }
        )
    }
}

@MainActor
final class PanelActivationPresenterTests: XCTestCase {
    func testUsesStrongUserInitiatedActivationAndRunsCompletionWhenActive() {
        let application = FakeQipliApplication(activeResults: [false, true])
        let presenter = PanelActivationPresenter(
            application: application,
            scheduleNextMainRunLoop: { $0() }
        )
        var completionCount = 0

        presenter.presentImmediatelyThenWhenActive(
            requiresStrongUserActivation: true,
            present: {},
            whenActive: {
                completionCount += 1
            }
        )

        XCTAssertEqual(application.strongActivationRequestCount, 1)
        XCTAssertEqual(application.activationRequestCount, 0)
        XCTAssertEqual(application.activeCheckCount, 2)
        XCTAssertEqual(completionCount, 1)
    }

    func testRegularPanelUsesCooperativeActivation() {
        let application = FakeQipliApplication(activeResults: [true])
        let presenter = PanelActivationPresenter(
            application: application,
            scheduleNextMainRunLoop: { $0() }
        )

        presenter.presentImmediatelyThenWhenActive(
            requiresStrongUserActivation: false,
            present: {},
            whenActive: {}
        )

        XCTAssertEqual(application.activationRequestCount, 1)
        XCTAssertEqual(application.strongActivationRequestCount, 0)
    }

    func testExhaustedActivationStillRunsImmediatePresentationAndSkipsActiveCompletion() {
        let application = FakeQipliApplication(activeResults: [false, false, false])
        let presenter = PanelActivationPresenter(
            application: application,
            scheduleNextMainRunLoop: { $0() }
        )
        var presentationCount = 0
        var completionCount = 0

        presenter.presentImmediatelyThenWhenActive(
            requiresStrongUserActivation: true,
            present: { presentationCount += 1 },
            whenActive: { completionCount += 1 }
        )

        XCTAssertEqual(application.strongActivationRequestCount, 1)
        XCTAssertEqual(application.activationRequestCount, 0)
        XCTAssertEqual(application.activeCheckCount, 3)
        XCTAssertEqual(presentationCount, 1)
        XCTAssertEqual(completionCount, 0)
    }
}

@MainActor
final class HistoryPanelIntentTests: XCTestCase {
    func testKeyboardIntentsDriveSelectionPasteAndClose() {
        let entry = makeEntry("fixture", offset: 1)
        let trace = HistoryPanelIntentTrace(selectedEntryID: entry.id)
        let executor = makeExecutor(trace: trace)

        executor.execute(.moveSelection(by: 1))
        executor.execute(.pasteSelected)
        executor.execute(.close)

        XCTAssertEqual(trace.selectionOffsets, [1])
        XCTAssertEqual(trace.pasteCount, 1)
        XCTAssertEqual(trace.closeCount, 1)
    }

    func testDoubleClickSelectsExactIDThenPastesOnceWhenAllowed() {
        let entry = makeEntry("fixture", offset: 1)
        let trace = HistoryPanelIntentTrace(selectedEntryID: nil)
        let executor = makeExecutor(trace: trace)

        executor.execute(.selectAndPaste(entry.id))

        XCTAssertEqual(trace.selectedIDs, [entry.id])
        XCTAssertEqual(trace.pasteCount, 1)
    }

    func testDoubleClickDoesNotPasteWhenPermissionIsUnavailable() {
        let entry = makeEntry("fixture", offset: 1)
        let trace = HistoryPanelIntentTrace(selectedEntryID: nil, canPaste: false)

        makeExecutor(trace: trace).execute(.selectAndPaste(entry.id))

        XCTAssertEqual(trace.selectedIDs, [entry.id])
        XCTAssertEqual(trace.pasteCount, 0)
    }

    func testDeleteDoesNotSelectOrPaste() {
        let entry = makeEntry("fixture", offset: 1)
        let trace = HistoryPanelIntentTrace(selectedEntryID: nil)

        makeExecutor(trace: trace).execute(.delete(entry))

        XCTAssertEqual(trace.deletedIDs, [entry.id])
        XCTAssertTrue(trace.selectedIDs.isEmpty)
        XCTAssertEqual(trace.pasteCount, 0)
    }

    func testEmptyQueryAdmitsTheExactSelectedEntryForSearchDelete() {
        let selected = makeEntry("selected fixture", offset: 1)
        let other = makeEntry("other fixture", offset: 2)

        let admitted = HistorySearchDeleteAdmission.selectedEntry(
            query: "",
            state: .list([selected, other]),
            selectedEntry: selected
        )

        XCTAssertEqual(admitted?.id, selected.id)
    }

    func testNonEmptyQueryNoSelectionAndNonListStatePassSearchDeleteThrough() {
        let entry = makeEntry("fixture", offset: 1)

        XCTAssertNil(HistorySearchDeleteAdmission.selectedEntry(
            query: "f",
            state: .list([entry]),
            selectedEntry: entry
        ))
        XCTAssertNil(HistorySearchDeleteAdmission.selectedEntry(
            query: "",
            state: .list([entry]),
            selectedEntry: nil
        ))
        XCTAssertNil(HistorySearchDeleteAdmission.selectedEntry(
            query: "",
            state: .empty,
            selectedEntry: entry
        ))
    }

    func testLocalDeleteMonitorAdmissionRequiresFocusedKeyWindowAndPhysicalUnmodifiedNonrepeatDelete() {
        let entry = makeEntry("selected fixture", offset: 1)
        let sharedContext: (query: String, state: HistoryViewState, selectedEntry: HistoryEntry?) = (
            "",
            .list([entry]),
            entry
        )
        let backward = HistorySearchDeleteEvent(key: .backward, hasDisallowedModifiers: false, isRepeat: false)
        let forward = HistorySearchDeleteEvent(key: .forward, hasDisallowedModifiers: false, isRepeat: false)

        XCTAssertEqual(HistorySearchDeleteAdmission.selectedEntry(
            for: backward,
            isSearchFocused: true,
            isEventInKeyWindow: true,
            query: sharedContext.query,
            state: sharedContext.state,
            selectedEntry: sharedContext.selectedEntry
        )?.id, entry.id)
        XCTAssertEqual(HistorySearchDeleteAdmission.selectedEntry(
            for: forward,
            isSearchFocused: true,
            isEventInKeyWindow: true,
            query: sharedContext.query,
            state: sharedContext.state,
            selectedEntry: sharedContext.selectedEntry
        )?.id, entry.id)

        let rejectedEvents = [
            HistorySearchDeleteEvent(key: .backward, hasDisallowedModifiers: true, isRepeat: false),
            HistorySearchDeleteEvent(key: .forward, hasDisallowedModifiers: false, isRepeat: true),
            HistorySearchDeleteEvent(key: .other, hasDisallowedModifiers: false, isRepeat: false)
        ]
        for event in rejectedEvents {
            XCTAssertNil(HistorySearchDeleteAdmission.selectedEntry(
                for: event,
                isSearchFocused: true,
                isEventInKeyWindow: true,
                query: sharedContext.query,
                state: sharedContext.state,
                selectedEntry: sharedContext.selectedEntry
            ))
        }

        XCTAssertNil(HistorySearchDeleteAdmission.selectedEntry(
            for: backward,
            isSearchFocused: false,
            isEventInKeyWindow: true,
            query: sharedContext.query,
            state: sharedContext.state,
            selectedEntry: sharedContext.selectedEntry
        ))
        XCTAssertNil(HistorySearchDeleteAdmission.selectedEntry(
            for: backward,
            isSearchFocused: true,
            isEventInKeyWindow: false,
            query: sharedContext.query,
            state: sharedContext.state,
            selectedEntry: sharedContext.selectedEntry
        ))
    }

    func testPhysicalDeleteEventNormalizationAcceptsCapsFnAndNumericPadButRejectsShortcutModifiers() throws {
        let backward = HistorySearchDeleteEvent(event: try makeKeyEvent(keyCode: 51))
        let forward = HistorySearchDeleteEvent(event: try makeKeyEvent(keyCode: 117))
        let other = HistorySearchDeleteEvent(event: try makeKeyEvent(keyCode: 0))
        let modified = HistorySearchDeleteEvent(event: try makeKeyEvent(
            keyCode: 51,
            modifierFlags: [.command, .capsLock, .function, .numericPad]
        ))
        let acceptedFlags = HistorySearchDeleteEvent(event: try makeKeyEvent(
            keyCode: 51,
            modifierFlags: [.capsLock, .function, .numericPad]
        ))

        XCTAssertEqual(backward.key, .backward)
        XCTAssertEqual(forward.key, .forward)
        XCTAssertEqual(other.key, .other)
        XCTAssertFalse(acceptedFlags.hasDisallowedModifiers)
        XCTAssertTrue(modified.hasDisallowedModifiers)
    }

    private func makeKeyEvent(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags = [],
        isARepeat: Bool = false
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: isARepeat,
            keyCode: keyCode
        ))
    }

    private func makeEntry(_ text: String, offset: TimeInterval) -> HistoryEntry {
        HistoryEntry(id: UUID(), text: text, activityAt: Date.now.addingTimeInterval(offset))
    }

    private func makeExecutor(trace: HistoryPanelIntentTrace) -> HistoryPanelIntentExecutor {
        HistoryPanelIntentExecutor(
            moveSelection: { trace.selectionOffsets.append($0) },
            select: {
                trace.selectedIDs.append($0)
                trace.selectedEntryID = $0
            },
            hasSelectedEntry: { trace.selectedEntryID != nil },
            canPaste: { trace.canPaste },
            pasteSelection: { trace.pasteCount += 1 },
            close: { trace.closeCount += 1 },
            delete: { trace.deletedIDs.append($0.id) }
        )
    }
}

@MainActor
private final class HistoryPanelIntentTrace {
    var selectedEntryID: UUID?
    var canPaste: Bool
    var selectionOffsets: [Int] = []
    var selectedIDs: [UUID] = []
    var pasteCount = 0
    var closeCount = 0
    var deletedIDs: [UUID] = []

    init(selectedEntryID: UUID?, canPaste: Bool = true) {
        self.selectedEntryID = selectedEntryID
        self.canPaste = canPaste
    }
}

private final class InMemoryHistoryStore: HistoryStoring {
    var entries: [HistoryEntry]
    var markUsedError: Error?

    init(entries: [HistoryEntry] = [], markUsedError: Error? = nil) {
        self.entries = entries
        self.markUsedError = markUsedError
    }

    func fetchCurrent(since cutoff: Date) throws -> [HistoryEntry] {
        entries
            .filter { $0.activityAt > cutoff }
            .sorted {
                if $0.activityAt != $1.activityAt {
                    return $0.activityAt > $1.activityAt
                }
                return $0.id.uuidString > $1.id.uuidString
            }
    }

    func create(text: String, activityAt: Date) throws -> HistoryEntry {
        let entry = HistoryEntry(id: UUID(), text: text, activityAt: activityAt)
        entries.append(entry)
        return entry
    }

    func markUsed(id: UUID, activityAt: Date) throws {
        if let markUsedError { throw markUsedError }
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries[index]
        entries[index] = HistoryEntry(id: entry.id, text: entry.text, activityAt: activityAt)
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

private final class FakeActivationClock {
    var now = Date(timeIntervalSinceReferenceDate: 0)

    func advance(by interval: TimeInterval) {
        now.addTimeInterval(interval)
    }
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

@MainActor
private final class FakeQipliApplication: QipliApplicationActivating {
    private var activeResults: [Bool]
    private(set) var activationRequestCount = 0
    private(set) var strongActivationRequestCount = 0
    private(set) var activeCheckCount = 0

    init(activeResults: [Bool]) {
        self.activeResults = activeResults
    }

    var isActive: Bool {
        activeCheckCount += 1
        if activeResults.count > 1 {
            return activeResults.removeFirst()
        }
        return activeResults.first ?? false
    }

    func requestActivation() {
        activationRequestCount += 1
    }

    func requestUserInitiatedActivation() {
        strongActivationRequestCount += 1
    }
}

private extension Result where Success == Void, Failure == HistoryPasteFailure {
    var failureValue: HistoryPasteFailure? {
        guard case let .failure(failure) = self else { return nil }
        return failure
    }
}
