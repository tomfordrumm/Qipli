import XCTest
@testable import Qipli

@MainActor
final class SecureUpdaterSettingsTests: XCTestCase {
    func testManualCheckDoesNotEnableAutomaticChecks() {
        let context = makeViewModel(
            snapshot: SecureUpdaterSnapshot(
                canCheckForUpdates: true,
                automaticallyChecksForUpdates: false
            )
        )
        defer { context.cleanup() }

        context.viewModel.checkForUpdates()

        XCTAssertEqual(context.updater.manualCheckCount, 1)
        XCTAssertFalse(context.viewModel.automaticallyChecksForUpdates)
        XCTAssertEqual(context.updater.setAutomaticValues, [])
    }

    func testAutomaticChecksChangeOnlyFromExplicitSettingAction() {
        let context = makeViewModel(
            snapshot: SecureUpdaterSnapshot(
                canCheckForUpdates: true,
                automaticallyChecksForUpdates: false
            )
        )
        defer { context.cleanup() }

        context.viewModel.setAutomaticallyChecksForUpdates(true)
        context.viewModel.setAutomaticallyChecksForUpdates(false)

        XCTAssertEqual(context.updater.setAutomaticValues, [true, false])
        XCTAssertFalse(context.viewModel.automaticallyChecksForUpdates)
        XCTAssertEqual(
            context.viewModel.updateCheckDescription,
            "Qipli checks only when you ask. Installing an update always requires confirmation."
        )
    }

    func testUpdaterStateControlsManualActionAvailability() {
        let context = makeViewModel(
            snapshot: SecureUpdaterSnapshot(
                canCheckForUpdates: false,
                automaticallyChecksForUpdates: false
            )
        )
        defer { context.cleanup() }

        context.viewModel.checkForUpdates()
        XCTAssertEqual(context.updater.manualCheckCount, 0)

        context.updater.publish(
            SecureUpdaterSnapshot(
                canCheckForUpdates: true,
                automaticallyChecksForUpdates: true
            )
        )

        XCTAssertTrue(context.viewModel.canCheckForUpdates)
        XCTAssertTrue(context.viewModel.automaticallyChecksForUpdates)
        XCTAssertEqual(
            context.viewModel.updateCheckDescription,
            "Qipli checks periodically. Installing an update always requires confirmation."
        )

        context.viewModel.checkForUpdates()
        XCTAssertEqual(context.updater.manualCheckCount, 1)
    }

    private func makeViewModel(snapshot: SecureUpdaterSnapshot) -> (
        viewModel: SettingsViewModel,
        updater: FakeSecureUpdater,
        cleanup: () -> Void
    ) {
        let suiteName = "QipliTests.Updates.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let updater = FakeSecureUpdater(snapshot: snapshot)
        let viewModel = SettingsViewModel(
            shortcutPreferences: ShortcutPreferences(defaults: defaults, storageKey: "shortcuts"),
            launchAtLoginService: FakeUpdateLaunchAtLoginService(),
            secureUpdater: updater
        )
        return (
            viewModel,
            updater,
            { defaults.removePersistentDomain(forName: suiteName) }
        )
    }
}

@MainActor
private final class FakeSecureUpdater: SecureUpdaterServicing {
    var snapshot: SecureUpdaterSnapshot
    var onStateChange: ((SecureUpdaterSnapshot) -> Void)?
    private(set) var manualCheckCount = 0
    private(set) var setAutomaticValues: [Bool] = []

    init(snapshot: SecureUpdaterSnapshot) {
        self.snapshot = snapshot
    }

    func start() {}
    func stop() {}

    func checkForUpdates() {
        guard snapshot.canCheckForUpdates else { return }
        manualCheckCount += 1
    }

    func setAutomaticallyChecksForUpdates(_ isEnabled: Bool) {
        setAutomaticValues.append(isEnabled)
        snapshot = SecureUpdaterSnapshot(
            canCheckForUpdates: snapshot.canCheckForUpdates,
            automaticallyChecksForUpdates: isEnabled
        )
        onStateChange?(snapshot)
    }

    func publish(_ snapshot: SecureUpdaterSnapshot) {
        self.snapshot = snapshot
        onStateChange?(snapshot)
    }
}

private final class FakeUpdateLaunchAtLoginService: LaunchAtLoginServicing {
    var status: LaunchAtLoginStatus = .notRegistered
    func register() throws { status = .enabled }
    func unregister() throws { status = .notRegistered }
    func openSystemSettings() {}
}
