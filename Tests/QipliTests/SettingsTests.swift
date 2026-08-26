import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Qipli

final class ShortcutPreferencesTests: XCTestCase {
    func testDefaultsMatchDocumentedQipliShortcuts() {
        let context = makePreferences()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }

        XCTAssertEqual(context.preferences.snapshot.history.displayValue, "⇧⌘V")
        XCTAssertEqual(context.preferences.snapshot.pasteStack.displayValue, "⇧⌘C")
        XCTAssertEqual(context.preferences.snapshot.reactivatePrevious.displayValue, "⇧⌘Z")
        XCTAssertFalse(context.preferences.recoveredDefaults)
    }

    func testValidSnapshotUpdateIsAvailableImmediatelyAndPersistsAcrossRestart() throws {
        let context = makePreferences()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let custom = ShortcutBinding(
            keyCode: UInt16(kVK_ANSI_H),
            keyRepresentation: "H",
            modifiers: [.control, .option]
        )

        try context.preferences.update(.history, binding: custom)

        XCTAssertEqual(context.preferences.currentSnapshot.history, custom)
        let reloaded = ShortcutPreferences(defaults: context.defaults, storageKey: context.storageKey)
        XCTAssertEqual(reloaded.snapshot.history, custom)
        XCTAssertEqual(reloaded.snapshot.pasteStack, ShortcutSnapshot.defaults.pasteStack)
        XCTAssertEqual(reloaded.snapshot.reactivatePrevious, ShortcutSnapshot.defaults.reactivatePrevious)
    }

    func testInvalidDuplicateAndProtectedBindingsLeaveLastWorkingSnapshotUntouched() {
        let context = makePreferences()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let original = context.preferences.snapshot

        XCTAssertThrowsError(try context.preferences.update(
            .history,
            binding: ShortcutBinding(
                keyCode: UInt16(kVK_ANSI_H),
                keyRepresentation: "H",
                modifiers: [.shift]
            )
        )) { error in
            XCTAssertEqual(error as? ShortcutValidationError, .missingPrimaryModifier)
        }
        XCTAssertThrowsError(try context.preferences.update(
            .history,
            binding: ShortcutBinding(
                keyCode: original.pasteStack.keyCode,
                keyRepresentation: "X",
                modifiers: original.pasteStack.modifiers
            )
        )) { error in
            XCTAssertEqual(error as? ShortcutValidationError, .duplicate)
        }
        XCTAssertThrowsError(try context.preferences.update(
            .history,
            binding: ShortcutBinding(
                keyCode: UInt16(kVK_ANSI_V),
                keyRepresentation: "V",
                modifiers: [.command]
            )
        )) { error in
            XCTAssertEqual(error as? ShortcutValidationError, .protectedCombination)
        }

        XCTAssertEqual(context.preferences.snapshot, original)
        XCTAssertEqual(context.preferences.currentSnapshot, original)
    }

    func testCorruptPreferencesRecoverTheWholeDefaultSnapshot() {
        let context = makePreferences()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        context.defaults.set(Data([0x01, 0x02, 0x03]), forKey: context.storageKey)

        let recovered = ShortcutPreferences(defaults: context.defaults, storageKey: context.storageKey)

        XCTAssertEqual(recovered.snapshot, .defaults)
        XCTAssertTrue(recovered.recoveredDefaults)
        let nextLaunch = ShortcutPreferences(defaults: context.defaults, storageKey: context.storageKey)
        XCTAssertEqual(nextLaunch.snapshot, .defaults)
        XCTAssertFalse(nextLaunch.recoveredDefaults)
    }

    func testResetChangesOnlyShortcutPreferences() throws {
        let context = makePreferences()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        context.defaults.set(true, forKey: "qipli.onboardingCompleted")
        try context.preferences.update(
            .history,
            binding: ShortcutBinding(
                keyCode: UInt16(kVK_ANSI_H),
                keyRepresentation: "H",
                modifiers: [.control, .option]
            )
        )

        context.preferences.resetToDefaults()

        XCTAssertEqual(context.preferences.snapshot, .defaults)
        XCTAssertTrue(context.defaults.bool(forKey: "qipli.onboardingCompleted"))
    }

    private func makePreferences() -> (
        preferences: ShortcutPreferences,
        defaults: UserDefaults,
        suiteName: String,
        storageKey: String
    ) {
        let suiteName = "QipliTests.Shortcuts.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let storageKey = "shortcuts"
        return (
            ShortcutPreferences(defaults: defaults, storageKey: storageKey),
            defaults,
            suiteName,
            storageKey
        )
    }
}

final class CustomShortcutInputTests: XCTestCase {
    func testCustomHistoryShortcutMatchesWithoutRelaunchAndDefaultStopsMatching() throws {
        let customHistory = ShortcutBinding(
            keyCode: UInt16(kVK_ANSI_H),
            keyRepresentation: "H",
            modifiers: [.control, .option]
        )
        let snapshot = ShortcutSnapshot.defaults.replacing(.history, with: customHistory)
        try ShortcutValidator.validate(snapshot)
        let customEvent = try makeKeyEvent(
            keyCode: CGKeyCode(kVK_ANSI_H),
            flags: [.maskControl, .maskAlternate]
        )
        let oldEvent = try makeKeyEvent(
            keyCode: CGKeyCode(kVK_ANSI_V),
            flags: [.maskCommand, .maskShift]
        )

        XCTAssertEqual(
            CGEventTapAdapter.consumedAction(
                type: .keyDown,
                event: customEvent,
                stackSessionIsActive: false,
                shortcutSnapshot: snapshot
            ),
            .hotKey(.history)
        )
        XCTAssertNil(CGEventTapAdapter.consumedAction(
            type: .keyDown,
            event: oldEvent,
            stackSessionIsActive: false,
            shortcutSnapshot: snapshot
        ))
    }

    func testCustomReactivatePreviousKeepsAdmissionAndOrdinaryPasteContracts() throws {
        let customReactivation = ShortcutBinding(
            keyCode: UInt16(kVK_ANSI_R),
            keyRepresentation: "R",
            modifiers: [.control, .option]
        )
        let snapshot = ShortcutSnapshot.defaults.replacing(
            .reactivatePrevious,
            with: customReactivation
        )
        try ShortcutValidator.validate(snapshot)
        let reactivationEvent = try makeKeyEvent(
            keyCode: CGKeyCode(kVK_ANSI_R),
            flags: [.maskControl, .maskAlternate]
        )
        let ordinaryPaste = try makeKeyEvent(
            keyCode: CGKeyCode(kVK_ANSI_V),
            flags: .maskCommand
        )

        XCTAssertEqual(
            CGEventTapAdapter.consumedAction(
                type: .keyDown,
                event: reactivationEvent,
                stackSessionIsActive: true,
                reactivationPreviousInterception: { .consumeAndReactivate },
                shortcutSnapshot: snapshot
            ),
            .reactivatePreviousStackItem
        )
        XCTAssertNil(CGEventTapAdapter.consumedAction(
            type: .keyDown,
            event: ordinaryPaste,
            stackSessionIsActive: true,
            stackPasteInterception: { .passThrough },
            shortcutSnapshot: snapshot
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

@MainActor
final class SettingsViewModelTests: XCTestCase {
    func testLaunchAtLoginUsesSystemStatusForEnableDisableAndExternalRefresh() {
        let context = makeViewModel(status: .notRegistered)
        defer { context.cleanup() }

        context.viewModel.setLaunchAtLoginEnabled(true)
        XCTAssertEqual(context.service.registerCount, 1)
        XCTAssertEqual(context.viewModel.launchAtLoginStatus, .enabled)

        context.service.status = .requiresApproval
        context.viewModel.refresh()
        XCTAssertFalse(context.viewModel.launchAtLoginIsEnabled)
        XCTAssertFalse(context.viewModel.launchAtLoginCanToggle)

        context.service.status = .enabled
        context.viewModel.refresh()
        context.viewModel.setLaunchAtLoginEnabled(false)
        XCTAssertEqual(context.service.unregisterCount, 1)
        XCTAssertEqual(context.viewModel.launchAtLoginStatus, .notRegistered)
    }

    func testRequiresApprovalOpensSettingsWithoutRepeatingRegistration() {
        let context = makeViewModel(status: .requiresApproval)
        defer { context.cleanup() }

        context.viewModel.setLaunchAtLoginEnabled(true)
        context.viewModel.openLoginItemsSettings()

        XCTAssertEqual(context.service.registerCount, 0)
        XCTAssertEqual(context.service.openSettingsCount, 1)
        XCTAssertEqual(context.viewModel.launchAtLoginStatus, .requiresApproval)
    }

    func testLaunchAtLoginFailureIsVisibleAndKeepsActualStatus() {
        let context = makeViewModel(status: .notRegistered)
        defer { context.cleanup() }
        context.service.registerError = TestLaunchAtLoginError.denied

        context.viewModel.setLaunchAtLoginEnabled(true)

        XCTAssertEqual(context.viewModel.launchAtLoginStatus, .notRegistered)
        XCTAssertEqual(context.viewModel.launchAtLoginError, "Registration was denied for this test.")
    }

    func testNotFoundAndUnregisterFailureNeverReportFalseSuccess() {
        let context = makeViewModel(status: .enabled)
        defer { context.cleanup() }
        context.service.unregisterError = TestLaunchAtLoginError.denied

        context.viewModel.setLaunchAtLoginEnabled(false)
        XCTAssertEqual(context.viewModel.launchAtLoginStatus, .enabled)
        XCTAssertEqual(context.viewModel.launchAtLoginError, "Registration was denied for this test.")

        context.service.status = .notFound
        context.viewModel.refresh()
        XCTAssertEqual(context.viewModel.launchAtLoginStatus, .notFound)
        XCTAssertFalse(context.viewModel.launchAtLoginCanToggle)
        XCTAssertFalse(context.viewModel.launchAtLoginIsEnabled)
    }

    private func makeViewModel(status: LaunchAtLoginStatus) -> (
        viewModel: SettingsViewModel,
        service: FakeLaunchAtLoginService,
        cleanup: () -> Void
    ) {
        let suiteName = "QipliTests.Settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let service = FakeLaunchAtLoginService(status: status)
        let preferences = ShortcutPreferences(defaults: defaults, storageKey: "shortcuts")
        return (
            SettingsViewModel(
                shortcutPreferences: preferences,
                launchAtLoginService: service
            ),
            service,
            { defaults.removePersistentDomain(forName: suiteName) }
        )
    }
}

@MainActor
final class SettingsWindowControllerTests: XCTestCase {
    func testRepeatedShowReusesOneNativeWindowAndRefreshesSystemState() {
        let suiteName = "QipliTests.SettingsWindow.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = ShortcutPreferences(defaults: defaults, storageKey: "shortcuts")
        let launchService = FakeLaunchAtLoginService(status: .notRegistered)
        let viewModel = SettingsViewModel(
            shortcutPreferences: preferences,
            launchAtLoginService: launchService
        )
        let permissionService = AccessibilityPermissionService(trustChecker: { true })
        let activator = FakeSettingsApplicationActivator()
        var refreshCount = 0
        let controller = SettingsWindowController(
            viewModel: viewModel,
            permissionService: permissionService,
            applicationActivator: activator,
            requestAccessibilityAccess: {},
            openAccessibilitySettings: {},
            refreshSystemState: {
                refreshCount += 1
                return .ready
            }
        )
        defer { controller.close() }

        controller.show()
        let firstWindow = controller.managedWindow
        viewModel.select(.shortcuts)
        controller.show(section: .general)

        XCTAssertTrue(firstWindow === controller.managedWindow)
        XCTAssertEqual(controller.windowCreationCount, 1)
        XCTAssertEqual(refreshCount, 2)
        XCTAssertEqual(activator.userInitiatedActivationCount, 2)
        XCTAssertEqual(viewModel.inputStatus, .ready)
        XCTAssertEqual(viewModel.selectedSection, .general)
    }
}

private final class FakeLaunchAtLoginService: LaunchAtLoginServicing {
    var status: LaunchAtLoginStatus
    var registerError: Error?
    var unregisterError: Error?
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    private(set) var openSettingsCount = 0

    init(status: LaunchAtLoginStatus) {
        self.status = status
    }

    func register() throws {
        registerCount += 1
        if let registerError { throw registerError }
        status = .enabled
    }

    func unregister() throws {
        unregisterCount += 1
        if let unregisterError { throw unregisterError }
        status = .notRegistered
    }

    func openSystemSettings() {
        openSettingsCount += 1
    }
}

private enum TestLaunchAtLoginError: LocalizedError {
    case denied

    var errorDescription: String? {
        "Registration was denied for this test."
    }
}

@MainActor
private final class FakeSettingsApplicationActivator: QipliApplicationActivating {
    var isActive = true
    private(set) var activationCount = 0
    private(set) var userInitiatedActivationCount = 0

    func requestActivation() {
        activationCount += 1
    }

    func requestUserInitiatedActivation() {
        userInitiatedActivationCount += 1
    }
}
