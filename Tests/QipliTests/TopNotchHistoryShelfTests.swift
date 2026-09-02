import AppKit
import XCTest
@testable import Qipli

final class TopNotchHistoryShelfTests: XCTestCase {
    func testCameraSafePlacementKeepsStableTopAnchorAndFitsVisibleWidth() {
        let frame = TopNotchHistoryGeometry.frame(
            screenFrame: NSRect(x: 0, y: 0, width: 1_512, height: 982),
            visibleFrame: NSRect(x: 0, y: 0, width: 1_512, height: 950),
            safeAreaInsets: NSEdgeInsets(top: 37, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: NSRect(x: 0, y: 945, width: 586, height: 37),
            auxiliaryTopRightArea: NSRect(x: 926, y: 945, width: 586, height: 37)
        )

        XCTAssertEqual(frame.maxY, 982, accuracy: 0.001)
        XCTAssertEqual(frame.midX, 756, accuracy: 0.001)
        XCTAssertLessThanOrEqual(frame.maxX, 1_512)
        XCTAssertGreaterThanOrEqual(frame.minY, 0)
    }

    func testCameraSafePlacementCentersExpandedShelfOnAuxiliaryNotchGap() {
        let frame = TopNotchHistoryGeometry.frame(
            screenFrame: NSRect(x: 1_920, y: 78, width: 1_312, height: 848),
            visibleFrame: NSRect(x: 1_920, y: 78, width: 1_312, height: 824),
            safeAreaInsets: NSEdgeInsets(top: 24, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: NSRect(x: 1_920, y: 902, width: 586, height: 24),
            auxiliaryTopRightArea: NSRect(x: 2_646, y: 902, width: 586, height: 24)
        )

        XCTAssertEqual(frame.maxY, 926, accuracy: 0.001)
        XCTAssertEqual(frame.midX, 2_576, accuracy: 0.001)
    }

    func testNotchlessPlacementUsesMenuBarSafeVisibleFrame() {
        let frame = TopNotchHistoryGeometry.frame(
            screenFrame: NSRect(x: 100, y: 40, width: 1_000, height: 800),
            visibleFrame: NSRect(x: 100, y: 40, width: 1_000, height: 760),
            safeAreaInsets: NSEdgeInsets()
        )

        XCTAssertEqual(frame.maxY, 800, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(frame.minY, 40)
        XCTAssertGreaterThanOrEqual(frame.minX, 100)
        XCTAssertLessThanOrEqual(frame.maxX, 1_100)
    }

    func testNarrowDisplayClampsPanelWithoutHardcodedNotchDimensions() {
        let frame = TopNotchHistoryGeometry.frame(
            screenFrame: NSRect(x: -200, y: 0, width: 400, height: 300),
            visibleFrame: NSRect(x: -200, y: 0, width: 400, height: 280),
            safeAreaInsets: NSEdgeInsets(top: 20, left: 0, bottom: 0, right: 0),
            panelSize: NSSize(width: 960, height: 276)
        )

        XCTAssertEqual(frame.width, 400, accuracy: 0.001)
        XCTAssertLessThanOrEqual(frame.maxX, 200)
        XCTAssertGreaterThanOrEqual(frame.minX, -200)
        XCTAssertGreaterThanOrEqual(frame.minY, 0)
    }

    func testNotchlessCollapsedFrameStartsInvisibleAtTopCenter() {
        let expanded = NSRect(x: 100, y: 400, width: 800, height: 276)
        let collapsed = TopNotchHistoryGeometry.collapsedFrame(from: expanded)

        XCTAssertEqual(collapsed.maxY, expanded.maxY, accuracy: 0.001)
        XCTAssertEqual(collapsed.midX, expanded.midX, accuracy: 0.001)
        XCTAssertEqual(collapsed.width, 160, accuracy: 0.001)
        XCTAssertEqual(collapsed.height, 1, accuracy: 0.001)
    }

    func testCameraCollapsedFrameMatchesNotchGapAndSafeAreaBand() {
        let expanded = NSRect(x: 276, y: 669, width: 960, height: 313)
        let collapsed = TopNotchHistoryGeometry.collapsedFrame(
            from: expanded,
            safeAreaInsets: NSEdgeInsets(top: 37, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: NSRect(x: 0, y: 945, width: 586, height: 37),
            auxiliaryTopRightArea: NSRect(x: 926, y: 945, width: 586, height: 37)
        )

        XCTAssertEqual(collapsed.maxY, expanded.maxY, accuracy: 0.001)
        XCTAssertEqual(collapsed.midX, expanded.midX, accuracy: 0.001)
        XCTAssertEqual(collapsed.width, 404, accuracy: 0.001)
        XCTAssertEqual(collapsed.height, 37, accuracy: 0.001)
    }

    func testSurfaceBottomCornersContinueInwardFromSideWalls() {
        let bounds = CGRect(x: 0, y: 0, width: 960, height: 313)
        let path = TopNotchHistorySurfaceView.surfacePath(in: bounds)

        XCTAssertFalse(path.contains(CGPoint(x: 40, y: 312)))
        XCTAssertTrue(path.contains(CGPoint(x: 72, y: 312)))
        XCTAssertFalse(path.contains(CGPoint(x: 920, y: 312)))
        XCTAssertTrue(path.contains(CGPoint(x: 888, y: 312)))
    }

    func testCompactSurfacePathStaysCenteredInsideExpandedLayout() {
        let compactRect = CGRect(x: 338, y: 0, width: 404, height: 37)
        let path = TopNotchHistorySurfaceView.surfacePath(in: compactRect)

        XCTAssertFalse(path.contains(CGPoint(x: 337, y: 1)))
        XCTAssertTrue(path.contains(CGPoint(x: 540, y: 20)))
        XCTAssertFalse(path.contains(CGPoint(x: 743, y: 1)))
    }

    func testContentInsetClearsConcaveTopCorner() {
        XCTAssertGreaterThan(
            TopNotchHistoryGeometry.contentHorizontalInset,
            TopNotchHistoryGeometry.topCornerRadius
        )
        XCTAssertEqual(TopNotchHistoryGeometry.contentHorizontalInset, 46, accuracy: 0.001)
    }

    func testPresentationStateMachineHandlesShowDismissAndInterruption() {
        var state = TopNotchPresentationState.hidden
        state = TopNotchPresentationStateMachine.transition(state, event: .show)
        XCTAssertEqual(state, .appearing)
        state = TopNotchPresentationStateMachine.transition(state, event: .appearanceFinished)
        XCTAssertEqual(state, .visible)
        state = TopNotchPresentationStateMachine.transition(state, event: .dismiss)
        XCTAssertEqual(state, .dismissing)
        state = TopNotchPresentationStateMachine.transition(state, event: .show)
        XCTAssertEqual(state, .appearing)
    }

    func testCardDescriptorUsesBoundedTypeAwareMetadata() {
        let entry = HistoryEntry(
            id: UUID(),
            text: String(repeating: "x", count: 500),
            activityAt: Date(),
            representations: [HistoryRepresentationDescriptor(kind: .text, typeIdentifier: "public.utf8-plain-text")]
        )

        let descriptor = TopNotchHistoryCardDescriptor.make(entry: entry)

        XCTAssertEqual(descriptor.kind, .text)
        XCTAssertEqual(descriptor.detail.count, HistoryPreview.maximumCharacters + 1)
        XCTAssertTrue(descriptor.detail.hasSuffix("…"))
    }

    func testCardDescriptorSurfacesUnavailableReferenceState() {
        let descriptor = HistoryOccurrenceDescriptor(
            id: UUID(),
            activityAt: Date(),
            textPreview: nil,
            representations: [HistoryRepresentationDescriptor(
                kind: .fileReference,
                typeIdentifier: "public.file-url"
            )],
            referenceMetadata: [HistoryReferenceMetadata(
                displayName: "report.pdf",
                typeIdentifier: "com.adobe.pdf",
                searchText: "report.pdf",
                availability: .unavailable
            )]
        )

        let card = TopNotchHistoryCardDescriptor.make(descriptor: descriptor)

        XCTAssertEqual(card.detail, "Unavailable: report.pdf")
        XCTAssertTrue(card.accessibilityLabel.contains("Unavailable"))
    }
}
