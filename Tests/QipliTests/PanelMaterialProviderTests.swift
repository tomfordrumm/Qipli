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

    func testWindowConfigurationsPreservePanelContractsAndAddOnlySystemPresentation() {
        let expectedTitles: [PanelKind: String] = [
            .history: "History",
            .pasteStack: "Paste Stack"
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
            XCTAssertTrue(panel.isFloatingPanel)
            XCTAssertEqual(panel.level, .floating)
            XCTAssertEqual(panel.collectionBehavior, [.canJoinAllSpaces, .fullScreenAuxiliary])
            XCTAssertFalse(panel.hidesOnDeactivate)
            XCTAssertFalse(panel.isOpaque)
            XCTAssertTrue(panel.hasShadow)
        }

        let historyConfiguration = PanelWindowConfiguration.make(for: .history)
        XCTAssertEqual(historyConfiguration.chrome, .native)
        XCTAssertTrue(historyConfiguration.styleMask.contains(.titled))
        XCTAssertTrue(historyConfiguration.styleMask.contains(.closable))
        XCTAssertTrue(historyConfiguration.styleMask.contains(.utilityWindow))
        XCTAssertTrue(historyConfiguration.styleMask.contains(.fullSizeContentView))

        let stackConfiguration = PanelWindowConfiguration.make(for: .pasteStack)
        XCTAssertEqual(stackConfiguration.chrome, .custom(cornerRadius: 18))
        XCTAssertFalse(stackConfiguration.styleMask.contains(.titled))
        XCTAssertFalse(stackConfiguration.styleMask.contains(.closable))
        XCTAssertFalse(stackConfiguration.styleMask.contains(.utilityWindow))
        XCTAssertFalse(stackConfiguration.styleMask.contains(.fullSizeContentView))
        XCTAssertFalse(PanelWindowConfiguration.make(for: .history).styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(stackConfiguration.styleMask.contains(.nonactivatingPanel))
        XCTAssertEqual(PanelWindowConfiguration.make(for: .history).contentRect.size, NSSize(width: 460, height: 340))
        XCTAssertEqual(stackConfiguration.contentRect.size, NSSize(width: 400, height: 360))
    }

    func testPasteStackCustomChromeClipsTheSingleMaterialSurface() {
        let configuration = PanelWindowConfiguration.make(for: .pasteStack)
        let panel = NSPanel(
            contentRect: configuration.contentRect,
            styleMask: configuration.styleMask,
            backing: .buffered,
            defer: false
        )
        configuration.applyPresentation(to: panel)
        let provider = PanelMaterialProvider(
            capabilities: FixedPanelMaterialCapabilities(supportsLiquidGlass: false)
        )

        let surface = provider.install(content: NSView(), in: panel)
        configuration.applySurfacePresentation(to: surface)
        panel.layoutIfNeeded()

        XCTAssertEqual(panel.contentLayoutRect.size, configuration.contentRect.size)
        XCTAssertEqual(surface.layer?.cornerRadius, 18)
        XCTAssertEqual(surface.layer?.cornerCurve, .continuous)
        XCTAssertTrue(surface.layer?.masksToBounds == true)
    }
}

private struct FixedPanelMaterialCapabilities: PanelMaterialCapabilityProviding {
    let supportsLiquidGlass: Bool
}
