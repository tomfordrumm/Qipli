import AppKit

/// Runtime capability boundary kept separate from panel lifecycle and feature state.
protocol PanelMaterialCapabilityProviding {
    var supportsLiquidGlass: Bool { get }
}

struct SystemPanelMaterialCapabilities: PanelMaterialCapabilityProviding {
    var supportsLiquidGlass: Bool {
        if #available(macOS 26.0, *) {
            true
        } else {
            false
        }
    }
}

enum PanelMaterialBackend: Equatable {
    case liquidGlassRegular
    case visualEffectPopover
}

/// Describes the system-owned effect selected for a panel without exposing its content.
struct PanelMaterialConfiguration: Equatable {
    let backend: PanelMaterialBackend

    static func resolve(capabilities: any PanelMaterialCapabilityProviding) -> Self {
        Self(backend: capabilities.supportsLiquidGlass ? .liquidGlassRegular : .visualEffectPopover)
    }
}

/// Owns exactly one outer material view per panel and nothing about panel behavior.
@MainActor
final class PanelMaterialProvider {
    private let capabilities: any PanelMaterialCapabilityProviding

    init(capabilities: any PanelMaterialCapabilityProviding = SystemPanelMaterialCapabilities()) {
        self.capabilities = capabilities
    }

    var configuration: PanelMaterialConfiguration {
        PanelMaterialConfiguration.resolve(capabilities: capabilities)
    }

    func makeSurface(wrapping content: NSView) -> NSView {
        switch configuration.backend {
        case .liquidGlassRegular:
            if #available(macOS 26.0, *) {
                let glass = NSGlassEffectView()
                glass.style = .regular
                glass.contentView = content
                return glass
            }
            // A test double may request glass on an older runtime. Never touch an
            // unavailable symbol there; use the same semantic fallback instead.
            return makeVisualEffectSurface(wrapping: content)
        case .visualEffectPopover:
            return makeVisualEffectSurface(wrapping: content)
        }
    }

    /// Installs one full-size material surface behind the native title bar while
    /// pinning SwiftUI content to the window's safe content layout rect.
    @discardableResult
    func install(content: NSView, in panel: NSPanel) -> NSView {
        let contentContainer = NSView()
        let surface = makeSurface(wrapping: contentContainer)
        panel.contentView = surface

        content.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(content)
        guard let contentLayoutGuide = panel.contentLayoutGuide as? NSLayoutGuide else {
            preconditionFailure("Titled Qipli panels require NSWindow.contentLayoutGuide")
        }
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            content.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor)
        ])
        return surface
    }

    private func makeVisualEffectSurface(wrapping content: NSView) -> NSVisualEffectView {
        let material = NSVisualEffectView()
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .followsWindowActiveState
        content.frame = material.bounds
        content.autoresizingMask = [.width, .height]
        material.addSubview(content)
        return material
    }
}

enum PanelKind: CaseIterable {
    case history
    case pasteStack
    case permission
}

/// Explicitly preserves each panel's pre-S009 AppKit contract while allowing
/// the content view itself to become an adaptive material surface.
struct PanelWindowConfiguration {
    let title: String
    let contentRect: NSRect
    let styleMask: NSWindow.StyleMask

    static func make(for kind: PanelKind) -> Self {
        switch kind {
        case .history:
            Self(
                title: "History",
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 340),
                styleMask: [.titled, .closable, .utilityWindow, .fullSizeContentView]
            )
        case .pasteStack:
            Self(
                title: "Paste Stack",
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 360),
                styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel, .fullSizeContentView]
            )
        case .permission:
            Self(
                title: "Accessibility Permission",
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 150),
                styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel, .fullSizeContentView]
            )
        }
    }

    func applyPresentation(to panel: NSPanel) {
        panel.title = title
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        // `.fullSizeContentView` puts the material behind native titled/closable
        // chrome; content itself is constrained to `contentLayoutGuide` above.
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.titlebarAppearsTransparent = true
        // `contentRect` is the feature-owned SwiftUI size. Full-size content
        // extends the material under native chrome, so compensate for that
        // chrome before pinning SwiftUI to the unobscured layout rect.
        let titleBarHeight = panel.contentView!.bounds.height - panel.contentLayoutRect.height
        panel.setContentSize(NSSize(
            width: contentRect.width,
            height: contentRect.height + titleBarHeight
        ))
    }
}
