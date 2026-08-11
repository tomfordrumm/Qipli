import ApplicationServices
import Carbon.HIToolbox
import XCTest
@testable import Qipli

final class InputCoordinatorTests: XCTestCase {
    func testDeniedPermissionStopsAdapterWithoutStartingIt() {
        let permission = FakePermissionService(state: .denied)
        let adapter = FakeInputAdapter()
        let coordinator = InputCoordinator(permissionService: permission, eventAdapter: adapter)

        XCTAssertEqual(coordinator.refreshAndStart(), .permissionRequired)
        XCTAssertEqual(adapter.startCount, 0)
        XCTAssertEqual(adapter.stopCount, 1)
    }

    func testGrantedPermissionStartsAdapterAndForwardsHotKey() {
        let permission = FakePermissionService(state: .granted)
        let adapter = FakeInputAdapter()
        let coordinator = InputCoordinator(permissionService: permission, eventAdapter: adapter)
        var receivedHotKey: GlobalHotKey?
        coordinator.onHotKey = { receivedHotKey = $0 }

        XCTAssertEqual(coordinator.refreshAndStart(), .ready)
        adapter.emit(.history)

        XCTAssertEqual(adapter.startCount, 1)
        XCTAssertEqual(receivedHotKey, .history)
    }

    func testAdapterFailureIsVisibleThroughCoordinator() {
        let permission = FakePermissionService(state: .granted)
        let adapter = FakeInputAdapter(startResult: .unavailable("listener disabled"))
        let coordinator = InputCoordinator(permissionService: permission, eventAdapter: adapter)

        XCTAssertEqual(coordinator.refreshAndStart(), .unavailable("listener disabled"))
        adapter.emitStatus(.unavailable("recovery exhausted"))

        XCTAssertEqual(coordinator.status, .unavailable("recovery exhausted"))
    }

    func testRefreshingAfterAdapterFailureRebuildsTheAdapter() {
        let permission = FakePermissionService(state: .granted)
        let adapter = FakeInputAdapter(startResults: [
            .unavailable("recovery exhausted"),
            .ready
        ])
        let coordinator = InputCoordinator(permissionService: permission, eventAdapter: adapter)

        XCTAssertEqual(coordinator.refreshAndStart(), .unavailable("recovery exhausted"))
        XCTAssertEqual(coordinator.refreshAndStart(), .ready)
        XCTAssertEqual(adapter.stopCount, 1)
        XCTAssertEqual(adapter.startCount, 2)
    }
}

final class AccessibilityPermissionServiceTests: XCTestCase {
    func testPermissionStateDistinguishesNotRequestedDeniedAndGranted() {
        var isTrusted = false
        var promptCount = 0
        let service = AccessibilityPermissionService(
            trustChecker: { isTrusted },
            promptRequester: {
                promptCount += 1
                return false
            },
            settingsOpener: {}
        )

        XCTAssertEqual(service.state, .notRequested)
        XCTAssertEqual(service.requestAccess(), .denied)
        XCTAssertEqual(promptCount, 1)

        isTrusted = true
        XCTAssertEqual(service.refresh(), .granted)
    }

    func testRequestAccessMonitorsUntilPermissionBecomesGranted() {
        var isTrusted = false
        let scheduler = ManualPermissionMonitoringScheduler()
        let service = AccessibilityPermissionService(
            trustChecker: { isTrusted },
            promptRequester: { false },
            settingsOpener: {},
            monitoringScheduler: scheduler.schedule
        )

        XCTAssertEqual(service.requestAccess(), .denied)
        XCTAssertTrue(scheduler.isScheduled)

        isTrusted = true
        scheduler.tick()

        XCTAssertEqual(service.state, .granted)
        XCTAssertEqual(scheduler.cancelCount, 1)
    }

    func testOpeningSettingsMonitorsPermissionRevocation() {
        var isTrusted = true
        var openCount = 0
        let scheduler = ManualPermissionMonitoringScheduler()
        let service = AccessibilityPermissionService(
            trustChecker: { isTrusted },
            promptRequester: { true },
            settingsOpener: { openCount += 1 },
            monitoringScheduler: scheduler.schedule
        )

        service.openSystemSettings()
        isTrusted = false
        scheduler.tick()

        XCTAssertEqual(openCount, 1)
        XCTAssertEqual(service.state, .denied)
        XCTAssertEqual(scheduler.cancelCount, 1)
    }

    func testSettingsMonitoringStopsAfterBoundedUnchangedPolls() {
        let scheduler = ManualPermissionMonitoringScheduler()
        let service = AccessibilityPermissionService(
            trustChecker: { false },
            promptRequester: { false },
            settingsOpener: {},
            monitoringPollLimit: 2,
            monitoringScheduler: scheduler.schedule
        )

        service.openSystemSettings()
        scheduler.tick()
        XCTAssertEqual(scheduler.cancelCount, 0)

        scheduler.tick()
        XCTAssertEqual(service.state, .denied)
        XCTAssertEqual(scheduler.cancelCount, 1)
    }
}

final class SyntheticEventMarkerTests: XCTestCase {
    func testOnlyExactMarkerIsRecognizedAsQipliSyntheticInput() {
        XCTAssertTrue(SyntheticEventMarker.isQipliSynthetic(sourceUserData: SyntheticEventMarker.sourceUserData))
        XCTAssertFalse(SyntheticEventMarker.isQipliSynthetic(sourceUserData: 0))
        XCTAssertFalse(SyntheticEventMarker.isQipliSynthetic(sourceUserData: SyntheticEventMarker.sourceUserData - 1))
    }
}

final class CGEventTapAdapterClassificationTests: XCTestCase {
    func testRecognizesOnlyTheConfiguredCommandShiftHotKeys() throws {
        let history = try makeKeyEvent(keyCode: CGKeyCode(kVK_ANSI_V), flags: [.maskCommand, .maskShift])
        let pasteStack = try makeKeyEvent(keyCode: CGKeyCode(kVK_ANSI_C), flags: [.maskCommand, .maskShift])

        XCTAssertEqual(CGEventTapAdapter.hotKey(for: history), .history)
        XCTAssertEqual(CGEventTapAdapter.hotKey(for: pasteStack), .pasteStack)
    }

    func testOrdinaryCommandVAndTaggedSyntheticInputAreIgnored() throws {
        let ordinaryPaste = try makeKeyEvent(keyCode: CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
        let ordinaryCopy = try makeKeyEvent(keyCode: CGKeyCode(kVK_ANSI_C), flags: .maskCommand)
        let syntheticHotKey = try makeKeyEvent(keyCode: CGKeyCode(kVK_ANSI_V), flags: [.maskCommand, .maskShift])
        syntheticHotKey.setIntegerValueField(.eventSourceUserData, value: SyntheticEventMarker.sourceUserData)

        XCTAssertNil(CGEventTapAdapter.hotKey(for: ordinaryPaste))
        XCTAssertNil(CGEventTapAdapter.hotKey(for: ordinaryCopy))
        XCTAssertNil(CGEventTapAdapter.hotKey(for: syntheticHotKey))
    }

    func testActiveTapConsumesOnlyExactUntaggedQipliHotkeyKeyDownEvents() throws {
        let history = try makeKeyEvent(keyCode: CGKeyCode(kVK_ANSI_V), flags: [.maskCommand, .maskShift])
        let stack = try makeKeyEvent(keyCode: CGKeyCode(kVK_ANSI_C), flags: [.maskCommand, .maskShift])
        let ordinaryPaste = try makeKeyEvent(keyCode: CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
        let modifiedPaste = try makeKeyEvent(keyCode: CGKeyCode(kVK_ANSI_V), flags: [.maskCommand, .maskShift, .maskAlternate])
        let unrelatedHotKey = try makeKeyEvent(keyCode: CGKeyCode(kVK_ANSI_X), flags: [.maskCommand, .maskShift])
        let taggedHistory = try makeKeyEvent(keyCode: CGKeyCode(kVK_ANSI_V), flags: [.maskCommand, .maskShift])
        taggedHistory.setIntegerValueField(.eventSourceUserData, value: SyntheticEventMarker.sourceUserData)
        let taggedCopy = try makeKeyEvent(keyCode: CGKeyCode(kVK_ANSI_C), flags: .maskCommand)
        taggedCopy.setIntegerValueField(.eventSourceUserData, value: SyntheticEventMarker.sourceUserData)

        XCTAssertEqual(CGEventTapAdapter.consumedHotKey(type: .keyDown, event: history), .history)
        XCTAssertEqual(CGEventTapAdapter.consumedHotKey(type: .keyDown, event: stack), .pasteStack)
        XCTAssertNil(CGEventTapAdapter.consumedHotKey(type: .keyUp, event: history))
        XCTAssertNil(CGEventTapAdapter.consumedHotKey(type: .keyDown, event: ordinaryPaste))
        XCTAssertNil(CGEventTapAdapter.consumedHotKey(type: .keyDown, event: modifiedPaste))
        XCTAssertNil(CGEventTapAdapter.consumedHotKey(type: .keyDown, event: unrelatedHotKey))
        XCTAssertNil(CGEventTapAdapter.consumedHotKey(type: .keyDown, event: taggedHistory))
        XCTAssertNil(CGEventTapAdapter.consumedAction(type: .keyDown, event: taggedCopy, stackSessionIsActive: true))
    }

    func testEscapeIsConsumedOnlyForAnActiveStackWithoutSemanticModifiers() throws {
        let escape = try makeKeyEvent(keyCode: CGKeyCode(kVK_Escape), flags: [])
        let modifiedEscape = try makeKeyEvent(keyCode: CGKeyCode(kVK_Escape), flags: .maskShift)
        let taggedEscape = try makeKeyEvent(keyCode: CGKeyCode(kVK_Escape), flags: [])
        taggedEscape.setIntegerValueField(.eventSourceUserData, value: SyntheticEventMarker.sourceUserData)
        let ordinaryPaste = try makeKeyEvent(keyCode: CGKeyCode(kVK_ANSI_V), flags: .maskCommand)

        XCTAssertNil(CGEventTapAdapter.consumedAction(type: .keyDown, event: escape, stackSessionIsActive: false))
        XCTAssertEqual(CGEventTapAdapter.consumedAction(type: .keyDown, event: escape, stackSessionIsActive: true), .cancelPasteStack)
        XCTAssertNil(CGEventTapAdapter.consumedAction(type: .keyUp, event: escape, stackSessionIsActive: true))
        XCTAssertNil(CGEventTapAdapter.consumedAction(type: .keyDown, event: modifiedEscape, stackSessionIsActive: true))
        XCTAssertNil(CGEventTapAdapter.consumedAction(type: .keyDown, event: taggedEscape, stackSessionIsActive: true))
        XCTAssertNil(CGEventTapAdapter.consumedAction(type: .keyDown, event: ordinaryPaste, stackSessionIsActive: true))
    }

    func testTapUsesActiveFilteringConfiguration() {
        XCTAssertEqual(CGEventTapAdapter.eventTapOptions, .defaultTap)
    }

    func testOrdinaryCommandVIsConsumedOnlyWhenStackAdmissionSaysSo() throws {
        let ordinaryPaste = try makeKeyEvent(keyCode: CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
        let modifiedPaste = try makeKeyEvent(keyCode: CGKeyCode(kVK_ANSI_V), flags: [.maskCommand, .maskAlternate])
        let taggedPaste = try makeKeyEvent(keyCode: CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
        taggedPaste.setIntegerValueField(.eventSourceUserData, value: SyntheticEventMarker.sourceUserData)

        XCTAssertNil(CGEventTapAdapter.consumedAction(
            type: .keyDown,
            event: ordinaryPaste,
            stackSessionIsActive: true,
            stackPasteInterception: { .passThrough }
        ))
        XCTAssertEqual(CGEventTapAdapter.consumedAction(
            type: .keyDown,
            event: ordinaryPaste,
            stackSessionIsActive: true,
            stackPasteInterception: { .consumeAndDispatch }
        ), .pasteStackItem)
        XCTAssertEqual(CGEventTapAdapter.consumedAction(
            type: .keyDown,
            event: ordinaryPaste,
            stackSessionIsActive: true,
            stackPasteInterception: { .consume }
        ), .consumePasteStackItem)
        XCTAssertNil(CGEventTapAdapter.consumedAction(
            type: .keyUp,
            event: ordinaryPaste,
            stackSessionIsActive: true,
            stackPasteInterception: { .consumeAndDispatch }
        ))
        XCTAssertNil(CGEventTapAdapter.consumedAction(
            type: .keyDown,
            event: modifiedPaste,
            stackSessionIsActive: true,
            stackPasteInterception: { .consumeAndDispatch }
        ))
        XCTAssertNil(CGEventTapAdapter.consumedAction(
            type: .keyDown,
            event: taggedPaste,
            stackSessionIsActive: true,
            stackPasteInterception: { .consumeAndDispatch }
        ))
    }

    func testReactivatePreviousConsumesOnlyExactAdmittedCommandShiftZ() throws {
        let reactivate = try makeKeyEvent(keyCode: CGKeyCode(kVK_ANSI_Z), flags: [.maskCommand, .maskShift])
        let modified = try makeKeyEvent(keyCode: CGKeyCode(kVK_ANSI_Z), flags: [.maskCommand, .maskShift, .maskAlternate])
        let tagged = try makeKeyEvent(keyCode: CGKeyCode(kVK_ANSI_Z), flags: [.maskCommand, .maskShift])
        tagged.setIntegerValueField(.eventSourceUserData, value: SyntheticEventMarker.sourceUserData)

        XCTAssertNil(CGEventTapAdapter.consumedAction(
            type: .keyDown,
            event: reactivate,
            stackSessionIsActive: true,
            reactivationPreviousInterception: { .passThrough }
        ))
        XCTAssertEqual(CGEventTapAdapter.consumedAction(
            type: .keyDown,
            event: reactivate,
            stackSessionIsActive: true,
            reactivationPreviousInterception: { .consumeAndReactivate }
        ), .reactivatePreviousStackItem)
        XCTAssertEqual(CGEventTapAdapter.consumedAction(
            type: .keyDown,
            event: reactivate,
            stackSessionIsActive: true,
            reactivationPreviousInterception: { .consume }
        ), .consumeReactivatePreviousStackItem)
        XCTAssertNil(CGEventTapAdapter.consumedAction(
            type: .keyUp,
            event: reactivate,
            stackSessionIsActive: true,
            reactivationPreviousInterception: { .consumeAndReactivate }
        ))
        XCTAssertNil(CGEventTapAdapter.consumedAction(
            type: .keyDown,
            event: modified,
            stackSessionIsActive: true,
            reactivationPreviousInterception: { .consumeAndReactivate }
        ))
        XCTAssertNil(CGEventTapAdapter.consumedAction(
            type: .keyDown,
            event: tagged,
            stackSessionIsActive: true,
            reactivationPreviousInterception: { .consumeAndReactivate }
        ))
    }

    private func makeKeyEvent(keyCode: CGKeyCode, flags: CGEventFlags) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(
            keyboardEventSource: CGEventSource(stateID: .combinedSessionState),
            virtualKey: keyCode,
            keyDown: true
        ))
        event.flags = flags
        return event
    }
}

final class EventTapRecoveryPolicyTests: XCTestCase {
    func testRecoveryIsBoundedUntilHealthyInputIsObserved() {
        var policy = EventTapRecoveryPolicy(maximumAttempts: 2)

        XCTAssertTrue(policy.permitsRecovery())
        XCTAssertTrue(policy.permitsRecovery())
        XCTAssertFalse(policy.permitsRecovery())

        policy.recordHealthyEvent()
        XCTAssertTrue(policy.permitsRecovery())
    }
}

final class CGEventTapAdapterRecoveryTests: XCTestCase {
    func testDisabledTapRecoveryBecomesUnavailableAfterBoundedFailures() {
        let adapter = CGEventTapAdapter()
        var attempts = 0

        adapter.simulateDisabledTapForTesting {
            attempts += 1
            return false
        }

        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(
            adapter.status,
            .unavailable("macOS repeatedly disabled Qipli’s global input listener. Open Permission Status and try again.")
        )
    }

    func testDisabledTapRecoveryReturnsReadyWhenRetrySucceeds() {
        let adapter = CGEventTapAdapter()

        adapter.simulateDisabledTapForTesting { true }

        XCTAssertEqual(adapter.status, .ready)
    }
}

private final class FakePermissionService: AccessibilityPermissionChecking {
    var state: AccessibilityPermissionState

    init(state: AccessibilityPermissionState) {
        self.state = state
    }

    func refresh() -> AccessibilityPermissionState { state }
    func requestAccess() -> AccessibilityPermissionState { state }
    func openSystemSettings() {}
}

private final class FakeInputAdapter: GlobalInputEventAdapting {
    private(set) var status: GlobalInputStatus = .stopped
    var onHotKey: ((GlobalHotKey) -> Void)?
    var onEscape: (() -> Void)?
    var onStackPaste: (() -> Void)?
    var onReactivatePrevious: (() -> Void)?
    var shouldConsumeEscape: (() -> Bool)?
    var stackPasteInterception: (() -> StackPasteInputDisposition)?
    var reactivationPreviousInterception: (() -> StackReactivationInputDisposition)?
    var onStatusChange: ((GlobalInputStatus) -> Void)?
    private var startResults: [GlobalInputStatus]
    private(set) var startCount = 0
    private(set) var stopCount = 0

    init(startResult: GlobalInputStatus = .ready) {
        startResults = [startResult]
    }

    init(startResults: [GlobalInputStatus]) {
        precondition(!startResults.isEmpty)
        self.startResults = startResults
    }

    func start() -> GlobalInputStatus {
        startCount += 1
        status = startResults[min(startCount - 1, startResults.count - 1)]
        return status
    }

    func stop() {
        stopCount += 1
        status = .stopped
    }

    func emit(_ hotKey: GlobalHotKey) {
        onHotKey?(hotKey)
    }

    func emitStatus(_ status: GlobalInputStatus) {
        self.status = status
        onStatusChange?(status)
    }
}

private final class ManualPermissionMonitoringScheduler {
    private var action: (() -> Void)?
    private(set) var cancelCount = 0
    var isScheduled: Bool { action != nil }

    lazy var schedule: (TimeInterval, @escaping () -> Void) -> () -> Void = { [weak self] _, action in
        self?.action = action
        return { [weak self] in
            self?.cancelCount += 1
            self?.action = nil
        }
    }

    func tick() {
        action?()
    }
}
