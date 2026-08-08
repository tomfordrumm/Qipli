import AppKit
import SwiftUI

/// Maintains one AppKit panel per temporary surface; reopening a surface reuses its panel.
@MainActor
final class PanelController {
    private let permissionService: AccessibilityPermissionService
    private let historyViewModel: HistoryViewModel
    private let historyPasteExecutor: HistoryPasteExecutor
    private let frontmostApplicationCapture: FrontmostApplicationCapturing
    private let openAccessibilitySettings: () -> Void
    private let activationPresenter: PanelActivationPresenter
    private var historyPanel: NSPanel?
    private var stackPanel: NSPanel?
    private var permissionPanel: NSPanel?
    private var historyPasteTarget: HistoryPasteTarget?

    init(
        permissionService: AccessibilityPermissionService,
        historyViewModel: HistoryViewModel,
        historyPasteExecutor: HistoryPasteExecutor,
        frontmostApplicationCapture: FrontmostApplicationCapturing = SystemFrontmostApplicationCapture(),
        applicationActivator: QipliApplicationActivating? = nil,
        activationScheduler: @escaping (@escaping () -> Void) -> Void = { action in
            RunLoop.main.perform(inModes: [.common]) { action() }
        },
        openAccessibilitySettings: @escaping () -> Void
    ) {
        self.permissionService = permissionService
        self.historyViewModel = historyViewModel
        self.historyPasteExecutor = historyPasteExecutor
        self.frontmostApplicationCapture = frontmostApplicationCapture
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
        let panel = stackPanel ?? makePanel(title: "Paste Stack") {
            PasteStackPlaceholderView()
        }
        stackPanel = panel
        present(panel)
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

    private func present(
        _ panel: NSPanel,
        requestSearchFocus: Bool = false,
        requestHistoryViewportReset: Bool = false,
        requiresStrongUserActivation: Bool = false
    ) {
        panel.center()
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
