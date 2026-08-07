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
    private var historyPanel: NSPanel?
    private var stackPanel: NSPanel?
    private var permissionPanel: NSPanel?
    private var historyPasteTarget: HistoryPasteTarget?

    init(
        permissionService: AccessibilityPermissionService,
        historyViewModel: HistoryViewModel,
        historyPasteExecutor: HistoryPasteExecutor,
        frontmostApplicationCapture: FrontmostApplicationCapturing = SystemFrontmostApplicationCapture(),
        openAccessibilitySettings: @escaping () -> Void
    ) {
        self.permissionService = permissionService
        self.historyViewModel = historyViewModel
        self.historyPasteExecutor = historyPasteExecutor
        self.frontmostApplicationCapture = frontmostApplicationCapture
        self.openAccessibilitySettings = openAccessibilitySettings
    }

    func showHistory() {
        _ = permissionService.refresh()
        if historyPanel?.isVisible != true {
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
        present(panel)
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
                    break
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
        guard let historyPanel else { return }
        NSApp.activate()
        historyPanel.makeKeyAndOrderFront(nil)
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

    private func present(_ panel: NSPanel) {
        panel.center()
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }
}
