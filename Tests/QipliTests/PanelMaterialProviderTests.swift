import AppKit
import XCTest
@testable import Qipli

@MainActor
final class PanelMaterialProviderTests: XCTestCase {
    func testInjectedCapabilitiesSelectExpectedBackend() {
        XCTAssertEqual(
            PanelMaterialProvider(capabilities: FixedPanelMaterialCapabilities(supportsLiquidGlass: false)).configuration.backend,
            .visualEffectPopover
        )
        XCTAssertEqual(
            PanelMaterialProvider(capabilities: FixedPanelMaterialCapabilities(supportsLiquidGlass: true)).configuration.backend,
            .liquidGlassRegular
        )
    }

    func testFallbackSurfaceUsesOneSemanticVisualEffectContainer() {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 80, height: 40))
        let provider = PanelMaterialProvider(
            capabilities: FixedPanelMaterialCapabilities(supportsLiquidGlass: false)
        )

        let surface = try! XCTUnwrap(provider.makeSurface(wrapping: content) as? NSVisualEffectView)

        XCTAssertEqual(surface.material, .popover)
        XCTAssertEqual(surface.blendingMode, .behindWindow)
        XCTAssertEqual(surface.state, .followsWindowActiveState)
        XCTAssertEqual(surface.subviews.count, 1)
        XCTAssertTrue(surface.subviews.first === content)
    }

    func testGlassSurfaceUsesRegularStyleWhenRuntimeSupportsIt() throws {
        guard #available(macOS 26.0, *) else {
            throw XCTSkip("NSGlassEffectView is unavailable before macOS 26")
        }
        let content = NSView()
        let provider = PanelMaterialProvider(
            capabilities: FixedPanelMaterialCapabilities(supportsLiquidGlass: true)
        )

        let surface = try XCTUnwrap(provider.makeSurface(wrapping: content) as? NSGlassEffectView)

        XCTAssertEqual(surface.style, .regular)
        XCTAssertTrue(surface.contentView === content)
    }

    func testInstalledMaterialFillsPanelWhileContentRespectsContentLayoutRect() {
        let configuration = PanelWindowConfiguration.make(for: .history)
        let panel = NSPanel(
            contentRect: configuration.contentRect,
            styleMask: configuration.styleMask,
            backing: .buffered,
            defer: false
        )
        configuration.applyPresentation(to: panel)
        let content = NSView()
        let provider = PanelMaterialProvider(
            capabilities: FixedPanelMaterialCapabilities(supportsLiquidGlass: false)
        )

        let surface = provider.install(content: content, in: panel)
        panel.layoutIfNeeded()

        XCTAssertTrue(panel.contentView === surface)
        XCTAssertEqual(surface.bounds.size, panel.contentView?.bounds.size)
        XCTAssertEqual(content.frame, panel.contentLayoutRect)
        XCTAssertEqual(panel.contentLayoutRect.size, configuration.contentRect.size)
        XCTAssertGreaterThan(surface.bounds.height, content.frame.height)
    }

    func testPermissionPanelKeepsCompactContentLayoutRectInsideNativeTitleBar() {
        let configuration = PanelWindowConfiguration.make(for: .permission)
        let panel = NSPanel(
            contentRect: configuration.contentRect,
            styleMask: configuration.styleMask,
            backing: .buffered,
            defer: false
        )
        configuration.applyPresentation(to: panel)
        let content = NSView()
        let provider = PanelMaterialProvider(
            capabilities: FixedPanelMaterialCapabilities(supportsLiquidGlass: false)
        )

        _ = provider.install(content: content, in: panel)
        panel.layoutIfNeeded()

        XCTAssertEqual(configuration.contentRect.size, NSSize(width: 360, height: 150))
        XCTAssertEqual(panel.contentLayoutRect.size, configuration.contentRect.size)
        XCTAssertEqual(content.frame, panel.contentLayoutRect)
    }

    func testPermissionPresentationMapsEachStateToOneRelevantAction() {
        XCTAssertEqual(
            PermissionPanelPresentation.resolve(state: .notRequested),
            .init(
                message: "Enable Accessibility for global shortcuts and paste.",
                buttonTitle: "Allow Access",
                accessibilityLabel: "Allow Accessibility Access",
                action: .requestAccess
            )
        )
        XCTAssertEqual(
            PermissionPanelPresentation.resolve(state: .denied),
            .init(
                message: "Accessibility access is off.",
                buttonTitle: "Open System Settings",
                accessibilityLabel: "Open System Settings",
                action: .openSettings
            )
        )
        XCTAssertEqual(
            PermissionPanelPresentation.resolve(state: .granted),
            .init(
                message: "Accessibility access is enabled.",
                buttonTitle: "Open System Settings",
                accessibilityLabel: "Open System Settings",
                action: .openSettings
            )
        )
    }

    func testWindowConfigurationsPreservePanelContractsAndAddOnlySystemPresentation() {
        let expectedTitles: [PanelKind: String] = [
            .history: "History",
            .pasteStack: "Paste Stack",
            .permission: "Accessibility Permission"
        ]

        for kind in PanelKind.allCases {
            let configuration = PanelWindowConfiguration.make(for: kind)
            let panel = NSPanel(
                contentRect: configuration.contentRect,
                styleMask: configuration.styleMask,
                backing: .buffered,
                defer: false
            )
            configuration.applyPresentation(to: panel)

            XCTAssertEqual(panel.title, expectedTitles[kind])
            XCTAssertTrue(panel.styleMask.contains(.titled))
            XCTAssertTrue(panel.styleMask.contains(.closable))
            XCTAssertTrue(panel.styleMask.contains(.utilityWindow))
            XCTAssertTrue(panel.styleMask.contains(.fullSizeContentView))
            XCTAssertTrue(panel.isFloatingPanel)
            XCTAssertEqual(panel.level, .floating)
            XCTAssertEqual(panel.collectionBehavior, [.canJoinAllSpaces, .fullScreenAuxiliary])
            XCTAssertFalse(panel.hidesOnDeactivate)
            XCTAssertFalse(panel.isOpaque)
            XCTAssertTrue(panel.titlebarAppearsTransparent)
        }

        XCTAssertFalse(PanelWindowConfiguration.make(for: .history).styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(PanelWindowConfiguration.make(for: .pasteStack).styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(PanelWindowConfiguration.make(for: .permission).styleMask.contains(.nonactivatingPanel))
        XCTAssertEqual(PanelWindowConfiguration.make(for: .history).contentRect.size, NSSize(width: 460, height: 340))
        XCTAssertEqual(PanelWindowConfiguration.make(for: .pasteStack).contentRect.size, NSSize(width: 400, height: 360))
        XCTAssertEqual(PanelWindowConfiguration.make(for: .permission).contentRect.size, NSSize(width: 360, height: 150))
    }
}

private struct FixedPanelMaterialCapabilities: PanelMaterialCapabilityProviding {
    let supportsLiquidGlass: Bool
}
