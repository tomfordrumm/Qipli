import AppKit
import SwiftUI

/// Maintains one AppKit panel per temporary surface; reopening a surface reuses its panel.
final class PanelController {
    private let permissionService: AccessibilityPermissionService
    private var historyPanel: NSPanel?
    private var stackPanel: NSPanel?
    private var permissionPanel: NSPanel?

    init(permissionService: AccessibilityPermissionService) {
        self.permissionService = permissionService
    }

    func showHistory() {
        let panel = historyPanel ?? makePanel(title: "History") {
            HistoryPlaceholderView()
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

    private func makePanel<Content: View>(title: String, @ViewBuilder content: () -> Content) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 260),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
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
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
}
