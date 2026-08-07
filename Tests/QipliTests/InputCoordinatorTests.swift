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
        let syntheticHotKey = try makeKeyEvent(keyCode: CGKeyCode(kVK_ANSI_V), flags: [.maskCommand, .maskShift])
        syntheticHotKey.setIntegerValueField(.eventSourceUserData, value: SyntheticEventMarker.sourceUserData)

        XCTAssertNil(CGEventTapAdapter.hotKey(for: ordinaryPaste))
        XCTAssertNil(CGEventTapAdapter.hotKey(for: syntheticHotKey))
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
