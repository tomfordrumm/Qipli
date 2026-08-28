import AppKit
import ApplicationServices
import Combine

enum AccessibilityPermissionState: Equatable {
    case notRequested
    case denied
    case granted

    var menuDescription: String {
        switch self {
        case .notRequested:
            "Accessibility access needed"
        case .denied:
            "Accessibility access denied"
        case .granted:
            "Global input ready"
        }
    }

    var explanation: String {
        switch self {
        case .notRequested:
            "Enable Accessibility in System Settings to use global shortcuts and paste from Qipli."
        case .denied:
            "Accessibility access is currently off. Qipli cannot use global shortcuts or send a paste command until you enable it."
        case .granted:
            "Qipli can now use global shortcuts and paste into other apps."
        }
    }
}

/// The only production type that calls the Accessibility APIs.
final class AccessibilityPermissionService: ObservableObject, AccessibilityPermissionChecking {
    @Published private(set) var state: AccessibilityPermissionState

    private let trustChecker: () -> Bool
    private let promptRequester: () -> Bool
    private let settingsOpener: () -> Void
    private let monitoringScheduler: (TimeInterval, @escaping () -> Void) -> () -> Void
    private let monitoringInterval: TimeInterval
    private let monitoringPollLimit: Int
    private var hasRequestedAccess: Bool
    private var cancelMonitoring: (() -> Void)?

    init(
        trustChecker: @escaping () -> Bool = { AXIsProcessTrusted() },
        promptRequester: @escaping () -> Bool = AccessibilityPermissionService.requestSystemPrompt,
        settingsOpener: @escaping () -> Void = AccessibilityPermissionService.openAccessibilityPane,
        monitoringInterval: TimeInterval = 0.5,
        monitoringPollLimit: Int = 600,
        monitoringScheduler: @escaping (TimeInterval, @escaping () -> Void) -> () -> Void = AccessibilityPermissionService.scheduleRepeating
    ) {
        self.trustChecker = trustChecker
        self.promptRequester = promptRequester
        self.settingsOpener = settingsOpener
        self.monitoringInterval = monitoringInterval
        self.monitoringPollLimit = monitoringPollLimit
        self.monitoringScheduler = monitoringScheduler

        let isTrusted = trustChecker()
        state = isTrusted ? .granted : .notRequested
        hasRequestedAccess = isTrusted
    }

    deinit {
        cancelMonitoring?()
    }

    @discardableResult
    func refresh() -> AccessibilityPermissionState {
        let refreshedState: AccessibilityPermissionState = trustChecker()
            ? .granted
            : (hasRequestedAccess ? .denied : .notRequested)
        if refreshedState != state {
            state = refreshedState
        }
        return refreshedState
    }

    @discardableResult
    func requestAccess() -> AccessibilityPermissionState {
        hasRequestedAccess = true
        _ = promptRequester()
        let refreshedState = refresh()
        if refreshedState != .granted {
            monitorSystemSettingsChanges()
        }
        return refreshedState
    }

    func openSystemSettings() {
        hasRequestedAccess = true
        monitorSystemSettingsChanges()
        settingsOpener()
    }

    func stopMonitoringSystemSettingsChanges() {
        cancelMonitoring?()
        cancelMonitoring = nil
    }

    private func monitorSystemSettingsChanges() {
        stopMonitoringSystemSettingsChanges()
        let baselineState = refresh()
        var remainingPolls = monitoringPollLimit

        cancelMonitoring = monitoringScheduler(monitoringInterval) { [weak self] in
            guard let self else { return }
            remainingPolls -= 1
            let refreshedState = self.refresh()
            if refreshedState != baselineState || remainingPolls <= 0 {
                self.stopMonitoringSystemSettingsChanges()
            }
        }
    }

    private static func requestSystemPrompt() -> Bool {
        // This is the documented value of kAXTrustedCheckOptionPrompt. Keeping a Swift-owned
        // key avoids importing the C global as shared mutable state under Swift 6 checks.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private static func openAccessibilityPane() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private static func scheduleRepeating(
        interval: TimeInterval,
        action: @escaping () -> Void
    ) -> () -> Void {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in action() }
        RunLoop.main.add(timer, forMode: .common)
        return { timer.invalidate() }
    }
}
