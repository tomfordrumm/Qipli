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
    private let shortcutPreferences: ShortcutPreferences
    private let settingsViewModel: SettingsViewModel
    private var settingsWindowController: SettingsWindowController!
    private var onboardingCoordinator: OnboardingCoordinator!
    private var onboardingWindowController: OnboardingWindowController!
    private var retentionTimer: Timer?
    private var permissionStateObservation: AnyCancellable?
    private var statusItem: NSStatusItem?
    private let pasteStackMenuItem = NSMenuItem()

    init(
        permissionService: AccessibilityPermissionService = AccessibilityPermissionService(),
        inputAdapter: GlobalInputEventAdapting? = nil,
        shortcutPreferences: ShortcutPreferences = ShortcutPreferences(),
        launchAtLoginService: LaunchAtLoginServicing = SystemLaunchAtLoginService(),
        onboardingCompletionStore: OnboardingCompletionStoring = OnboardingCompletionStore(),
        historyStore: HistoryStoring? = nil,
        pasteCommandDispatcher: TaggedPasteCommandDispatching? = nil,
        copyCommandDispatcher: TaggedCopyCommandDispatching? = nil
    ) {
        self.permissionService = permissionService
        self.shortcutPreferences = shortcutPreferences
        let resolvedInputAdapter = inputAdapter ?? CGEventTapAdapter(
            shortcutSnapshotProvider: { shortcutPreferences.currentSnapshot }
        )
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
            eventAdapter: resolvedInputAdapter
        )
        let commandDispatcher = pasteCommandDispatcher
            ?? (resolvedInputAdapter as? TaggedPasteCommandDispatching)
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
            ?? (resolvedInputAdapter as? TaggedCopyCommandDispatching)
            ?? UnavailableCopyCommandDispatcher()
        stackCollectionStarter = StackCollectionStarter(
            sessionController: stackSessionController,
            currentPasteboardChangeCount: { monitor.currentChangeCount },
            showStackPanel: { panelController.showPasteStack() },
            copyCommandDispatcher: resolvedCopyCommandDispatcher
        )
        settingsViewModel = SettingsViewModel(
            shortcutPreferences: shortcutPreferences,
            launchAtLoginService: launchAtLoginService
        )
        super.init()

        onboardingCoordinator = OnboardingCoordinator(
            completionStore: onboardingCompletionStore,
            startProductServices: { [weak self] in
                self?.startProductServices()
            }
        )
        onboardingWindowController = OnboardingWindowController(
            settingsViewModel: settingsViewModel,
            permissionService: permissionService,
            requestAccessibilityAccess: { [weak self] in
                self?.requestAccessibilityAccessFromOnboarding()
            },
            openAccessibilitySettings: { [weak self] in
                self?.openAccessibilitySettings()
            },
            completeFirstRun: { [weak self] in
                self?.onboardingCoordinator.completeFirstRun()
            }
        )
        settingsWindowController = SettingsWindowController(
            viewModel: settingsViewModel,
            permissionService: permissionService,
            requestAccessibilityAccess: { [weak self] in
                self?.requestAccessibilityAccess()
                self?.settingsWindowController.refresh()
            },
            openAccessibilitySettings: { [weak self] in
                self?.openAccessibilitySettings()
            },
            refreshSystemState: { [weak self] in
                self?.refreshInputAvailability()
                return self?.inputCoordinator.status ?? .stopped
            },
            showOnboarding: { [weak self] in
                self?.showOnboardingAgain()
            }
        )

        inputCoordinator.onStatusChange = { [weak self] status in
            guard let self else { return }
            self.settingsViewModel.updateInputStatus(status)
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
        onboardingCoordinator.start { [weak self] mode in
            self?.onboardingWindowController.show(mode: mode)
        }
    }

    private func startProductServices() {
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
        onboardingWindowController.closeWithoutCompleting()
        permissionService.stopMonitoringSystemSettingsChanges()
        permissionStateObservation?.cancel()
        permissionStateObservation = nil
        inputCoordinator.stop()
        pasteboardMonitor.stop()
        retentionTimer?.invalidate()
        retentionTimer = nil
        panels.closeAll()
        settingsWindowController.close()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private func configureStatusItem() {
        guard statusItem == nil else { return }
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.statusItem = statusItem
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

        menu.addItem(menuItem(title: "Settings…", action: #selector(showSettings)))

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
    }

    func refreshSystemPermissions() {
        permissionService.refresh()
        onboardingWindowController.refresh()
        if onboardingCoordinator.productServicesStarted {
            settingsWindowController.refresh()
        }
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
            showPermissionSettings()
            return
        }
        refreshInputAvailability()
        guard inputCoordinator.status == .ready else {
            showPermissionSettings()
            return
        }
        stackCollectionStarter.startFromHotKey()
        updatePasteStackMenuTitle()
    }

    private func startPasteStackFromMenu() {
        guard permissionService.refresh() == .granted else {
            showPermissionSettings()
            return
        }
        refreshInputAvailability()
        guard inputCoordinator.status == .ready else {
            showPermissionSettings()
            return
        }
        stackCollectionStarter.startFromMenu()
        updatePasteStackMenuTitle()
    }

    private func cancelPasteStack() {
        panels.cancelPasteStack()
        updatePasteStackMenuTitle()
    }

    @objc private func showSettings() {
        settingsWindowController.show()
    }

    private func showPermissionSettings() {
        settingsWindowController.show(section: .general)
    }

    private func requestAccessibilityAccess() {
        permissionService.requestAccess()
        refreshInputAvailability()
    }

    private func requestAccessibilityAccessFromOnboarding() {
        permissionService.requestAccess()
        onboardingWindowController.refresh()
    }

    private func openAccessibilitySettings() {
        permissionService.openSystemSettings()
    }

    private func showOnboardingAgain() {
        onboardingCoordinator.showAgain { [weak self] mode in
            self?.onboardingWindowController.show(mode: mode)
        }
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
