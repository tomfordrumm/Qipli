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
    private let openAccessibilitySettings: () -> Void
    private let activationPresenter: PanelActivationPresenter
    private var historyPanel: NSPanel?
    private var stackPanel: NSPanel?
    private var permissionPanel: NSPanel?
    private var historyPasteTarget: HistoryPasteTarget?
    private var stackPanelCloseDelegate: StackPanelCloseDelegate?

    /// The shell uses this only to refresh its Start/Cancel menu title.
    var onPasteStackCancelled: (() -> Void)?

    init(
        permissionService: AccessibilityPermissionService,
        historyViewModel: HistoryViewModel,
        stackSessionController: StackSessionController,
        historyPasteExecutor: HistoryPasteExecutor,
        frontmostApplicationCapture: FrontmostApplicationCapturing = SystemFrontmostApplicationCapture(),
        screenProvider: PanelScreenProviding = SystemPanelScreenProvider(),
        applicationActivator: QipliApplicationActivating? = nil,
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
        self.openAccessibilitySettings = openAccessibilitySettings
        let resolvedApplicationActivator = applicationActivator ?? SystemQipliApplicationActivator()
        activationPresenter = PanelActivationPresenter(
            application: resolvedApplicationActivator,
            scheduleNextMainRunLoop: activationScheduler
        )
    }

    func showHistory() {
        _ = permissionService.refresh()
        let isFreshPresentation = historyPanel?.isVisible != true
        if isFreshPresentation {
            historyPasteTarget = frontmostApplicationCapture.capturePriorApplication()
        }
        historyViewModel.prepareForPresentation()
        let panel = historyPanel ?? makePanel(title: "History", acceptsKeyboardInput: true) {
            HistoryPanelView(
                viewModel: self.historyViewModel,
                permissionService: self.permissionService,
                openAccessibilitySettings: self.openAccessibilitySettings,
                pasteSelection: { [weak self] in self?.pasteSelectedHistoryEntry() },
                close: { [weak self] in self?.cancelHistory() }
            )
        }
        historyPanel = panel
        present(
            panel,
            requestSearchFocus: true,
            requestHistoryViewportReset: isFreshPresentation,
            requiresStrongUserActivation: true
        )
    }

    func showPasteStack() {
        let panel = stackPanel ?? makeStackPanel {
            PasteStackPanelView(
                sessionController: self.stackSessionController,
                cancel: { [weak self] in self?.cancelPasteStack() }
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

    func showPermission(requestAccess: @escaping () -> Void, openSettings: @escaping () -> Void) {
        let panel = permissionPanel ?? makePanel(title: "Accessibility Permission") {
            PermissionStatusView(
                permissionService: self.permissionService,
                requestAccess: requestAccess,
                openSettings: openSettings
            )
        }
        permissionPanel = panel
        present(panel)
    }

    func closeAll() {
        cancelPasteStack()
        [historyPanel, stackPanel, permissionPanel].forEach { $0?.close() }
    }

    private func pasteSelectedHistoryEntry() {
        guard let entry = historyViewModel.selectedEntry else { return }
        historyViewModel.clearPasteFailure()
        historyPasteExecutor.paste(
            entry: entry,
            target: historyPasteTarget,
            closePanel: { [weak self] in self?.dismissHistoryForPaste() },
            completion: { [weak self] result in
                switch result {
                case .success:
                    self?.historyViewModel.markUsedAfterSuccessfulPaste(id: entry.id)
                case let .failure(failure):
                    self?.historyViewModel.recordPasteFailure(failure)
                    self?.reopenHistoryAfterPasteFailure()
                }
            }
        )
    }

    private func dismissHistoryForPaste() {
        historyPanel?.orderOut(nil)
    }

    private func cancelHistory() {
        historyPanel?.orderOut(nil)
        _ = HistoryFocusRestorer.returnToCapturedTarget(historyPasteTarget)
    }

    private func reopenHistoryAfterPasteFailure() {
        guard let historyPanel, !historyPanel.isVisible else { return }
        present(historyPanel, requestSearchFocus: true, requiresStrongUserActivation: true)
    }

    private func makePanel<Content: View>(
        title: String,
        acceptsKeyboardInput: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> NSPanel {
        var styleMask: NSWindow.StyleMask = [.titled, .closable, .utilityWindow]
        if !acceptsKeyboardInput {
            styleMask.insert(.nonactivatingPanel)
        }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 260),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: content())
        return panel
    }

    private func makeStackPanel<Content: View>(@ViewBuilder content: () -> Content) -> NSPanel {
        let panel = NonActivatingStackPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 360),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Paste Stack"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: content())

        let closeDelegate = StackPanelCloseDelegate { [weak self] in
            self?.cancelPasteStack()
        }
        panel.delegate = closeDelegate
        stackPanelCloseDelegate = closeDelegate
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
        panel.setFrameOrigin(
            FloatingPanelPlacement.origin(
                panelSize: panel.frame.size,
                visibleFrame: screenProvider.currentVisibleFrame()
            )
        )
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

enum FloatingPanelPlacement {
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

private final class NonActivatingStackPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class StackPanelCloseDelegate: NSObject, NSWindowDelegate {
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
