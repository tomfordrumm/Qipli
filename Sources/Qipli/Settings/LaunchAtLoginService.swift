import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

protocol LaunchAtLoginServicing: AnyObject {
    var status: LaunchAtLoginStatus { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

final class SystemLaunchAtLoginService: LaunchAtLoginServicing {
    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
    }

    var status: LaunchAtLoginStatus {
        switch service.status {
        case .notRegistered:
            .notRegistered
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .notFound
        @unknown default:
            .notFound
        }
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
