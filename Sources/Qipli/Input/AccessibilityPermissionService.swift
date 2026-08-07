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
            "Allow Accessibility access to use Qipli’s global shortcuts and send paste commands to the app you were using."
        case .denied:
            "Accessibility access is currently off. Qipli cannot use global shortcuts or send a paste command until you enable it."
        case .granted:
            "Accessibility access is enabled. Qipli can listen for its global shortcuts."
        }
    }
}

/// The only production type that calls the Accessibility APIs.
final class AccessibilityPermissionService: ObservableObject, AccessibilityPermissionChecking {
    @Published private(set) var state: AccessibilityPermissionState

    private let trustChecker: () -> Bool
    private let promptRequester: () -> Bool
    private let settingsOpener: () -> Void
    private var hasRequestedAccess = false

    init(
        trustChecker: @escaping () -> Bool = { AXIsProcessTrusted() },
        promptRequester: @escaping () -> Bool = AccessibilityPermissionService.requestSystemPrompt,
        settingsOpener: @escaping () -> Void = AccessibilityPermissionService.openAccessibilityPane
    ) {
        self.trustChecker = trustChecker
        self.promptRequester = promptRequester
        self.settingsOpener = settingsOpener
        state = trustChecker() ? .granted : .notRequested
    }

    @discardableResult
    func refresh() -> AccessibilityPermissionState {
        state = trustChecker() ? .granted : (hasRequestedAccess ? .denied : .notRequested)
        return state
    }

    @discardableResult
    func requestAccess() -> AccessibilityPermissionState {
        hasRequestedAccess = true
        _ = promptRequester()
        return refresh()
    }

    func openSystemSettings() {
        settingsOpener()
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
}
