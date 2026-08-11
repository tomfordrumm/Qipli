import AppKit
import Combine

/// Owns AppKit lifecycle concerns. Product rules remain in the injected services.
@MainActor
final class ApplicationShell: NSObject {
    private let permissionService: AccessibilityPermissionService
    private let inputCoordinator: InputCoordinator
    private let panels: PanelController
    private let historyViewModel: HistoryViewModel
    private let stackSessionController: StackSessionController
    private let stackCaptureCoordinator: StackCollectionCaptureCoordinator
    private let stackCollectionStarter: StackCollectionStarter
    private let stackSequentialPasteExecutor: StackSequentialPasteExecutor
    private let pasteboardMonitor: PasteboardMonitor
    private var retentionTimer: Timer?
    private var permissionStateObservation: AnyCancellable?
    private let statusItem: NSStatusItem
    private let permissionMenuItem = NSMenuItem()
    private let pasteStackMenuItem = NSMenuItem()

    init(
        permissionService: AccessibilityPermissionService = AccessibilityPermissionService(),
        inputAdapter: GlobalInputEventAdapting = CGEventTapAdapter(),
        historyStore: HistoryStoring? = nil,
        pasteCommandDispatcher: TaggedPasteCommandDispatching? = nil,
        copyCommandDispatcher: TaggedCopyCommandDispatching? = nil
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
        stackSessionController = StackSessionController()
        stackCaptureCoordinator = StackCollectionCaptureCoordinator(
            historyViewModel: historyViewModel,
            stackSessionController: stackSessionController
        )
        let monitor = PasteboardMonitor { [weak stackCaptureCoordinator, weak stackSessionController] change in
            // The monitor observes the active session before it defers the
            // persistence work. A later Start/Cancel cannot claim this copy;
            // the session watermark also rejects a write that predates Start.
            let captureContext = stackSessionController?.captureContext
            Task { @MainActor in
                stackCaptureCoordinator?.recordExternalText(
                    change.text,
                    observedChangeCount: change.changeCount,
                    stackCaptureContext: captureContext
                )
            }
        }
        pasteboardMonitor = monitor
        inputCoordinator = InputCoordinator(
            permissionService: permissionService,
            eventAdapter: inputAdapter
        )
        let commandDispatcher = pasteCommandDispatcher
            ?? (inputAdapter as? TaggedPasteCommandDispatching)
            ?? UnavailablePasteCommandDispatcher()
        let pasteExecutor = HistoryPasteExecutor(
            permissionService: permissionService,
            pasteboardWriter: SystemHistoryPasteboardWriter(),
            registerSelfWrite: { [weak pasteboardMonitor] changeCount in
                pasteboardMonitor?.registerSelfWrite(changeCount: changeCount)
            },
            commandDispatcher: commandDispatcher
        )
        let panelController = PanelController(
            permissionService: permissionService,
            historyViewModel: historyViewModel,
            stackSessionController: stackSessionController,
            historyPasteExecutor: pasteExecutor,
            openAccessibilitySettings: { [weak permissionService] in
                permissionService?.openSystemSettings()
            }
        )
        panels = panelController
        stackSequentialPasteExecutor = StackSequentialPasteExecutor(
            permissionService: permissionService,
            pasteboardWriter: SystemHistoryPasteboardWriter(),
            registerSelfWrite: { [weak pasteboardMonitor] changeCount in
                pasteboardMonitor?.registerSelfWrite(changeCount: changeCount)
            },
            commandDispatcher: commandDispatcher,
            sessionController: stackSessionController,
            finishPresentation: { panelController.finishPasteStackAfterCompletion() }
        )
        let resolvedCopyCommandDispatcher = copyCommandDispatcher
            ?? (inputAdapter as? TaggedCopyCommandDispatching)
            ?? UnavailableCopyCommandDispatcher()
        stackCollectionStarter = StackCollectionStarter(
            sessionController: stackSessionController,
            currentPasteboardChangeCount: { monitor.currentChangeCount },
            showStackPanel: { panelController.showPasteStack() },
            copyCommandDispatcher: resolvedCopyCommandDispatcher
        )
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        inputCoordinator.onStatusChange = { [weak self] status in
            guard let self else { return }
            self.updatePermissionMenuTitle()
            switch status {
            case .permissionRequired, .unavailable:
                self.stackSessionController.recordInputUnavailable()
            case .stopped, .ready:
                break
            }
        }
        inputCoordinator.onHotKey = { [weak self] hotKey in
            switch hotKey {
            case .history:
                self?.showHistory()
            case .pasteStack:
                self?.startPasteStackFromHotKey()
            }
        }
        inputCoordinator.shouldConsumeEscape = { [weak stackSessionController] in
            stackSessionController?.isActive ?? false
        }
        inputCoordinator.stackPasteInterception = { [weak stackSessionController] in
            stackSessionController?.acceptNextPasteInput() ?? .passThrough
        }
        inputCoordinator.reactivationPreviousInterception = { [weak stackSessionController] in
            stackSessionController?.acceptReactivatePreviousInput() ?? .passThrough
        }
        inputCoordinator.onStackPaste = { [weak stackSequentialPasteExecutor] in
            stackSequentialPasteExecutor?.executeReservedPaste()
        }
        inputCoordinator.onReactivatePrevious = { [weak stackSessionController] in
            // The event tap already made the UUID-only decision. Publish on the
            // shared common-mode boundary so a SwiftUI List is never mutated
            // during input handling or another view-update transaction.
            PasteStackPanelIntentScheduler.schedule {
                stackSessionController?.publishAcceptedReactivatePreviousState()
            }
        }
        inputCoordinator.onEscape = { [weak self] in
            self?.cancelPasteStack()
        }
        panels.onPasteStackCancelled = { [weak self] in
            self?.updatePasteStackMenuTitle()
        }
    }

    func start() {
        configureStatusItem()
        observePermissionChanges()
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
        permissionService.stopMonitoringSystemSettingsChanges()
        permissionStateObservation?.cancel()
        permissionStateObservation = nil
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
        pasteStackMenuItem.target = self
        pasteStackMenuItem.action = #selector(togglePasteStackFromMenu)
        menu.addItem(pasteStackMenuItem)
        menu.addItem(.separator())

        permissionMenuItem.target = self
        permissionMenuItem.action = #selector(showPermissionStatus)
        menu.addItem(permissionMenuItem)

        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Quit Qipli", action: #selector(quit)))
        statusItem.menu = menu
        updatePasteStackMenuTitle()
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

    func refreshSystemPermissions() {
        refreshInputAvailability()
    }

    private func observePermissionChanges() {
        guard permissionStateObservation == nil else { return }
        permissionStateObservation = permissionService.$state
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                // @Published delivers during willSet. Defer the trust recheck until the
                // new state is stored so refresh() cannot recursively publish it again.
                Task { @MainActor [weak self] in
                    self?.refreshInputAvailability()
                }
            }
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

    private func updatePasteStackMenuTitle() {
        pasteStackMenuItem.title = stackSessionController.isActive ? "Cancel Paste Stack" : "Start Paste Stack"
    }

    @objc private func showHistory() {
        panels.showHistory()
    }

    @objc private func togglePasteStackFromMenu() {
        if stackSessionController.isActive {
            cancelPasteStack()
        } else {
            startPasteStackFromMenu()
        }
    }

    private func startPasteStackFromHotKey() {
        guard permissionService.refresh() == .granted else {
            showPermissionStatus()
            return
        }
        refreshInputAvailability()
        guard inputCoordinator.status == .ready else {
            showPermissionStatus()
            return
        }
        stackCollectionStarter.startFromHotKey()
        updatePasteStackMenuTitle()
    }

    private func startPasteStackFromMenu() {
        guard permissionService.refresh() == .granted else {
            showPermissionStatus()
            return
        }
        refreshInputAvailability()
        guard inputCoordinator.status == .ready else {
            showPermissionStatus()
            return
        }
        stackCollectionStarter.startFromMenu()
        updatePasteStackMenuTitle()
    }

    private func cancelPasteStack() {
        panels.cancelPasteStack()
        updatePasteStackMenuTitle()
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

private final class UnavailablePasteCommandDispatcher: TaggedPasteCommandDispatching {
    func postTaggedCommandV() -> Bool { false }
}

private final class UnavailableCopyCommandDispatcher: TaggedCopyCommandDispatching {
    func postTaggedCommandC() -> Bool { false }
}
