import XCTest
@testable import Qipli

final class OnboardingCompletionStoreTests: XCTestCase {
    func testFreshProfileIsPendingAndCompletionPersists() {
        let suiteName = "QipliTests.OnboardingCompletion.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let storageKey = "onboarding"

        let store = OnboardingCompletionStore(defaults: defaults, storageKey: storageKey)
        XCTAssertFalse(store.isCompleted)

        store.markCompleted()

        XCTAssertTrue(OnboardingCompletionStore(defaults: defaults, storageKey: storageKey).isCompleted)
    }
}

@MainActor
final class OnboardingCoordinatorTests: XCTestCase {
    func testFreshProfileWaitsForDismissalThenStartsServicesExactlyOnce() {
        let store = FakeOnboardingCompletionStore(isCompleted: false)
        var starts = 0
        var presentations: [OnboardingPresentationMode] = []
        let coordinator = OnboardingCoordinator(completionStore: store) { starts += 1 }

        coordinator.start { presentations.append($0) }

        XCTAssertEqual(presentations, [.firstRun])
        XCTAssertEqual(starts, 0)
        XCTAssertEqual(store.markCount, 0)

        coordinator.completeFirstRun()
        coordinator.completeFirstRun()
        coordinator.start { presentations.append($0) }

        XCTAssertTrue(store.isCompleted)
        XCTAssertEqual(store.markCount, 1)
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(presentations, [.firstRun])
    }

    func testCompletedProfileStartsWithoutPresentingOnboarding() {
        let store = FakeOnboardingCompletionStore(isCompleted: true)
        var starts = 0
        var presentations: [OnboardingPresentationMode] = []
        let coordinator = OnboardingCoordinator(completionStore: store) { starts += 1 }

        coordinator.start { presentations.append($0) }
        coordinator.start { presentations.append($0) }

        XCTAssertEqual(starts, 1)
        XCTAssertTrue(presentations.isEmpty)
        XCTAssertEqual(store.markCount, 0)
    }

    func testInterruptedFirstRunRemainsPendingAndReappearsOnNextLaunch() {
        let store = FakeOnboardingCompletionStore(isCompleted: false)
        var firstLaunchStarts = 0
        let firstCoordinator = OnboardingCoordinator(completionStore: store) {
            firstLaunchStarts += 1
        }
        var firstPresentations: [OnboardingPresentationMode] = []
        firstCoordinator.start { firstPresentations.append($0) }

        var nextLaunchStarts = 0
        let nextCoordinator = OnboardingCoordinator(completionStore: store) {
            nextLaunchStarts += 1
        }
        var nextPresentations: [OnboardingPresentationMode] = []
        nextCoordinator.start { nextPresentations.append($0) }

        XCTAssertEqual(firstPresentations, [.firstRun])
        XCTAssertEqual(nextPresentations, [.firstRun])
        XCTAssertEqual(firstLaunchStarts, 0)
        XCTAssertEqual(nextLaunchStarts, 0)
        XCTAssertFalse(store.isCompleted)
    }

    func testManualReopenDoesNotChangeCompletionOrRestartServices() {
        let store = FakeOnboardingCompletionStore(isCompleted: true)
        var starts = 0
        let coordinator = OnboardingCoordinator(completionStore: store) { starts += 1 }
        coordinator.start { _ in XCTFail("Completed profile should not present automatically.") }
        var presentations: [OnboardingPresentationMode] = []

        coordinator.showAgain { presentations.append($0) }

        XCTAssertEqual(presentations, [.reopened])
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(store.markCount, 0)
    }
}

@MainActor
final class OnboardingViewModelTests: XCTestCase {
    func testNavigationIsBoundedAndResetsWhenReopened() {
        let viewModel = OnboardingViewModel()

        viewModel.goBack()
        XCTAssertEqual(viewModel.step, .welcome)
        XCTAssertEqual(viewModel.navigationDirection, .forward)
        viewModel.continueForward()
        XCTAssertEqual(viewModel.navigationDirection, .forward)
        viewModel.continueForward()
        viewModel.continueForward()
        viewModel.continueForward()
        XCTAssertEqual(viewModel.step, .shortcuts)

        viewModel.goBack()
        XCTAssertEqual(viewModel.step, .launchAtLogin)
        XCTAssertEqual(viewModel.navigationDirection, .backward)

        viewModel.begin(mode: .reopened)

        XCTAssertEqual(viewModel.step, .welcome)
        XCTAssertEqual(viewModel.mode, .reopened)
        XCTAssertEqual(viewModel.navigationDirection, .forward)
    }
}

@MainActor
final class OnboardingWindowControllerTests: XCTestCase {
    func testRepeatedShowReusesWindowAndPerformsNoImplicitSystemActions() {
        let context = makeController()
        defer { context.cleanup() }

        context.controller.show(mode: .firstRun)
        let firstWindow = context.controller.managedWindow
        context.controller.show(mode: .firstRun)

        XCTAssertTrue(firstWindow === context.controller.managedWindow)
        XCTAssertEqual(context.controller.windowCreationCount, 1)
        XCTAssertEqual(context.activator.userInitiatedActivationCount, 2)
        XCTAssertEqual(context.launchService.registerCount, 0)
        XCTAssertEqual(context.requestAccessCount(), 0)
        XCTAssertEqual(context.completionCount(), 0)
    }

    func testWindowUsesOpaqueEdgeToEdgePresentationWithoutRemovingNativeControls() {
        let context = makeController()
        defer { context.cleanup() }

        context.controller.show(mode: .firstRun)

        let window = context.controller.managedWindow
        XCTAssertEqual(window?.contentLayoutRect.size.width ?? 0, 820, accuracy: 1)
        XCTAssertGreaterThanOrEqual(window?.contentLayoutRect.size.height ?? 0, 530)
        XCTAssertTrue(window?.styleMask.contains(.fullSizeContentView) == true)
        XCTAssertTrue(window?.styleMask.contains(.closable) == true)
        XCTAssertEqual(window?.titleVisibility, .hidden)
        XCTAssertTrue(window?.titlebarAppearsTransparent == true)
        XCTAssertEqual(window?.titlebarSeparatorStyle, NSTitlebarSeparatorStyle.none)
        XCTAssertTrue(window?.isOpaque == true)
        XCTAssertNotEqual(window?.backgroundColor, .clear)
    }

    func testFirstRunSkipAndFinishCallbacksAreIdempotent() {
        let skipContext = makeController()
        skipContext.controller.show(mode: .firstRun)

        skipContext.controller.skip()
        skipContext.controller.skip()

        XCTAssertNil(skipContext.controller.managedWindow)
        XCTAssertEqual(skipContext.completionCount(), 1)
        skipContext.cleanup()

        let finishContext = makeController()
        finishContext.controller.show(mode: .firstRun)

        finishContext.controller.finish()
        finishContext.controller.finish()

        XCTAssertNil(finishContext.controller.managedWindow)
        XCTAssertEqual(finishContext.completionCount(), 1)
        finishContext.cleanup()
    }

    func testFirstRunWindowCloseCompletesButTerminationCloseDoesNot() {
        let userClose = makeController()
        userClose.controller.show(mode: .firstRun)
        userClose.controller.managedWindow?.close()
        XCTAssertEqual(userClose.completionCount(), 1)
        userClose.cleanup()

        let termination = makeController()
        termination.controller.show(mode: .firstRun)
        termination.controller.closeWithoutCompleting()
        XCTAssertEqual(termination.completionCount(), 0)
        termination.cleanup()
    }

    func testReopenedFinishDoesNotChangeCompletionBoundary() {
        let context = makeController()
        defer { context.cleanup() }
        context.controller.show(mode: .reopened)

        context.controller.finish()

        XCTAssertNil(context.controller.managedWindow)
        XCTAssertEqual(context.completionCount(), 0)
        XCTAssertEqual(context.launchService.registerCount, 0)
        XCTAssertEqual(context.requestAccessCount(), 0)
    }

    private func makeController() -> (
        controller: OnboardingWindowController,
        launchService: OnboardingFakeLaunchAtLoginService,
        activator: OnboardingFakeApplicationActivator,
        requestAccessCount: () -> Int,
        completionCount: () -> Int,
        cleanup: () -> Void
    ) {
        let suiteName = "QipliTests.OnboardingWindow.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = ShortcutPreferences(defaults: defaults, storageKey: "shortcuts")
        let launchService = OnboardingFakeLaunchAtLoginService()
        let settingsViewModel = SettingsViewModel(
            shortcutPreferences: preferences,
            launchAtLoginService: launchService
        )
        let permissionService = AccessibilityPermissionService(trustChecker: { false })
        let activator = OnboardingFakeApplicationActivator()
        final class Counters {
            var requestAccess = 0
            var completion = 0
        }
        let counters = Counters()
        let controller = OnboardingWindowController(
            settingsViewModel: settingsViewModel,
            permissionService: permissionService,
            applicationActivator: activator,
            requestAccessibilityAccess: { counters.requestAccess += 1 },
            openAccessibilitySettings: {},
            completeFirstRun: { counters.completion += 1 }
        )
        return (
            controller,
            launchService,
            activator,
            { counters.requestAccess },
            { counters.completion },
            {
                controller.closeWithoutCompleting()
                defaults.removePersistentDomain(forName: suiteName)
            }
        )
    }
}

private final class FakeOnboardingCompletionStore: OnboardingCompletionStoring {
    private(set) var isCompleted: Bool
    private(set) var markCount = 0

    init(isCompleted: Bool) {
        self.isCompleted = isCompleted
    }

    func markCompleted() {
        markCount += 1
        isCompleted = true
    }
}

private final class OnboardingFakeLaunchAtLoginService: LaunchAtLoginServicing {
    var status: LaunchAtLoginStatus = .notRegistered
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0

    func register() throws {
        registerCount += 1
        status = .enabled
    }

    func unregister() throws {
        unregisterCount += 1
        status = .notRegistered
    }

    func openSystemSettings() {}
}

@MainActor
private final class OnboardingFakeApplicationActivator: QipliApplicationActivating {
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
