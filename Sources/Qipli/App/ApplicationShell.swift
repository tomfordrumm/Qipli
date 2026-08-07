import AppKit

/// Owns AppKit lifecycle concerns. Product rules remain in the injected services.
@MainActor
final class ApplicationShell: NSObject {
    private let permissionService: AccessibilityPermissionService
    private let inputCoordinator: InputCoordinator
    private let panels: PanelController
    private let historyViewModel: HistoryViewModel
    private let pasteboardMonitor: PasteboardMonitor
    private var retentionTimer: Timer?
    private let statusItem: NSStatusItem
    private let permissionMenuItem = NSMenuItem()

    init(
        permissionService: AccessibilityPermissionService = AccessibilityPermissionService(),
        inputAdapter: GlobalInputEventAdapting = CGEventTapAdapter(),
        historyStore: HistoryStoring? = nil
    ) {
        self.permissionService = permissionService
        let store: HistoryStoring
        if let historyStore {
            store = historyStore
        } else {
            store = RetryingHistoryStore { try CoreDataHistoryStore() }
        }
        let historyService = HistoryService(store: store)
        historyViewModel = HistoryViewModel(service: historyService)
        pasteboardMonitor = PasteboardMonitor { [weak historyViewModel] text in
            Task { @MainActor in
                historyViewModel?.recordExternalText(text)
            }
        }
        inputCoordinator = InputCoordinator(
            permissionService: permissionService,
            eventAdapter: inputAdapter
        )
        panels = PanelController(permissionService: permissionService, historyViewModel: historyViewModel)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
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
        historyViewModel.reload()
        pasteboardMonitor.start()
        retentionTimer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.historyViewModel.reload()
            }
        }
    }

    func stop() {
        inputCoordinator.stop()
        pasteboardMonitor.stop()
        retentionTimer?.invalidate()
        retentionTimer = nil
        panels.closeAll()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func configureStatusItem() {
        statusItem.length = NSStatusItem.squareLength
        statusItem.isVisible = true

        if let button = statusItem.button {
            button.toolTip = "Qipli"
            if let image = NSImage(
                systemSymbolName: "clipboard",
                accessibilityDescription: "Qipli"
            ) {
                image.isTemplate = true
                button.image = image
                button.imagePosition = .imageOnly
            } else {
                button.image = nil
                button.title = "Q"
                button.font = .systemFont(ofSize: 13, weight: .semibold)
            }
        }

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
