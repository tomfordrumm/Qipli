import AppKit
import SwiftUI

/// Maintains one AppKit panel per temporary surface; reopening a surface reuses its panel.
@MainActor
final class PanelController {
    private let permissionService: AccessibilityPermissionService
    private let historyViewModel: HistoryViewModel
    private let stackSessionController: StackSessionController
    private let historyPasteExecutor: HistoryPasteExecutor
    private let frontmostApplicationCapture: FrontmostApplicationCapturing
    private let screenProvider: PanelScreenProviding
    private let topNotchScreenProvider: TopNotchScreenProviding
    private let openAccessibilitySettings: () -> Void
    private let activationPresenter: PanelActivationPresenter
    private let materialProvider: PanelMaterialProvider
    private let topNotchInteractionBridge = TopNotchHistoryInteractionBridge()
    private let topNotchLayoutModel = TopNotchHistoryLayoutModel()
    private let historyPresentation = TopNotchPanelLifecycle()
    private let stackPresentation = TopNotchPanelLifecycle()
    private var historyPanel: NSPanel?
    private var stackPanel: NSPanel?
    private var stackTopNotchScreen: NSScreen?
    private var historyPasteTarget: HistoryPasteTarget?
    private var historyPasteTransactionID: UUID?
    private var pendingHistoryPasteEntryID: UUID?
    private var historyPanelDelegate: HistoryPanelDelegate?
    private var historyKeyboardMonitor: HistoryPanelKeyboardMonitor?
    private var historyOutsideClickMonitor: HistoryPanelOutsideClickMonitor?
    private var stackPanelDelegate: StackPanelDelegate?
    private var screenParametersObserver: NSObjectProtocol?

    /// The shell uses this only to refresh its Start/Cancel menu title.
    var onPasteStackCancelled: (() -> Void)?

    init(
        permissionService: AccessibilityPermissionService,
        historyViewModel: HistoryViewModel,
        stackSessionController: StackSessionController,
        historyPasteExecutor: HistoryPasteExecutor,
        frontmostApplicationCapture: FrontmostApplicationCapturing = SystemFrontmostApplicationCapture(),
        screenProvider: PanelScreenProviding = SystemPanelScreenProvider(),
        topNotchScreenProvider: TopNotchScreenProviding = SystemTopNotchScreenProvider(),
        applicationActivator: QipliApplicationActivating? = nil,
        materialProvider: PanelMaterialProvider? = nil,
        activationScheduler: @escaping (@escaping () -> Void) -> Void = { action in
            RunLoop.main.perform(inModes: [.common]) { action() }
        },
        openAccessibilitySettings: @escaping () -> Void
    ) {
        self.permissionService = permissionService
        self.historyViewModel = historyViewModel
        self.stackSessionController = stackSessionController
        self.historyPasteExecutor = historyPasteExecutor
        self.frontmostApplicationCapture = frontmostApplicationCapture
        self.screenProvider = screenProvider
        self.topNotchScreenProvider = topNotchScreenProvider
        self.openAccessibilitySettings = openAccessibilitySettings
        self.materialProvider = materialProvider ?? PanelMaterialProvider()
        let resolvedApplicationActivator = applicationActivator ?? SystemQipliApplicationActivator()
        activationPresenter = PanelActivationPresenter(
            application: resolvedApplicationActivator,
            scheduleNextMainRunLoop: activationScheduler
        )
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshVisibleTopNotchFrame()
            }
        }
    }

    deinit {
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
        }
    }

    func showHistory() {
        cancelHistoryPasteTransaction()
        restoreHistoryPanelPresentation()
        _ = permissionService.refresh()
        let isFreshPresentation = historyPanel?.isVisible != true
        if isFreshPresentation {
            historyPasteTarget = frontmostApplicationCapture.capturePriorApplication()
        }
        historyViewModel.prepareForPresentation()
        topNotchInteractionBridge.applySnapshot(
            entryIDs: historyViewModel.visibleDescriptors.map(\.id),
            selectedEntryID: historyViewModel.selectedEntryID
        )
        let panel: NSPanel
        if let historyPanel {
            panel = historyPanel
        } else {
            panel = makeHistoryPanel()
        }
        historyPanel = panel
        topNotchLayoutModel.topContentInset = topNotchSafeAreaInset(for: historyPasteTarget)
        let expandedFrame = topNotchFrame(for: panel, target: historyPasteTarget)
        let collapsedFrame = topNotchCollapsedFrame(
            from: expandedFrame,
            target: historyPasteTarget
        )
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let presentation = historyPresentation.prepare(
            panel: panel,
            expandedFrame: expandedFrame,
            compactRect: topNotchCompactRect(collapsedFrame: collapsedFrame, expandedFrame: expandedFrame),
            reduceMotion: reduceMotion
        )
        present(
            panel,
            requestSearchFocus: true,
            requiresStrongUserActivation: true,
            preserveFrame: true,
            afterPresent: { [weak self, weak panel] in
                guard let self, let panel else { return }
                self.historyPresentation.animatePresentation(panel: panel, token: presentation)
            }
        )
    }

    /// Builds the reusable Top Notch History surface after startup data has
    /// loaded so the first user invocation does not pay construction cost.
    func prepareHistoryPanel() {
        guard historyPanel == nil else { return }
        historyPanel = makeHistoryPanel()
    }

    func showPasteStack() {
        let capturedScreen = frontmostApplicationCapture.capturePriorApplication()?.preferredScreen
        let panel = stackPanel ?? makeStackPanel {
            PasteStackPanelView(
                sessionController: self.stackSessionController,
                close: { [weak self] in self?.cancelPasteStack() }
            )
        }
        stackPanel = panel
        stackTopNotchScreen = resolveStackTopNotchScreen(preferredScreen: capturedScreen)
        panel.ignoresMouseEvents = false
        panel.alphaValue = 1
        let expandedFrame = topNotchFrame(
            for: panel,
            target: nil,
            preferredScreen: stackTopNotchScreen,
            panelSize: TopNotchHistoryGeometry.pasteStackPanelSize,
            includesSafeAreaBand: false
        )
        let collapsedFrame = topNotchCollapsedFrame(
            from: expandedFrame,
            target: nil,
            preferredScreen: stackTopNotchScreen
        )
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let presentation = stackPresentation.prepare(
            panel: panel,
            expandedFrame: expandedFrame,
            compactRect: topNotchCompactRect(collapsedFrame: collapsedFrame, expandedFrame: expandedFrame),
            reduceMotion: reduceMotion
        )

        present(
            panel,
            activatesApplication: false,
            preserveFrame: true,
            afterPresent: { [weak self, weak panel] in
                guard let self, let panel else { return }
                self.stackPresentation.animatePresentation(panel: panel, token: presentation)
            }
        )
    }

    func cancelPasteStack() {
        stackSessionController.cancel()
        dismissPasteStackPanel()
        onPasteStackCancelled?()
    }

    /// S006 has already published the all-used state before this deferred
    /// presentation cleanup. Do not reactivate the former target here.
    func finishPasteStackAfterCompletion() {
        dismissPasteStackPanel()
        onPasteStackCancelled?()
    }

    func closeAll() {
        cancelHistoryPasteTransaction()
        cancelPasteStack()
        historyPanel?.delegate = nil
        historyPresentation.close(panel: historyPanel)
        stackPresentation.close(panel: stackPanel)
        [historyPanel, stackPanel].forEach { $0?.close() }
    }

    private func pasteHistoryEntry(_ entry: HistoryEntry, mode: HistoryPasteMode = .rich) {
        pendingHistoryPasteEntryID = nil
        guard historyPasteTransactionID == nil else { return }
        let transactionID = UUID()
        historyPasteTransactionID = transactionID
        let started = historyPasteExecutor.paste(
            entry: entry,
            target: historyPasteTarget,
            mode: mode,
            concealPanel: { [weak self] in self?.concealHistoryForPaste() },
            closePanel: { [weak self] in self?.dismissHistoryForPaste() },
            completion: { [weak self] result in
                guard let self, self.historyPasteTransactionID == transactionID else { return }
                self.historyPasteTransactionID = nil
                self.historyViewModel.endPaste()
                switch result {
                case .success:
                    Task { @MainActor [weak self] in
                        await self?.historyViewModel.markUsedAfterSuccessfulPaste(id: entry.id)
                    }
                case let .failure(failure):
                    self.historyViewModel.recordPasteFailure(failure)
                    self.reopenHistoryAfterPasteFailure()
                }
            }
        )
        if !started {
            historyPasteTransactionID = nil
            historyViewModel.endPaste()
        }
    }

    private func concealHistoryForPaste() {
        historyPanel?.alphaValue = 0
        historyPanel?.ignoresMouseEvents = true
        historyViewModel.beginPaste()
    }

    private func dismissHistoryForPaste() {
        hideHistoryPanel()
    }

    private func cancelHistory() {
        dismissHistory(.explicit)
    }

    private func passiveDismissHistory() {
        dismissHistory(.passive)
    }

    private func dismissHistory(_ intent: HistoryPanelDismissalIntent) {
        HistoryPanelDismissalExecutor(
            cancelPaste: { [weak self] in self?.cancelHistoryPasteTransaction() },
            hide: { [weak self] completion in
                self?.hideHistoryPanel(completion: completion)
            },
            restoreFocus: { [weak self] in
                _ = HistoryFocusRestorer.returnToCapturedTarget(self?.historyPasteTarget)
            }
        )
        .execute(intent)
    }

    private func cancelHistoryPasteTransaction() {
        pendingHistoryPasteEntryID = nil
        guard historyPasteTransactionID != nil || historyPasteExecutor.hasActivePaste else {
            return
        }
        historyPasteExecutor.cancelActivePaste()
        historyPasteTransactionID = nil
        historyViewModel.endPaste()
        restoreHistoryPanelPresentation()
    }

    private func reopenHistoryAfterPasteFailure() {
        restoreHistoryPanelPresentation()
        guard let historyPanel else { return }
        if historyPanel.isVisible {
            if !historyPanel.isKeyWindow {
                historyPanel.makeKeyAndOrderFront(nil)
                historyViewModel.requestSearchFocus()
            }
            return
        }
        present(
            historyPanel,
            requestSearchFocus: true,
            requiresStrongUserActivation: true,
            preserveFrame: true
        )
    }

    private func hideHistoryPanel(completion: @escaping () -> Void = {}) {
        guard let panel = historyPanel else {
            completion()
            return
        }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let expandedFrame = topNotchFrame(for: panel, target: historyPasteTarget)
        let collapsedFrame = topNotchCollapsedFrame(from: expandedFrame, target: historyPasteTarget)
        historyPresentation.dismiss(
            panel: panel,
            compactRect: topNotchCompactRect(collapsedFrame: collapsedFrame, expandedFrame: expandedFrame),
            reduceMotion: reduceMotion,
            completion: completion
        )
    }

    private func restoreHistoryPanelPresentation() {
        historyPresentation.restore(panel: historyPanel)
    }

    private func makePanel<Content: View>(
        kind: PanelKind,
        @ViewBuilder content: () -> Content
    ) -> NSPanel {
        let configuration = PanelWindowConfiguration.make(for: kind)
        let panel: NSPanel
        if kind == .topNotchHistory {
            panel = TopNotchHistoryPanel(
                contentRect: configuration.contentRect,
                styleMask: configuration.styleMask,
                backing: .buffered,
                defer: false
            )
        } else if kind == .pasteStack {
            panel = TopNotchPasteStackPanel(
                contentRect: configuration.contentRect,
                styleMask: configuration.styleMask,
                backing: .buffered,
                defer: false
            )
        } else {
            panel = NSPanel(
                contentRect: configuration.contentRect,
                styleMask: configuration.styleMask,
                backing: .buffered,
                defer: false
            )
        }
        configuration.applyPresentation(to: panel)
        let surface = materialProvider.install(
            content: NSHostingView(rootView: content()),
            in: panel,
            opaqueBackground: kind == .topNotchHistory || kind == .pasteStack ? .black : nil,
            opaqueSurface: kind == .topNotchHistory || kind == .pasteStack
                ? TopNotchHistorySurfaceView()
                : nil
        )
        configuration.applySurfacePresentation(to: surface)
        if kind == .topNotchHistory || kind == .pasteStack {
            // The expanded shelf is the notch overlay, not a window below it:
            // keep it above the menu bar and let the black surface meet the
            // hardware camera area directly.
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
            surface.layer?.cornerRadius = 0
            panel.hasShadow = false
            if kind == .topNotchHistory {
                historyPresentation.attach(surface: surface as? TopNotchHistorySurfaceView)
            } else {
                stackPresentation.attach(surface: surface as? TopNotchHistorySurfaceView)
            }
        }

        switch kind {
        case .topNotchHistory:
            (panel as? TopNotchHistoryPanel)?.onCancel = { [weak self] in
                self?.scheduleHistoryCancellation()
            }
            let panelDelegate = HistoryPanelDelegate(
                cancel: { [weak self] in self?.cancelHistory() },
                passiveDismiss: { [weak self] in self?.passiveDismissHistory() },
                didBecomeKey: { [weak self] in self?.historyViewModel.requestSearchFocus() }
            )
            panel.delegate = panelDelegate
            historyPanelDelegate = panelDelegate
            historyKeyboardMonitor = HistoryPanelKeyboardMonitor(
                panel: panel,
                selectionAxis: .horizontal
            ) { [weak self] action in
                self?.handleHistoryKeyAction(action) ?? false
            }
            if configuration.dismissesOnOutsideClick {
                historyOutsideClickMonitor = HistoryPanelOutsideClickMonitor(panel: panel) { [weak self] in
                    self?.passiveDismissHistory()
                }
            }
        case .pasteStack:
            break
        }
        return panel
    }

    private func makeHistoryPanel() -> NSPanel {
        makePanel(kind: .topNotchHistory) {
            TopNotchHistoryShelfView(
                viewModel: self.historyViewModel,
                permissionService: self.permissionService,
                layoutModel: self.topNotchLayoutModel,
                openAccessibilitySettings: self.openAccessibilitySettings,
                pasteEntry: { [weak self] id in self?.requestPasteHistoryEntry(id: id) },
                close: { [weak self] in self?.cancelHistory() },
                interactionBridge: self.topNotchInteractionBridge
            )
        }
    }

    private func handleHistoryKeyAction(_ action: HistoryPanelKeyAction) -> Bool {
        switch action {
        case let .moveSelection(offset):
            historyViewModel.moveSelection(by: offset)
            topNotchInteractionBridge.applySelection(id: historyViewModel.selectedEntryID)
            return true
        case .pasteSelection, .pasteSelectionAsPlainText:
            if historyPasteTransactionID != nil || historyViewModel.isPasteInProgress {
                return true
            }
            guard permissionService.state == .granted else {
                return false
            }
            guard let selectedEntryID = historyViewModel.selectedEntryID else { return false }
            requestPasteHistoryEntry(
                id: selectedEntryID,
                mode: action == .pasteSelectionAsPlainText ? .plainText : .rich
            )
            return true
        case .close:
            scheduleHistoryCancellation()
            return true
        }
    }

    private func scheduleHistoryCancellation() {
        RunLoop.main.perform(inModes: [.common]) { [weak self] in
            Task { @MainActor [weak self] in
                self?.cancelHistory()
            }
        }
    }

    private func requestPasteHistoryEntry(id: UUID, mode: HistoryPasteMode = .rich) {
        guard pendingHistoryPasteEntryID == nil,
              historyPasteTransactionID == nil,
              !historyViewModel.isPasteInProgress,
              permissionService.state == .granted
        else { return }
        pendingHistoryPasteEntryID = id
        Task { @MainActor [weak self] in
            guard let self,
                  self.pendingHistoryPasteEntryID == id
            else { return }
            self.pendingHistoryPasteEntryID = nil
            switch await self.historyViewModel.entryForPaste(id: id) {
            case let .success(entry):
                self.pasteHistoryEntry(entry, mode: mode)
            case let .failure(failure):
                self.historyViewModel.recordPasteFailure(failure)
                self.reopenHistoryAfterPasteFailure()
            }
        }
    }

    private func makeStackPanel<Content: View>(@ViewBuilder content: () -> Content) -> NSPanel {
        let configuration = PanelWindowConfiguration.make(for: .pasteStack)
        let panel = TopNotchPasteStackPanel(
            contentRect: configuration.contentRect,
            styleMask: configuration.styleMask,
            backing: .buffered,
            defer: false
        )
        configuration.applyPresentation(to: panel)
        let surface = materialProvider.install(
            content: NSHostingView(rootView: content()),
            in: panel,
            opaqueBackground: .black,
            opaqueSurface: TopNotchHistorySurfaceView()
        )
        configuration.applySurfacePresentation(to: surface)

        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        surface.layer?.cornerRadius = 0
        panel.hasShadow = false
        stackPresentation.attach(surface: surface as? TopNotchHistorySurfaceView)
        let panelDelegate = StackPanelDelegate(cancel: { [weak self] in self?.cancelPasteStack() })
        panel.delegate = panelDelegate
        stackPanelDelegate = panelDelegate
        return panel
    }

    private func present(
        _ panel: NSPanel,
        requestSearchFocus: Bool = false,
        requiresStrongUserActivation: Bool = false,
        activatesApplication: Bool = true,
        preserveFrame: Bool = false,
        afterPresent: @escaping () -> Void = {}
    ) {
        if preserveFrame {
            // The caller has already selected a display-specific frame, such as
            // the safe-area anchored Top Notch frame.
        } else {
            panel.center()
        }
        guard activatesApplication else {
            panel.orderFrontRegardless()
            afterPresent()
            return
        }
        // `NSApplication.activate()` is an asynchronous, best-effort request. The
        // panel must still be visible if activation is denied or delayed, so order
        // it before waiting for the active-only keyboard follow-up.
        activationPresenter.presentImmediatelyThenWhenActive(
            requiresStrongUserActivation: requiresStrongUserActivation,
            present: { [weak panel] in
                panel?.makeKeyAndOrderFront(nil)
                afterPresent()
            },
            whenActive: { [weak self, weak panel] in
                guard let panel else { return }
                panel.makeKey()
                if requestSearchFocus {
                    self?.historyViewModel.requestSearchFocus()
                }
            }
        )
    }

    /// A screen object can outlive the display it represents. Resolve the
    /// stored target against the current display list before moving an active
    /// Stack, otherwise a disconnected monitor can leave the panel off-screen.
    private func resolveStackTopNotchScreen(preferredScreen: NSScreen? = nil) -> NSScreen? {
        let preferred = preferredScreen ?? stackTopNotchScreen
        guard let preferred else {
            let fallback = topNotchScreenProvider.currentScreen()
            stackTopNotchScreen = fallback
            return fallback
        }

        let currentScreens = NSScreen.screens
        if let preferredDisplayID = TopNotchDisplaySelection.resolvedPreferredDisplayID(
            preferredDisplayID: displayID(for: preferred),
            availableDisplayIDs: currentScreens.compactMap(displayID(for:))
        ),
           let currentScreen = currentScreens.first(where: { displayID(for: $0) == preferredDisplayID }) {
            stackTopNotchScreen = currentScreen
            return currentScreen
        }

        if currentScreens.contains(where: { $0 === preferred }) {
            stackTopNotchScreen = preferred
            return preferred
        }

        let fallback = topNotchScreenProvider.currentScreen()
        stackTopNotchScreen = fallback
        return fallback
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
    }

    private func topNotchFrame(
        for panel: NSPanel,
        target: HistoryPasteTarget?,
        preferredScreen: NSScreen? = nil,
        panelSize: NSSize = TopNotchHistoryGeometry.defaultPanelSize,
        includesSafeAreaBand: Bool = true
    ) -> NSRect {
        guard let screen = target?.preferredScreen ?? preferredScreen ?? topNotchScreenProvider.currentScreen() else {
            return TopNotchHistoryGeometry.frame(
                screenFrame: screenProvider.currentVisibleFrame(),
                visibleFrame: screenProvider.currentVisibleFrame(),
                safeAreaInsets: NSEdgeInsets(),
                panelSize: panelSize
            )
        }
        return TopNotchHistoryGeometry.frame(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaInsets: screen.safeAreaInsets,
            auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea,
            panelSize: NSSize(
                width: panelSize.width,
                height: panelSize.height
                    + (includesSafeAreaBand
                        ? topNotchSafeAreaInset(for: target, preferredScreen: preferredScreen)
                        : 0)
            )
        )
    }

    private func topNotchSafeAreaInset(
        for target: HistoryPasteTarget?,
        preferredScreen: NSScreen? = nil
    ) -> CGFloat {
        max(0, (target?.preferredScreen ?? preferredScreen ?? topNotchScreenProvider.currentScreen())?.safeAreaInsets.top ?? 0)
    }

    private func topNotchCollapsedFrame(
        from expandedFrame: NSRect,
        target: HistoryPasteTarget?,
        preferredScreen: NSScreen? = nil
    ) -> NSRect {
        guard let screen = target?.preferredScreen ?? preferredScreen ?? topNotchScreenProvider.currentScreen() else {
            return TopNotchHistoryGeometry.collapsedFrame(from: expandedFrame)
        }
        return TopNotchHistoryGeometry.collapsedFrame(
            from: expandedFrame,
            safeAreaInsets: screen.safeAreaInsets,
            auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea
        )
    }

    private func topNotchCompactRect(
        collapsedFrame: NSRect,
        expandedFrame: NSRect
    ) -> CGRect {
        CGRect(
            x: collapsedFrame.minX - expandedFrame.minX,
            y: 0,
            width: collapsedFrame.width,
            height: collapsedFrame.height
        )
    }

    private func refreshVisibleTopNotchFrame() {
        if historyPresentation.isVisible, let panel = historyPanel, panel.isVisible {
            topNotchLayoutModel.topContentInset = topNotchSafeAreaInset(for: historyPasteTarget)
            panel.setFrame(topNotchFrame(for: panel, target: historyPasteTarget), display: true)
        }
        if stackPresentation.isVisible, let panel = stackPanel, panel.isVisible {
            let stackScreen = resolveStackTopNotchScreen()
            panel.setFrame(
                topNotchFrame(
                    for: panel,
                    target: nil,
                    preferredScreen: stackScreen,
                    panelSize: TopNotchHistoryGeometry.pasteStackPanelSize,
                    includesSafeAreaBand: false
                ),
                display: true
            )
        }
    }

    private func dismissPasteStackPanel() {
        guard let panel = stackPanel else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let stackScreen = resolveStackTopNotchScreen()
        let expandedFrame = topNotchFrame(
            for: panel,
            target: nil,
            preferredScreen: stackScreen,
            panelSize: TopNotchHistoryGeometry.pasteStackPanelSize,
            includesSafeAreaBand: false
        )
        let collapsedFrame = topNotchCollapsedFrame(
            from: expandedFrame,
            target: nil,
            preferredScreen: stackTopNotchScreen
        )
        stackPresentation.dismiss(
            panel: panel,
            compactRect: topNotchCompactRect(collapsedFrame: collapsedFrame, expandedFrame: expandedFrame),
            reduceMotion: reduceMotion
        )
    }

}

/// Shared animation and interruption policy for the two Top Notch panels.
/// Feature controllers provide geometry; this object owns visual state and
/// generation guards so History and Paste Stack cannot drift independently.
@MainActor
private final class TopNotchPanelLifecycle {
    struct PresentationToken {
        let generation: Int
        let shouldAnimate: Bool
        let reduceMotion: Bool
    }

    private weak var surface: TopNotchHistorySurfaceView?
    private(set) var state: TopNotchPresentationState = .hidden
    private var generation = 0

    var isVisible: Bool { state == .visible }

    func attach(surface: TopNotchHistorySurfaceView?) {
        self.surface = surface
    }

    func prepare(
        panel: NSPanel,
        expandedFrame: NSRect,
        compactRect: CGRect,
        reduceMotion: Bool
    ) -> PresentationToken {
        generation &+= 1
        let token = PresentationToken(
            generation: generation,
            shouldAnimate: !panel.isVisible,
            reduceMotion: reduceMotion
        )
        panel.ignoresMouseEvents = false
        if token.shouldAnimate {
            state = TopNotchPresentationStateMachine.transition(state, event: .show)
            panel.setFrame(expandedFrame, display: false)
            panel.contentView?.layoutSubtreeIfNeeded()
            if reduceMotion {
                surface?.restoreExpandedPresentation()
                panel.alphaValue = 0
            } else {
                surface?.prepareForReveal(from: compactRect)
                panel.alphaValue = 1
            }
        } else {
            state = .visible
            panel.alphaValue = 1
            panel.setFrame(expandedFrame, display: true)
            surface?.restoreExpandedPresentation()
        }
        return token
    }

    func animatePresentation(panel: NSPanel, token: PresentationToken) {
        guard token.shouldAnimate,
              generation == token.generation,
              state == .appearing
        else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = token.reduceMotion ? 0.12 : 0.20
            context.timingFunction = Self.timingFunction
            panel.animator().alphaValue = 1
            if !token.reduceMotion {
                surface?.animateReveal(duration: context.duration)
                surface?.animateContentAlpha(to: 1)
            }
        } completionHandler: {
            Task { @MainActor [weak self, weak panel] in
                guard let self,
                      self.generation == token.generation,
                      self.state == .appearing,
                      panel?.isVisible == true
                else { return }
                self.state = TopNotchPresentationStateMachine.transition(self.state, event: .appearanceFinished)
            }
        }
    }

    func dismiss(
        panel: NSPanel,
        compactRect: CGRect,
        reduceMotion: Bool,
        completion: @escaping () -> Void = {}
    ) {
        guard state != .dismissing else { return }
        generation &+= 1
        let dismissalGeneration = generation
        state = TopNotchPresentationStateMachine.transition(state, event: .dismiss)
        guard panel.isVisible, panel.alphaValue > 0.001 else {
            panel.orderOut(nil)
            restore(panel: panel)
            state = .hidden
            completion()
            return
        }

        panel.ignoresMouseEvents = true
        let duration = reduceMotion ? 0.10 : 0.16
        if !reduceMotion {
            surface?.animateDismiss(to: compactRect, duration: duration)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = Self.timingFunction
            if reduceMotion {
                panel.animator().alphaValue = 0
            } else {
                surface?.animateContentAlpha(to: 0)
            }
        } completionHandler: {
            Task { @MainActor [weak self, weak panel] in
                guard let self,
                      let panel,
                      self.generation == dismissalGeneration,
                      self.state == .dismissing
                else { return }
                panel.orderOut(nil)
                self.restore(panel: panel)
                self.state = TopNotchPresentationStateMachine.transition(self.state, event: .dismissalFinished)
                completion()
            }
        }
    }

    func restore(panel: NSPanel?) {
        panel?.alphaValue = 1
        panel?.ignoresMouseEvents = false
        surface?.restoreExpandedPresentation()
    }

    func close(panel: NSPanel?) {
        generation &+= 1
        restore(panel: panel)
        state = .hidden
    }

    private static var timingFunction: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
    }
}

/// Narrow AppKit boundary for deciding which display owns a temporary panel.
protocol PanelScreenProviding: AnyObject {
    func currentVisibleFrame() -> NSRect
}

final class SystemPanelScreenProvider: PanelScreenProviding {
    func currentVisibleFrame() -> NSRect {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? .zero
    }

}

enum HistoryPanelKeyAction: Equatable {
    case moveSelection(by: Int)
    case pasteSelection
    case pasteSelectionAsPlainText
    case close
}

enum HistoryPanelDismissalIntent: Equatable {
    case explicit
    case passive
}

struct HistoryPanelDismissalExecutor {
    let cancelPaste: () -> Void
    let hide: (@escaping () -> Void) -> Void
    let restoreFocus: () -> Void

    func execute(_ intent: HistoryPanelDismissalIntent) {
        if intent == .explicit {
            cancelPaste()
        }
        hide {
            if intent == .explicit {
                restoreFocus()
            }
        }
    }
}

enum HistoryPanelPhysicalKey: Equatable {
    case up
    case down
    case left
    case right
    case enter
    case escape
    case other
}

struct HistoryPanelKeyEvent: Equatable {
    let key: HistoryPanelPhysicalKey
    let hasDisallowedModifiers: Bool
    let hasShiftModifier: Bool
    let isRepeat: Bool

    init(
        key: HistoryPanelPhysicalKey,
        hasDisallowedModifiers: Bool,
        hasShiftModifier: Bool = false,
        isRepeat: Bool
    ) {
        self.key = key
        self.hasDisallowedModifiers = hasDisallowedModifiers
        self.hasShiftModifier = hasShiftModifier
        self.isRepeat = isRepeat
    }

    init(event: NSEvent) {
        let key: HistoryPanelPhysicalKey = switch event.keyCode {
        case 126: .up
        case 125: .down
        case 123: .left
        case 124: .right
        case 36, 76: .enter
        case 53: .escape
        default: .other
        }
        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        self.init(
            key: key,
            hasDisallowedModifiers: !event.modifierFlags.intersection(disallowedModifiers).isEmpty,
            hasShiftModifier: event.modifierFlags.contains(.shift),
            isRepeat: event.isARepeat
        )
    }
}

enum HistoryPanelSelectionAxis: Equatable {
    case vertical
    case horizontal
}

enum HistoryPanelKeyAdmission {
    static func action(
        for event: HistoryPanelKeyEvent,
        isEventInKeyHistoryWindow: Bool,
        selectionAxis: HistoryPanelSelectionAxis = .vertical
    ) -> HistoryPanelKeyAction? {
        guard isEventInKeyHistoryWindow else { return nil }
        switch event.key {
        case .up where selectionAxis == .vertical && !event.hasDisallowedModifiers,
             .left where selectionAxis == .horizontal && !event.hasDisallowedModifiers:
            return .moveSelection(by: -1)
        case .down where selectionAxis == .vertical && !event.hasDisallowedModifiers,
             .right where selectionAxis == .horizontal && !event.hasDisallowedModifiers:
            return .moveSelection(by: 1)
        case .enter where !event.isRepeat && !event.hasDisallowedModifiers:
            return event.hasShiftModifier ? .pasteSelectionAsPlainText : .pasteSelection
        case .escape where !event.isRepeat:
            return .close
        case .up, .down, .left, .right, .enter, .escape, .other:
            return nil
        }
    }
}

enum HistoryPanelOutsideClickAdmission {
    static func shouldDismiss(isPanelVisible: Bool, isInsideHistoryPanel: Bool) -> Bool {
        isPanelVisible && !isInsideHistoryPanel
    }
}

private final class HistoryPanelKeyboardMonitor {
    private weak var panel: NSPanel?
    private var monitor: Any?
    private let selectionAxis: HistoryPanelSelectionAxis
    private let handle: (HistoryPanelKeyAction) -> Bool

    init(
        panel: NSPanel,
        selectionAxis: HistoryPanelSelectionAxis,
        handle: @escaping (HistoryPanelKeyAction) -> Bool
    ) {
        self.panel = panel
        self.selectionAxis = selectionAxis
        self.handle = handle
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.process(event) ?? event
        }
    }

    deinit {
        invalidate()
    }

    func invalidate() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    private func process(_ event: NSEvent) -> NSEvent? {
        guard let panel else { return event }
        let isEventInKeyHistoryWindow = event.window === panel && panel.isKeyWindow
        guard let action = HistoryPanelKeyAdmission.action(
            for: HistoryPanelKeyEvent(event: event),
            isEventInKeyHistoryWindow: isEventInKeyHistoryWindow,
            selectionAxis: selectionAxis
        ) else {
            return event
        }
        return handle(action) ? nil : event
    }
}

private final class HistoryPanelOutsideClickMonitor {
    private weak var panel: NSPanel?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private let handleOutsideClick: @MainActor () -> Void

    init(panel: NSPanel, handleOutsideClick: @escaping @MainActor () -> Void) {
        self.panel = panel
        self.handleOutsideClick = handleOutsideClick
        let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self] event in
            self?.processLocal(event)
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self] _ in
            self?.processGlobal()
        }
    }

    deinit {
        invalidate()
    }

    func invalidate() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }

    private func processLocal(_ event: NSEvent) {
        guard let panel else { return }
        let isInsideHistoryPanel = event.window === panel
            || panel.frame.contains(NSEvent.mouseLocation)
        guard
              HistoryPanelOutsideClickAdmission.shouldDismiss(
                  isPanelVisible: panel.isVisible,
                  isInsideHistoryPanel: isInsideHistoryPanel
              )
        else { return }
        Task { @MainActor [handleOutsideClick] in
            handleOutsideClick()
        }
    }

    private func processGlobal() {
        Task { @MainActor [weak panel, handleOutsideClick] in
            guard let panel,
                  HistoryPanelOutsideClickAdmission.shouldDismiss(
                      isPanelVisible: panel.isVisible,
                      isInsideHistoryPanel: panel.frame.contains(NSEvent.mouseLocation)
                  )
            else { return }
            handleOutsideClick()
        }
    }
}

@MainActor
private final class HistoryPanelDelegate: NSObject, NSWindowDelegate {
    private let cancel: () -> Void
    private let passiveDismiss: () -> Void
    private let didBecomeKey: () -> Void

    init(
        cancel: @escaping () -> Void,
        passiveDismiss: @escaping () -> Void,
        didBecomeKey: @escaping () -> Void
    ) {
        self.cancel = cancel
        self.passiveDismiss = passiveDismiss
        self.didBecomeKey = didBecomeKey
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        cancel()
        return false
    }

    func windowDidBecomeKey(_ notification: Notification) {
        didBecomeKey()
    }

    func windowDidResignKey(_ notification: Notification) {
        passiveDismiss()
    }
}

private final class TopNotchPasteStackPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class TopNotchHistoryPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

@MainActor
private final class StackPanelDelegate: NSObject, NSWindowDelegate {
    private let cancel: () -> Void

    init(cancel: @escaping () -> Void) {
        self.cancel = cancel
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        cancel()
        return false
    }

}

@MainActor
protocol QipliApplicationActivating: AnyObject {
    var isActive: Bool { get }
    func requestActivation()
    /// This path is used only for an explicit Qipli command that opens a keyboard-driven panel.
    func requestUserInitiatedActivation()
}

@MainActor
final class SystemQipliApplicationActivator: QipliApplicationActivating {
    var isActive: Bool { NSApp.isActive }

    func requestActivation() {
        NSApp.activate()
    }

    func requestUserInitiatedActivation() {
        StrongUserInitiatedActivation.request()
    }
}

/// Isolates the only legacy activation call. The command was explicitly initiated
/// from Qipli's menu or global hotkey, so stealing focus is necessary for its
/// keyboard-first History surface to work.
private enum StrongUserInitiatedActivation {
    static func request() {
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Requests AppKit activation and performs an optional active-only follow-up.
///
/// Panel visibility is deliberately outside this bounded check: activation is
/// cooperative and may not be accepted by the system immediately.
@MainActor
final class PanelActivationPresenter {
    private let application: QipliApplicationActivating
    private let scheduleNextMainRunLoop: (@escaping () -> Void) -> Void
    private let maximumChecks: Int

    init(
        application: QipliApplicationActivating,
        maximumChecks: Int = 3,
        scheduleNextMainRunLoop: @escaping (@escaping () -> Void) -> Void = { action in
            RunLoop.main.perform(inModes: [.common]) { action() }
        }
    ) {
        self.application = application
        self.maximumChecks = maximumChecks
        self.scheduleNextMainRunLoop = scheduleNextMainRunLoop
    }

    /// Runs `present` before the requested activation path. The second closure is
    /// only for work that requires Qipli to be active.
    func presentImmediatelyThenWhenActive(
        requiresStrongUserActivation: Bool,
        present: @escaping () -> Void,
        whenActive: @escaping () -> Void
    ) {
        present()
        if requiresStrongUserActivation {
            application.requestUserInitiatedActivation()
        } else {
            application.requestActivation()
        }
        performWhenActive(remainingChecks: maximumChecks, action: whenActive)
    }

    private func performWhenActive(remainingChecks: Int, action: @escaping () -> Void) {
        guard !application.isActive else {
            action()
            return
        }
        guard remainingChecks > 1 else { return }
        scheduleNextMainRunLoop { [weak self] in
            self?.performWhenActive(remainingChecks: remainingChecks - 1, action: action)
        }
    }
}
