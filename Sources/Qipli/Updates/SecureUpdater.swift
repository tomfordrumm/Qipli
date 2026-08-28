import Foundation
import Sparkle

struct SecureUpdaterSnapshot: Equatable {
    let canCheckForUpdates: Bool
    let automaticallyChecksForUpdates: Bool
}

@MainActor
protocol SecureUpdaterServicing: AnyObject {
    var snapshot: SecureUpdaterSnapshot { get }
    var onStateChange: ((SecureUpdaterSnapshot) -> Void)? { get set }

    func start()
    func stop()
    func checkForUpdates()
    func setAutomaticallyChecksForUpdates(_ isEnabled: Bool)
}

@MainActor
final class SparkleSecureUpdater: SecureUpdaterServicing {
    private let controller: SPUStandardUpdaterController
    private var canCheckObservation: NSKeyValueObservation?
    private var started = false

    var onStateChange: ((SecureUpdaterSnapshot) -> Void)?

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    init(controller: SPUStandardUpdaterController) {
        self.controller = controller
    }

    var snapshot: SecureUpdaterSnapshot {
        SecureUpdaterSnapshot(
            canCheckForUpdates: started && controller.updater.canCheckForUpdates,
            automaticallyChecksForUpdates: controller.updater.automaticallyChecksForUpdates
        )
    }

    func start() {
        guard !started else { return }
        started = true
        controller.startUpdater()
        canCheckObservation = controller.updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.publishSnapshot()
            }
        }
        publishSnapshot()
    }

    func stop() {
        canCheckObservation?.invalidate()
        canCheckObservation = nil
        started = false
        publishSnapshot()
    }

    func checkForUpdates() {
        guard snapshot.canCheckForUpdates else { return }
        controller.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ isEnabled: Bool) {
        guard controller.updater.automaticallyChecksForUpdates != isEnabled else { return }
        controller.updater.automaticallyChecksForUpdates = isEnabled
        publishSnapshot()
    }

    private func publishSnapshot() {
        onStateChange?(snapshot)
    }
}

@MainActor
final class UnavailableSecureUpdater: SecureUpdaterServicing {
    var snapshot = SecureUpdaterSnapshot(
        canCheckForUpdates: false,
        automaticallyChecksForUpdates: false
    )
    var onStateChange: ((SecureUpdaterSnapshot) -> Void)?

    func start() {}
    func stop() {}
    func checkForUpdates() {}
    func setAutomaticallyChecksForUpdates(_ isEnabled: Bool) {}
}
