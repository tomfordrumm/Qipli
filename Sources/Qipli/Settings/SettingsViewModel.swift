import Combine
import Foundation

enum SettingsSection: Hashable {
    case general
    case shortcuts
}

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var selectedSection: SettingsSection = .general
    @Published private(set) var shortcuts: ShortcutSnapshot
    @Published private(set) var recoveredShortcutDefaults: Bool
    @Published private(set) var shortcutError: String?
    @Published private(set) var shortcutErrorCommand: ShortcutCommand?
    @Published private(set) var launchAtLoginStatus: LaunchAtLoginStatus
    @Published private(set) var launchAtLoginError: String?
    @Published private(set) var inputStatus: GlobalInputStatus = .stopped

    private let shortcutPreferences: ShortcutPreferences
    private let launchAtLoginService: LaunchAtLoginServicing
    private var shortcutObservation: AnyCancellable?
    private var recoveryObservation: AnyCancellable?

    init(
        shortcutPreferences: ShortcutPreferences,
        launchAtLoginService: LaunchAtLoginServicing
    ) {
        self.shortcutPreferences = shortcutPreferences
        self.launchAtLoginService = launchAtLoginService
        shortcuts = shortcutPreferences.snapshot
        recoveredShortcutDefaults = shortcutPreferences.recoveredDefaults
        launchAtLoginStatus = launchAtLoginService.status

        shortcutObservation = shortcutPreferences.$snapshot
            .removeDuplicates()
            .sink { [weak self] snapshot in
                self?.shortcuts = snapshot
            }
        recoveryObservation = shortcutPreferences.$recoveredDefaults
            .removeDuplicates()
            .sink { [weak self] recovered in
                self?.recoveredShortcutDefaults = recovered
            }
    }

    var launchAtLoginIsEnabled: Bool {
        launchAtLoginStatus == .enabled
    }

    var launchAtLoginCanToggle: Bool {
        switch launchAtLoginStatus {
        case .notRegistered, .enabled:
            true
        case .requiresApproval, .notFound:
            false
        }
    }

    var launchAtLoginDescription: String {
        switch launchAtLoginStatus {
        case .notRegistered:
            "Qipli will not open automatically when you sign in."
        case .enabled:
            "Qipli will open automatically when you sign in."
        case .requiresApproval:
            "macOS needs your approval in Login Items before Qipli can open at sign-in."
        case .notFound:
            "macOS could not find Qipli's login item registration."
        }
    }

    func refresh(inputStatus: GlobalInputStatus? = nil) {
        launchAtLoginStatus = launchAtLoginService.status
        launchAtLoginError = nil
        if let inputStatus {
            self.inputStatus = inputStatus
        }
    }

    func updateInputStatus(_ inputStatus: GlobalInputStatus) {
        self.inputStatus = inputStatus
    }

    func select(_ section: SettingsSection) {
        selectedSection = section
    }

    func updateShortcut(_ command: ShortcutCommand, binding: ShortcutBinding) {
        do {
            try shortcutPreferences.update(command, binding: binding)
            shortcutError = nil
            shortcutErrorCommand = nil
        } catch {
            shortcutError = (error as? LocalizedError)?.errorDescription ?? "Qipli could not save that shortcut."
            shortcutErrorCommand = command
        }
    }

    func resetShortcuts() {
        shortcutPreferences.resetToDefaults()
        shortcutError = nil
        shortcutErrorCommand = nil
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        guard launchAtLoginCanToggle else { return }
        do {
            if isEnabled {
                try launchAtLoginService.register()
            } else {
                try launchAtLoginService.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        launchAtLoginStatus = launchAtLoginService.status
    }

    func openLoginItemsSettings() {
        launchAtLoginService.openSystemSettings()
    }
}
