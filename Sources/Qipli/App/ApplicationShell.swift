import AppKit

/// Owns AppKit lifecycle concerns. Product rules remain in the injected services.
final class ApplicationShell: NSObject {
    private let permissionService: AccessibilityPermissionService
    private let inputCoordinator: InputCoordinator
    private let panels: PanelController
    private let statusItem: NSStatusItem
    private let permissionMenuItem = NSMenuItem()

    init(
        permissionService: AccessibilityPermissionService = AccessibilityPermissionService(),
        inputAdapter: GlobalInputEventAdapting = CGEventTapAdapter()
    ) {
        self.permissionService = permissionService
        inputCoordinator = InputCoordinator(
            permissionService: permissionService,
            eventAdapter: inputAdapter
        )
        panels = PanelController(permissionService: permissionService)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        inputCoordinator.onStatusChange = { [weak self] _ in
            self?.updatePermissionMenuTitle()
        }
        inputCoordinator.onHotKey = { [weak self] hotKey in
            switch hotKey {
            case .history:
                self?.showHistory()
            case .pasteStack:
                self?.showPasteStack()
            }
        }
    }

    func start() {
        configureStatusItem()
        refreshInputAvailability()
    }

    func stop() {
        inputCoordinator.stop()
        panels.closeAll()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func configureStatusItem() {
        statusItem.button?.image = NSImage(
            systemSymbolName: "clipboard",
            accessibilityDescription: "Qipli"
        )

        let menu = NSMenu()
        menu.addItem(menuItem(title: "History", action: #selector(showHistory)))
        menu.addItem(menuItem(title: "Start Paste Stack", action: #selector(showPasteStack)))
        menu.addItem(.separator())

        permissionMenuItem.target = self
        permissionMenuItem.action = #selector(showPermissionStatus)
        menu.addItem(permissionMenuItem)

        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Quit Qipli", action: #selector(quit)))
        statusItem.menu = menu
    }

    private func menuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func refreshInputAvailability() {
        inputCoordinator.refreshAndStart()
        updatePermissionMenuTitle()
    }

    private func updatePermissionMenuTitle() {
        switch inputCoordinator.status {
        case .unavailable:
            permissionMenuItem.title = "Permission: Global input unavailable"
        case .ready:
            permissionMenuItem.title = "Permission: Global input ready"
        case .permissionRequired, .stopped:
            permissionMenuItem.title = "Permission: \(permissionService.state.menuDescription)"
        }
    }

    @objc private func showHistory() {
        panels.showHistory()
    }

    @objc private func showPasteStack() {
        guard permissionService.refresh() == .granted else {
            showPermissionStatus()
            return
        }
        panels.showPasteStack()
    }

    @objc private func showPermissionStatus() {
        permissionService.refresh()
        refreshInputAvailability()
        panels.showPermission(
            requestAccess: { [weak self] in self?.requestAccessibilityAccess() },
            openSettings: { [weak self] in self?.openAccessibilitySettings() }
        )
    }

    private func requestAccessibilityAccess() {
        permissionService.requestAccess()
        refreshInputAvailability()
    }

    private func openAccessibilitySettings() {
        permissionService.openSystemSettings()
    }

    @objc private func quit() {
        stop()
        NSApp.terminate(nil)
    }
}
