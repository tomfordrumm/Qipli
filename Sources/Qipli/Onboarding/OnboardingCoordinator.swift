import Combine
import Foundation

enum OnboardingPresentationMode: Equatable {
    case firstRun
    case reopened
}

enum OnboardingStep: Int, CaseIterable, Equatable {
    case welcome
    case accessibility
    case launchAtLogin
    case shortcuts

    var position: Int { rawValue + 1 }

    var previous: Self? {
        Self(rawValue: rawValue - 1)
    }

    var next: Self? {
        Self(rawValue: rawValue + 1)
    }
}

enum OnboardingNavigationDirection: Equatable {
    case forward
    case backward
}

protocol OnboardingCompletionStoring: AnyObject {
    var isCompleted: Bool { get }
    func markCompleted()
}

final class OnboardingCompletionStore: OnboardingCompletionStoring {
    static let defaultStorageKey = "qipli.onboardingCompleted"

    private let defaults: UserDefaults
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = OnboardingCompletionStore.defaultStorageKey
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    var isCompleted: Bool {
        defaults.bool(forKey: storageKey)
    }

    func markCompleted() {
        defaults.set(true, forKey: storageKey)
    }
}

/// Keeps first-run presentation separate from the one-time product-service start.
@MainActor
final class OnboardingCoordinator {
    private let completionStore: OnboardingCompletionStoring
    private let startProductServices: () -> Void
    private(set) var productServicesStarted = false

    init(
        completionStore: OnboardingCompletionStoring = OnboardingCompletionStore(),
        startProductServices: @escaping () -> Void
    ) {
        self.completionStore = completionStore
        self.startProductServices = startProductServices
    }

    func start(showOnboarding: (OnboardingPresentationMode) -> Void) {
        guard !productServicesStarted else { return }
        if completionStore.isCompleted {
            startProductServicesOnce()
        } else {
            showOnboarding(.firstRun)
        }
    }

    func completeFirstRun() {
        guard !productServicesStarted else { return }
        completionStore.markCompleted()
        startProductServicesOnce()
    }

    func showAgain(showOnboarding: (OnboardingPresentationMode) -> Void) {
        showOnboarding(.reopened)
    }

    private func startProductServicesOnce() {
        guard !productServicesStarted else { return }
        productServicesStarted = true
        startProductServices()
    }
}

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published private(set) var step: OnboardingStep = .welcome
    @Published private(set) var mode: OnboardingPresentationMode = .firstRun
    @Published private(set) var navigationDirection: OnboardingNavigationDirection = .forward

    func begin(mode: OnboardingPresentationMode) {
        self.mode = mode
        navigationDirection = .forward
        step = .welcome
    }

    func goBack() {
        guard let previous = step.previous else { return }
        navigationDirection = .backward
        step = previous
    }

    func continueForward() {
        guard let next = step.next else { return }
        navigationDirection = .forward
        step = next
    }
}
