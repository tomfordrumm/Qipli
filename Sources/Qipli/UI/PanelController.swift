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
    private let pasteStackPositionStore: PasteStackPanelPositionStoring
    private let openAccessibilitySettings: () -> Void
    private let activationPresenter: PanelActivationPresenter
    private let materialProvider: PanelMaterialProvider
    private let historyTableInteractionBridge = HistoryTableInteractionBridge()
    private var historyPanel: NSPanel?
    private var stackPanel: NSPanel?
    private var historyPasteTarget: HistoryPasteTarget?
    private var historyPasteTransactionID: UUID?
    private var historyPanelDelegate: HistoryPanelDelegate?
    private var historyKeyboardMonitor: HistoryPanelKeyboardMonitor?
    private var historyOutsideClickMonitor: HistoryPanelOutsideClickMonitor?
    private var stackPanelDelegate: StackPanelDelegate?

    /// The shell uses this only to refresh its Start/Cancel menu title.
    var onPasteStackCancelled: (() -> Void)?

    init(
        permissionService: AccessibilityPermissionService,
        historyViewModel: HistoryViewModel,
        stackSessionController: StackSessionController,
        historyPasteExecutor: HistoryPasteExecutor,
        frontmostApplicationCapture: FrontmostApplicationCapturing = SystemFrontmostApplicationCapture(),
        screenProvider: PanelScreenProviding = SystemPanelScreenProvider(),
        pasteStackPositionStore: PasteStackPanelPositionStoring = PasteStackPanelPositionStore(),
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
        self.pasteStackPositionStore = pasteStackPositionStore
        self.openAccessibilitySettings = openAccessibilitySettings
        self.materialProvider = materialProvider ?? PanelMaterialProvider()
        let resolvedApplicationActivator = applicationActivator ?? SystemQipliApplicationActivator()
        activationPresenter = PanelActivationPresenter(
            application: resolvedApplicationActivator,
            scheduleNextMainRunLoop: activationScheduler
        )
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
        historyTableInteractionBridge.applySnapshot(
            entries: historyViewModel.visibleEntries,
            revision: historyViewModel.visibleSnapshotRevision,
            selectedEntryID: historyViewModel.selectedEntryID,
            resetViewport: false
        )
        let panel: NSPanel
        if let historyPanel {
            panel = historyPanel
        } else {
            panel = makeHistoryPanel()
        }
        historyPanel = panel
        present(
            panel,
            requestSearchFocus: true,
            requestHistoryViewportReset: isFreshPresentation,
            requiresStrongUserActivation: true
        )
    }

    /// Builds the reusable History surface after startup data has loaded so the
    /// first user invocation does not pay SwiftUI/AppKit construction cost.
    func prepareHistoryPanel() {
        guard historyPanel == nil else { return }
        historyPanel = makeHistoryPanel()
    }

    func showPasteStack() {
        let panel = stackPanel ?? makeStackPanel {
            PasteStackPanelView(
                sessionController: self.stackSessionController,
                close: { [weak self] in self?.cancelPasteStack() }
            )
        }
        stackPanel = panel
        present(panel, activatesApplication: false, placeOnCurrentScreen: true)
    }

    func cancelPasteStack() {
        stackSessionController.cancel()
        stackPanel?.orderOut(nil)
        onPasteStackCancelled?()
    }

    /// S006 has already published the all-used state before this deferred
    /// presentation cleanup. Do not reactivate the former target here.
    func finishPasteStackAfterCompletion() {
        stackPanel?.orderOut(nil)
        onPasteStackCancelled?()
    }

    func closeAll() {
        cancelHistoryPasteTransaction()
        cancelPasteStack()
        historyPanel?.delegate = nil
        [historyPanel, stackPanel].forEach { $0?.close() }
    }

    private func pasteHistoryEntry(_ entry: HistoryEntry) {
        guard historyPasteTransactionID == nil else { return }
        let transactionID = UUID()
        historyPasteTransactionID = transactionID
        let started = historyPasteExecutor.paste(
            entry: entry,
            target: historyPasteTarget,
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
            hide: { [weak self] in self?.hideHistoryPanel() },
            restoreFocus: { [weak self] in
                _ = HistoryFocusRestorer.returnToCapturedTarget(self?.historyPasteTarget)
            }
        )
        .execute(intent)
    }

    private func cancelHistoryPasteTransaction() {
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
        present(historyPanel, requestSearchFocus: true, requiresStrongUserActivation: true)
    }

    private func hideHistoryPanel() {
        historyPanel?.orderOut(nil)
        restoreHistoryPanelPresentation()
    }

    private func restoreHistoryPanelPresentation() {
        historyPanel?.alphaValue = 1
        historyPanel?.ignoresMouseEvents = false
    }

    private func makePanel<Content: View>(
        kind: PanelKind,
        @ViewBuilder content: () -> Content
    ) -> NSPanel {
        let configuration = PanelWindowConfiguration.make(for: kind)
        let panel = NSPanel(
            contentRect: configuration.contentRect,
            styleMask: configuration.styleMask,
            backing: .buffered,
            defer: false
        )
        configuration.applyPresentation(to: panel)
        let surface = materialProvider.install(content: NSHostingView(rootView: content()), in: panel)
        configuration.applySurfacePresentation(to: surface)

        switch kind {
        case .history:
            let panelDelegate = HistoryPanelDelegate(
                cancel: { [weak self] in self?.cancelHistory() },
                passiveDismiss: { [weak self] in self?.passiveDismissHistory() },
                didBecomeKey: { [weak self] in self?.historyViewModel.requestSearchFocus() }
            )
            panel.delegate = panelDelegate
            historyPanelDelegate = panelDelegate
            historyKeyboardMonitor = HistoryPanelKeyboardMonitor(panel: panel) { [weak self] action in
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
        makePanel(kind: .history) {
            HistoryPanelView(
                viewModel: self.historyViewModel,
                permissionService: self.permissionService,
                openAccessibilitySettings: self.openAccessibilitySettings,
                pasteEntry: { [weak self] entry in self?.pasteHistoryEntry(entry) },
                close: { [weak self] in self?.cancelHistory() },
                tableInteractionBridge: self.historyTableInteractionBridge
            )
        }
    }

    private func handleHistoryKeyAction(_ action: HistoryPanelKeyAction) -> Bool {
        if action == .pasteSelection {
            if historyPasteTransactionID != nil || historyViewModel.isPasteInProgress {
                return true
            }
            guard permissionService.state == .granted else {
                return false
            }
        }

        return HistoryPanelKeyActionExecutor(
            moveSelection: { [weak self] offset in
                guard let self else { return }
                self.historyViewModel.moveSelection(by: offset)
                self.historyTableInteractionBridge.applySelection(
                    id: self.historyViewModel.selectedEntryID
                )
            },
            selectedEntry: { [weak self] in self?.historyViewModel.selectedEntry },
            pasteEntry: { [weak self] entry in
                self?.pasteHistoryEntry(entry)
            },
            close: { [weak self] in
                RunLoop.main.perform(inModes: [.common]) { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.cancelHistory()
                    }
                }
            }
        )
        .execute(action)
    }

    private func makeStackPanel<Content: View>(@ViewBuilder content: () -> Content) -> NSPanel {
        let configuration = PanelWindowConfiguration.make(for: .pasteStack)
        let panel = NonActivatingStackPanel(
            contentRect: configuration.contentRect,
            styleMask: configuration.styleMask,
            backing: .buffered,
            defer: false
        )
        configuration.applyPresentation(to: panel)
        let surface = materialProvider.install(content: NSHostingView(rootView: content()), in: panel)
        configuration.applySurfacePresentation(to: surface)

        let panelDelegate = StackPanelDelegate(
            cancel: { [weak self] in
                self?.cancelPasteStack()
            },
            didMove: { [weak self] origin in
                self?.pasteStackPositionStore.save(origin: origin)
            }
        )
        panel.delegate = panelDelegate
        stackPanelDelegate = panelDelegate
        return panel
    }

    private func present(
        _ panel: NSPanel,
        requestSearchFocus: Bool = false,
        requestHistoryViewportReset: Bool = false,
        requiresStrongUserActivation: Bool = false,
        activatesApplication: Bool = true,
        placeOnCurrentScreen: Bool = false
    ) {
        if placeOnCurrentScreen {
            place(panel)
        } else {
            panel.center()
        }
        guard activatesApplication else {
            panel.orderFrontRegardless()
            return
        }
        // `NSApplication.activate()` is an asynchronous, best-effort request. The
        // panel must still be visible if activation is denied or delayed, so order
        // it before waiting for the active-only keyboard follow-up.
        activationPresenter.presentImmediatelyThenWhenActive(
            requiresStrongUserActivation: requiresStrongUserActivation,
            present: { [weak self, weak panel] in
                panel?.makeKeyAndOrderFront(nil)
                if requestHistoryViewportReset {
                    self?.historyViewModel.requestPresentationViewportReset()
                    self?.historyTableInteractionBridge.applySelection(
                        id: self?.historyViewModel.selectedEntryID,
                        resetViewport: true
                    )
                }
            },
            whenActive: { [weak self, weak panel] in
                guard let panel else { return }
                panel.makeKey()
                if requestSearchFocus {
                    panel.makeFirstResponder(nil)
                    self?.historyViewModel.requestSearchFocus()
                }
            }
        )
    }

    private func place(_ panel: NSPanel) {
        let origin = FloatingPanelPlacement.restoredOrigin(
            savedOrigin: pasteStackPositionStore.savedOrigin,
            panelSize: panel.frame.size,
            availableVisibleFrames: screenProvider.availableVisibleFrames(),
            fallbackVisibleFrame: screenProvider.currentVisibleFrame()
        )
        panel.setFrameOrigin(origin)
        pasteStackPositionStore.save(origin: origin)
    }
}

protocol PasteStackPanelPositionStoring: AnyObject {
    var savedOrigin: NSPoint? { get }
    func save(origin: NSPoint)
}

final class PasteStackPanelPositionStore: PasteStackPanelPositionStoring {
    static let defaultStorageKey = "qipli.pasteStackPanelOrigin"

    private let defaults: UserDefaults
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = PasteStackPanelPositionStore.defaultStorageKey
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    var savedOrigin: NSPoint? {
        guard
            let coordinates = defaults.array(forKey: storageKey),
            coordinates.count == 2,
            let x = (coordinates[0] as? NSNumber)?.doubleValue,
            let y = (coordinates[1] as? NSNumber)?.doubleValue,
            x.isFinite,
            y.isFinite
        else {
            return nil
        }
        return NSPoint(x: x, y: y)
    }

    func save(origin: NSPoint) {
        guard origin.x.isFinite, origin.y.isFinite else { return }
        defaults.set([Double(origin.x), Double(origin.y)], forKey: storageKey)
    }
}

/// Narrow AppKit boundary for deciding which display owns a temporary panel.
protocol PanelScreenProviding: AnyObject {
    func currentVisibleFrame() -> NSRect
    func availableVisibleFrames() -> [NSRect]
}

final class SystemPanelScreenProvider: PanelScreenProviding {
    func currentVisibleFrame() -> NSRect {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? .zero
    }

    func availableVisibleFrames() -> [NSRect] {
        NSScreen.screens.map(\.visibleFrame)
    }
}

enum FloatingPanelPlacement {
    static func restoredOrigin(
        savedOrigin: NSPoint?,
        panelSize: NSSize,
        availableVisibleFrames: [NSRect],
        fallbackVisibleFrame: NSRect
    ) -> NSPoint {
        if let savedOrigin {
            let savedFrame = NSRect(origin: savedOrigin, size: panelSize)
            if availableVisibleFrames.contains(where: { $0.contains(savedFrame) }) {
                return savedOrigin
            }
        }
        return origin(panelSize: panelSize, visibleFrame: fallbackVisibleFrame)
    }

    /// Centers a compact panel on the display under the mouse and clamps its
    /// origin to that display's visible frame (menu bar and Dock excluded).
    static func origin(panelSize: NSSize, visibleFrame: NSRect) -> NSPoint {
        let desired = NSPoint(
            x: visibleFrame.midX - panelSize.width / 2,
            y: visibleFrame.midY - panelSize.height / 2
        )
        return NSPoint(
            x: min(max(desired.x, visibleFrame.minX), max(visibleFrame.minX, visibleFrame.maxX - panelSize.width)),
            y: min(max(desired.y, visibleFrame.minY), max(visibleFrame.minY, visibleFrame.maxY - panelSize.height))
        )
    }
}

enum HistoryPanelKeyAction: Equatable {
    case moveSelection(by: Int)
    case pasteSelection
    case close
}

/// Applies selection changes while the AppKit key event is still being handled,
/// then snapshots the exact entry for any deferred paste side effect.
@MainActor
struct HistoryPanelKeyActionExecutor {
    let moveSelection: (Int) -> Void
    let selectedEntry: () -> HistoryEntry?
    let pasteEntry: (HistoryEntry) -> Void
    let close: () -> Void

    func execute(_ action: HistoryPanelKeyAction) -> Bool {
        switch action {
        case let .moveSelection(offset):
            moveSelection(offset)
            return true
        case .pasteSelection:
            guard let entry = selectedEntry() else { return false }
            pasteEntry(entry)
            return true
        case .close:
            close()
            return true
        }
    }
}

enum HistoryPanelDismissalIntent: Equatable {
    case explicit
    case passive
}

struct HistoryPanelDismissalExecutor {
    let cancelPaste: () -> Void
    let hide: () -> Void
    let restoreFocus: () -> Void

    func execute(_ intent: HistoryPanelDismissalIntent) {
        if intent == .explicit {
            cancelPaste()
        }
        hide()
        if intent == .explicit {
            restoreFocus()
        }
    }
}

enum HistoryPanelPhysicalKey: Equatable {
    case up
    case down
    case enter
    case escape
    case other
}

struct HistoryPanelKeyEvent: Equatable {
    let key: HistoryPanelPhysicalKey
    let hasDisallowedModifiers: Bool
    let isRepeat: Bool

    init(key: HistoryPanelPhysicalKey, hasDisallowedModifiers: Bool, isRepeat: Bool) {
        self.key = key
        self.hasDisallowedModifiers = hasDisallowedModifiers
        self.isRepeat = isRepeat
    }

    init(event: NSEvent) {
        let key: HistoryPanelPhysicalKey = switch event.keyCode {
        case 126: .up
        case 125: .down
        case 36, 76: .enter
        case 53: .escape
        default: .other
        }
        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        self.init(
            key: key,
            hasDisallowedModifiers: !event.modifierFlags.intersection(disallowedModifiers).isEmpty,
            isRepeat: event.isARepeat
        )
    }
}

enum HistoryPanelKeyAdmission {
    static func action(
        for event: HistoryPanelKeyEvent,
        isEventInKeyHistoryWindow: Bool
    ) -> HistoryPanelKeyAction? {
        guard isEventInKeyHistoryWindow, !event.hasDisallowedModifiers else { return nil }
        switch event.key {
        case .up:
            return .moveSelection(by: -1)
        case .down:
            return .moveSelection(by: 1)
        case .enter where !event.isRepeat:
            return .pasteSelection
        case .escape where !event.isRepeat:
            return .close
        case .enter, .escape, .other:
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
    private let handle: (HistoryPanelKeyAction) -> Bool

    init(panel: NSPanel, handle: @escaping (HistoryPanelKeyAction) -> Bool) {
        self.panel = panel
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
            isEventInKeyHistoryWindow: isEventInKeyHistoryWindow
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

private final class NonActivatingStackPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class StackPanelDelegate: NSObject, NSWindowDelegate {
    private let cancel: () -> Void
    private let didMove: (NSPoint) -> Void

    init(cancel: @escaping () -> Void, didMove: @escaping (NSPoint) -> Void) {
        self.cancel = cancel
        self.didMove = didMove
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        cancel()
        return false
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        didMove(window.frame.origin)
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
