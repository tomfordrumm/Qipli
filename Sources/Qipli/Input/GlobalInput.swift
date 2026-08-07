import Foundation

enum GlobalHotKey: Equatable {
    case history
    case pasteStack
}

enum GlobalInputStatus: Equatable {
    case stopped
    case ready
    case permissionRequired
    case unavailable(String)

    var userDescription: String {
        switch self {
        case .stopped:
            "Global input is stopped."
        case .ready:
            "Global input is ready."
        case .permissionRequired:
            "Accessibility access is required for global shortcuts."
        case let .unavailable(message):
            message
        }
    }
}

protocol AccessibilityPermissionChecking: AnyObject {
    var state: AccessibilityPermissionState { get }
    @discardableResult func refresh() -> AccessibilityPermissionState
    @discardableResult func requestAccess() -> AccessibilityPermissionState
    func openSystemSettings()
}

protocol GlobalInputEventAdapting: AnyObject {
    var status: GlobalInputStatus { get }
    var onHotKey: ((GlobalHotKey) -> Void)? { get set }
    var onStatusChange: ((GlobalInputStatus) -> Void)? { get set }

    @discardableResult func start() -> GlobalInputStatus
    func stop()
}

/// Coordinates permission with global input without depending on AppKit or Core Graphics.
final class InputCoordinator {
    private let permissionService: AccessibilityPermissionChecking
    private let eventAdapter: GlobalInputEventAdapting

    private(set) var status: GlobalInputStatus = .stopped {
        didSet { onStatusChange?(status) }
    }
    var onHotKey: ((GlobalHotKey) -> Void)?
    var onStatusChange: ((GlobalInputStatus) -> Void)?

    init(permissionService: AccessibilityPermissionChecking, eventAdapter: GlobalInputEventAdapting) {
        self.permissionService = permissionService
        self.eventAdapter = eventAdapter

        eventAdapter.onHotKey = { [weak self] hotKey in
            self?.onHotKey?(hotKey)
        }
        eventAdapter.onStatusChange = { [weak self] status in
            self?.status = status
        }
    }

    @discardableResult
    func refreshAndStart() -> GlobalInputStatus {
        guard permissionService.refresh() == .granted else {
            eventAdapter.stop()
            status = .permissionRequired
            return status
        }

        if case .unavailable = status {
            eventAdapter.stop()
        }
        status = eventAdapter.start()
        return status
    }

    func stop() {
        eventAdapter.stop()
        status = .stopped
    }
}
