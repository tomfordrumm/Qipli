import AppKit
import Combine

enum ApplicationShellPasteboardRouting {
    static func shouldCaptureRichText(_ change: PasteboardTypedChange) -> Bool {
        (change.richTextCaptureRejected || !change.richTextItems.isEmpty) &&
            change.imageItems.isEmpty &&
            change.referenceItems.isEmpty &&
            change.canonicalText != nil
    }


    static func capture(from change: PasteboardTypedChange) -> HistoryCapture? {
        guard change.captureFailure == nil else { return nil }
        if shouldCaptureRichText(change), let canonicalText = change.canonicalText {
            return .richText(text: canonicalText, items: change.richTextItems)
        }
        if !change.imageItems.isEmpty, !change.referenceItems.isEmpty {
            return .mixed(images: change.imageItems, references: change.referenceItems)
        }
        if !change.imageItems.isEmpty {
            return .images(change.imageItems)
        }
        if !change.referenceItems.isEmpty {
            return .references(change.referenceItems)
        }
        return nil
    }
}

/// Owns AppKit lifecycle concerns. Product rules remain in the injected services.
@MainActor
final class ApplicationShell: NSObject {
    private let permissionService: AccessibilityPermissionService
    private let inputCoordinator: InputCoordinator
    private var recentHistoryMenu: RecentHistoryMenuController?
    private let panels: PanelController
    private let historyViewModel: HistoryViewModel
    private let stackSessionController: StackSessionController
    private let finderCutSessionController: FinderCutSessionController
    private let stackCaptureCoordinator: StackCollectionCaptureCoordinator
    private let stackCollectionStarter: StackCollectionStarter
    private let stackSequentialPasteExecutor: StackSequentialPasteExecutor
    private let pasteboardMonitor: PasteboardMonitor
    private let shortcutPreferences: ShortcutPreferences
    private let secureUpdater: SecureUpdaterServicing
    private let settingsViewModel: SettingsViewModel
    private var settingsWindowController: SettingsWindowController!
    private var onboardingCoordinator: OnboardingCoordinator!
    private var onboardingWindowController: OnboardingWindowController!
    private var retentionTimer: Timer?
    private var permissionStateObservation: AnyCancellable?
    private var historyShortcutObservation: AnyCancellable?
    private var updateAvailabilityObservation: AnyCancellable?
    private var statusItem: NSStatusItem?
    private let pasteStackMenuItem = NSMenuItem()
    private let checkForUpdatesMenuItem = NSMenuItem()

    init(
        permissionService: AccessibilityPermissionService = AccessibilityPermissionService(),
        inputAdapter: GlobalInputEventAdapting? = nil,
        shortcutPreferences: ShortcutPreferences = ShortcutPreferences(),
        launchAtLoginService: LaunchAtLoginServicing = SystemLaunchAtLoginService(),
        secureUpdater: SecureUpdaterServicing? = nil,
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
        historyShortcutObservation = shortcutPreferences.$snapshot
            .map(\.history)
            .removeDuplicates()
            .sink { [weak resolvedInputAdapter] binding in
                (resolvedInputAdapter as? CGEventTapAdapter)?.refreshHistoryShortcut(binding)
            }
        let store: HistoryStoring
        if let historyStore {
            store = historyStore
        } else {
            store = RetryingHistoryStore { try CoreDataHistoryStore() }
        }
        let historyClock = SystemHistoryClock()
        let historyService = HistoryService(store: store, clock: historyClock)
        let historyPersistence = SerializedHistoryService(service: historyService)
        historyViewModel = HistoryViewModel(service: historyPersistence, now: { historyClock.now })
        stackSessionController = StackSessionController(
            releasePayloadLeases: { leases in
                Task { @MainActor in
                    for lease in leases {
                        await historyPersistence.releaseStackPayloadLease(lease)
                    }
                }
            }
        )
        stackCaptureCoordinator = StackCollectionCaptureCoordinator(
            historyViewModel: historyViewModel,
            stackSessionController: stackSessionController
        )
        let resolvedCopyCommandDispatcher = copyCommandDispatcher
            ?? (resolvedInputAdapter as? TaggedCopyCommandDispatching)
            ?? UnavailableCopyCommandDispatcher()
        let resolvedMoveCommandDispatcher = (resolvedInputAdapter as? TaggedMoveCommandDispatching)
            ?? UnavailableMoveCommandDispatcher()
        let resolvedPasteCommandDispatcher = pasteCommandDispatcher
            ?? (resolvedInputAdapter as? TaggedPasteCommandDispatching)
            ?? UnavailablePasteCommandDispatcher()
        let finderCutSessionController = FinderCutSessionController(
            contextProvider: SystemFinderContextProvider(),
            pasteboard: SystemFinderCutPasteboard(),
            copyCommandDispatcher: resolvedCopyCommandDispatcher,
            moveCommandDispatcher: resolvedMoveCommandDispatcher,
            pasteCommandDispatcher: resolvedPasteCommandDispatcher,
            stackIsActive: { [weak stackSessionController] in
                stackSessionController?.isActive ?? false
            }
        )
        self.finderCutSessionController = finderCutSessionController
        let monitor = PasteboardMonitor(
            onExternalText: { [weak stackCaptureCoordinator, weak stackSessionController] change in
            // The monitor observes the active session before it defers the
            // persistence work. A later Start/Cancel cannot claim this copy;
            // the session watermark also rejects a write that predates Start.
            let captureContext = stackSessionController?.captureContext
            stackCaptureCoordinator?.enqueue(
                .text(change.text),
                observedChangeCount: change.changeCount,
                stackCaptureContext: captureContext
            )
            },
            onExternalChange: { [weak stackCaptureCoordinator, weak stackSessionController] change in
                let captureContext = stackSessionController?.captureContext
                if let failure = change.captureFailure {
                    stackCaptureCoordinator?.reject(message: failure.localizedDescription,
                        observedChangeCount: change.changeCount, stackCaptureContext: captureContext)
                    return
                }
                if let capture = ApplicationShellPasteboardRouting.capture(from: change) {
                    stackCaptureCoordinator?.enqueue(
                        capture,
                        observedChangeCount: change.changeCount,
                        stackCaptureContext: captureContext
                    )
                }
            },
            onExternalChangeObserved: { [weak finderCutSessionController] changeCount in
                finderCutSessionController?.handleExternalPasteboardChange(changeCount: changeCount) ?? false
            }
        )
        pasteboardMonitor = monitor
        finderCutSessionController.registerSelfWrite = { [weak monitor] changeCount in
            monitor?.registerSelfWrite(changeCount: changeCount)
        }
        inputCoordinator = InputCoordinator(
            permissionService: permissionService,
            eventAdapter: resolvedInputAdapter
        )
        let commandDispatcher = resolvedPasteCommandDispatcher
        let pasteExecutor = HistoryPasteExecutor(
            permissionService: permissionService,
            pasteboardWriter: SystemHistoryPasteboardWriter(),
            registerSelfWrite: { [weak pasteboardMonitor] changeCount in
                pasteboardMonitor?.registerSelfWrite(changeCount: changeCount)
            },
            commandDispatcher: commandDispatcher,
            payloadProvider: { entry async throws in
                if entry.isTypedEntry {
                    return try await historyPersistence.pastePayload(id: entry.id)
                }
                return HistoryPastePayload(items: [HistoryPasteboardItemPayload(representations: [
                    HistoryPasteboardRepresentationPayload(typeIdentifier: "public.utf8-plain-text", data: Data(entry.text.utf8))
                ])])
            }
        )
        let panelController = PanelController(
            permissionService: permissionService,
            historyViewModel: historyViewModel,
            stackSessionController: stackSessionController,
            finderCutSessionController: finderCutSessionController,
            historyPasteExecutor: pasteExecutor,
            openAccessibilitySettings: { [weak permissionService] in
                permissionService?.openSystemSettings()
            }
        )
        panels = panelController
        finderCutSessionController.showPanel = { [weak panelController] in
            panelController?.showFinderCut()
        }
        finderCutSessionController.hidePanel = { [weak panelController] in
            panelController?.dismissFinderCutPanel()
        }
        historyViewModel.onHistoryEntryDeletionWillStart = { [weak stackSessionController] id in
            stackSessionController?.prepareHistoryDeletion(for: id) ?? false
        }
        historyViewModel.onHistoryEntryDeleted = { [weak stackSessionController] id in
            stackSessionController?.finalizeHistoryDeletion(for: id)
        }
        historyViewModel.onHistoryEntryDeletionFailed = { [weak stackSessionController] id in
            stackSessionController?.cancelHistoryDeletion(for: id)
        }
        historyViewModel.onClearAllWillStart = { [weak panelController, weak finderCutSessionController] in
            panelController?.cancelPasteStack()
            finderCutSessionController?.cancel()
        }
        stackSequentialPasteExecutor = StackSequentialPasteExecutor(
            permissionService: permissionService,
            pasteboardWriter: SystemHistoryPasteboardWriter(),
            registerSelfWrite: { [weak pasteboardMonitor] changeCount in
                pasteboardMonitor?.registerSelfWrite(changeCount: changeCount)
            },
            commandDispatcher: commandDispatcher,
            sessionController: stackSessionController,
            payloadProvider: { handle in
                try await historyPersistence.pastePayload(id: handle.historyEntryID)
            },
            leaseValidator: { lease in
                await historyPersistence.isStackPayloadLeaseValid(lease)
            },
            currentPasteboardChangeCount: { monitor.currentChangeCount },
            finishPresentation: { panelController.finishPasteStackAfterCompletion() }
        )
        stackCollectionStarter = StackCollectionStarter(
            sessionController: stackSessionController,
            currentPasteboardChangeCount: { monitor.currentChangeCount },
            showStackPanel: { panelController.showPasteStack() },
            copyCommandDispatcher: resolvedCopyCommandDispatcher
        )
        #if DEBUG
        let resolvedSecureUpdater = secureUpdater ?? UnavailableSecureUpdater()
        #else
        let resolvedSecureUpdater = secureUpdater ?? SparkleSecureUpdater()
        #endif
        self.secureUpdater = resolvedSecureUpdater
        settingsViewModel = SettingsViewModel(
            shortcutPreferences: shortcutPreferences,
            launchAtLoginService: launchAtLoginService,
            secureUpdater: resolvedSecureUpdater
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
            },
            clearHistory: { [weak self] in
                await self?.historyViewModel.clearAll() ?? false
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
            stackSessionController?.acceptNextPasteInput(
                pasteboardChangeCount: monitor.currentChangeCount
            ) ?? .passThrough
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
        inputCoordinator.onFinderCutCommand = { [weak finderCutSessionController] isRepeat in
            finderCutSessionController?.handleCommandX(isRepeat: isRepeat)
        }
        inputCoordinator.finderCutPasteInterception = { [weak finderCutSessionController] isRepeat in
            finderCutSessionController?.inputGate.admitPaste(isRepeat: isRepeat) ?? .passThrough
        }
        inputCoordinator.onFinderCutMove = { [weak finderCutSessionController] in
            finderCutSessionController?.dispatchMove()
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
        secureUpdater.start()
        configureStatusItem()
        observeUpdateAvailability()
        observePermissionChanges()
        refreshInputAvailability()
        pasteboardMonitor.start()
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.historyViewModel.reload()
            self.panels.prepareHistoryPanel()
            self.retentionTimer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.historyViewModel.reload()
                }
            }
        }
    }

    func stop() {
        onboardingWindowController.closeWithoutCompleting()
        permissionService.stopMonitoringSystemSettingsChanges()
        permissionStateObservation?.cancel()
        permissionStateObservation = nil
        updateAvailabilityObservation?.cancel()
        updateAvailabilityObservation = nil
        secureUpdater.stop()
        finderCutSessionController.cancel()
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
        menu.autoenablesItems = false
        let recentMenu = RecentHistoryMenuController(
            snapshot: { [weak self] in self?.historyViewModel.recentState ?? .loading },
            refresh: { [weak self] in
                self?.pasteboardMonitor.poll()
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.stackCaptureCoordinator.drainPendingCaptures()
                    await self.historyViewModel.refreshRecentHistory()
                }
            },
            captureTarget: { SystemFrontmostApplicationCapture().capturePriorApplication() },
            stackIsActive: { [weak self] in self?.stackSessionController.isActive ?? true },
            paste: { [weak self] id, target in self?.panels.pasteRecentHistoryEntry(id: id, target: target) }
        )
        recentHistoryMenu = recentMenu
        menu.delegate = recentMenu
        let historyItem = menuItem(title: "Open History", action: #selector(showHistory))
        historyItem.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: "History")
        menu.addItem(historyItem)
        pasteStackMenuItem.target = self
        pasteStackMenuItem.action = #selector(togglePasteStackFromMenu)
        menu.addItem(pasteStackMenuItem)
        menu.addItem(.separator())

        checkForUpdatesMenuItem.title = "Check for Updates…"
        checkForUpdatesMenuItem.target = self
        checkForUpdatesMenuItem.action = #selector(checkForUpdates)
        checkForUpdatesMenuItem.isEnabled = settingsViewModel.canCheckForUpdates
        menu.addItem(checkForUpdatesMenuItem)
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

    private func observeUpdateAvailability() {
        guard updateAvailabilityObservation == nil else { return }
        updateAvailabilityObservation = settingsViewModel.$canCheckForUpdates
            .removeDuplicates()
            .sink { [weak self] canCheck in
                self?.checkForUpdatesMenuItem.isEnabled = canCheck
            }
    }

    private func updatePasteStackMenuTitle() {
        pasteStackMenuItem.title = stackSessionController.isActive ? "Cancel Paste Stack" : "Start Paste Stack"
    }

    @objc private func showHistory() {
        HistoryPresentationExecutor(
            pollPasteboard: { [weak self] in
                self?.pasteboardMonitor.poll()
            },
            presentCachedHistory: { [weak self] in
                self?.panels.showHistory()
            },
            startCaptureDrain: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.stackCaptureCoordinator.drainPendingCaptures()
                }
            }
        )
        .execute()
    }

    @objc private func togglePasteStackFromMenu() {
        if stackSessionController.isActive {
            cancelPasteStack()
        } else {
            startPasteStackFromMenu()
        }
    }

    private func startPasteStackFromHotKey() {
        finderCutSessionController.cancel()
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
        finderCutSessionController.cancel()
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

    @objc private func checkForUpdates() {
        settingsViewModel.checkForUpdates()
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

/// Fresh pasteboard capture continues after the reusable cached panel is on
/// screen. The capture pipeline still publishes the durable occurrence into the
/// visible History when it completes.
@MainActor
struct HistoryPresentationExecutor {
    let pollPasteboard: () -> Void
    let presentCachedHistory: () -> Void
    let startCaptureDrain: () -> Void

    func execute() {
        pollPasteboard()
        presentCachedHistory()
        startCaptureDrain()
    }
}

private final class UnavailablePasteCommandDispatcher: TaggedPasteCommandDispatching {
    func postTaggedCommandV() -> Bool { false }
}

private final class UnavailableCopyCommandDispatcher: TaggedCopyCommandDispatching {
    func postTaggedCommandC() -> Bool { false }
}

private final class UnavailableMoveCommandDispatcher: TaggedMoveCommandDispatching {
    func postTaggedCommandMove() -> Bool { false }
}

/// Owns an immutable set of native menu rows for each opening. Persistence
/// refreshes the next snapshot without changing the item under the pointer.
@MainActor
final class RecentHistoryMenuController: NSObject, NSMenuDelegate {
    private let snapshot: () -> HistoryViewState
    private let refresh: () -> Void
    private let captureTarget: () -> HistoryPasteTarget?
    private let stackIsActive: () -> Bool
    private let paste: (UUID, HistoryPasteTarget?) -> Void
    private var insertedItems: [NSMenuItem] = []
    private var openingID: UUID?
    private var target: HistoryPasteTarget?
    private var selected = false

    init(snapshot: @escaping () -> HistoryViewState,
         refresh: @escaping () -> Void,
         captureTarget: @escaping () -> HistoryPasteTarget?,
         stackIsActive: @escaping () -> Bool,
         paste: @escaping (UUID, HistoryPasteTarget?) -> Void) {
        self.snapshot = snapshot
        self.refresh = refresh
        self.captureTarget = captureTarget
        self.stackIsActive = stackIsActive
        self.paste = paste
    }

    func menuWillOpen(_ menu: NSMenu) {
        target = captureTarget()
        openingID = UUID()
        selected = false
        insertedItems.forEach { menu.removeItem($0) }
        insertedItems = []
        let blocked = stackIsActive()
        switch snapshot() {
        case .loading:
            append(NSMenuItem(title: "Loading recent History…", action: nil, keyEquivalent: ""), to: menu)
        case .error:
            append(NSMenuItem(title: "Recent History unavailable. Reopen to retry.", action: nil, keyEquivalent: ""), to: menu)
        case .empty:
            break
        case let .list(descriptors):
            for descriptor in descriptors.prefix(5) {
                let row = RecentHistoryMenuRow(descriptor)
                let item = NSMenuItem(title: row.title, action: #selector(selectRecent(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = descriptor.id
                item.image = NSImage(systemSymbolName: row.symbol, accessibilityDescription: row.kind)
                item.isEnabled = !blocked
                item.setAccessibilityLabel(row.kind + ": " + row.title)
                append(item, to: menu)
            }
            if blocked && !descriptors.isEmpty {
                append(NSMenuItem(title: "Finish Paste Stack to paste from History", action: nil, keyEquivalent: ""), to: menu)
            }
        }
        if !insertedItems.isEmpty {
            let separator = NSMenuItem.separator()
            menu.insertItem(separator, at: 1)
            insertedItems.insert(separator, at: 0)
            append(.separator(), to: menu)
        }
        refresh()
    }

    func menuDidClose(_ menu: NSMenu) {
        let closedID = openingID
        // AppKit can deliver the selected item's action after menuDidClose.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.openingID == closedID else { return }
            self.openingID = nil
            self.target = nil
        }
    }

    private func append(_ item: NSMenuItem, to menu: NSMenu) {
        if item.action == nil { item.isEnabled = false }
        menu.insertItem(item, at: 1 + insertedItems.count)
        insertedItems.append(item)
    }

    @objc func selectRecent(_ sender: NSMenuItem) {
        guard openingID != nil, !selected, !stackIsActive(), sender.isEnabled,
              insertedItems.contains(where: { $0 === sender }),
              let id = sender.representedObject as? UUID else { return }
        selected = true
        let capturedTarget = target
        sender.menu?.cancelTracking()
        // Default-mode dispatch runs after native menu tracking has unwound.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.stackIsActive() else { return }
            self.paste(id, capturedTarget)
        }
    }
}

struct RecentHistoryMenuRow {
    let title: String
    let symbol: String
    let kind: String

    init(_ descriptor: HistoryOccurrenceDescriptor) {
        let primary = descriptor.representations.first?.kind ?? .text
        switch primary {
        case .text: kind = "Text"; symbol = "text.alignleft"
        case .url: kind = "URL"; symbol = "link"
        case .inlineImage: kind = "Image"; symbol = "photo"
        case .fileReference: kind = "File"; symbol = "doc"
        case .videoReference: kind = "Video"; symbol = "film"
        }
        let count = descriptor.imageMetadata.count + descriptor.referenceMetadata.count
        let source = descriptor.textPreview
            ?? descriptor.referenceMetadata.first?.displayName
            ?? kind
        let bounded = source.prefix(256).split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        let preview = bounded.isEmpty ? kind : bounded
        let suffix = count > 1 ? " (\(count) items)" : ""
        title = String(preview.prefix(64)) + (preview.count > 64 || source.count > 256 ? "…" : "") + suffix
    }
}
