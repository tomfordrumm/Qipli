import AppKit
import XCTest
import SwiftUI
@testable import Qipli

final class TopNotchHistoryShelfTests: XCTestCase {
    @MainActor
    func testPresentationResetsNativeScrollEvenWithUnchangedSnapshot() {
        let collectionView = NSCollectionView(frame: NSRect(x: 0, y: 0, width: 3_000, height: 180))
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 180))
        scrollView.documentView = collectionView
        let bridge = TopNotchHistoryInteractionBridge()
        bridge.attach(collectionView: collectionView)

        for offset in [600.0, 1_200.0] {
            scrollView.contentView.scroll(to: NSPoint(x: offset, y: 0))
            bridge.applySnapshot(entryIDs: [], selectedEntryID: nil)
            // Ordinary snapshot/thumbnail updates must preserve manual scrolling.
            XCTAssertEqual(scrollView.contentView.bounds.origin.x, offset, accuracy: 0.1)

            bridge.resetViewportToStart()
            XCTAssertEqual(scrollView.contentView.bounds.origin.x, 0, accuracy: 0.1)
        }
    }

    func testDisconnectedPreferredDisplayIsRejectedBeforePlacement() {
        XCTAssertNil(
            TopNotchDisplaySelection.resolvedPreferredDisplayID(
                preferredDisplayID: CGDirectDisplayID(42),
                availableDisplayIDs: [CGDirectDisplayID(1), CGDirectDisplayID(2)]
            )
        )
        XCTAssertEqual(
            TopNotchDisplaySelection.resolvedPreferredDisplayID(
                preferredDisplayID: CGDirectDisplayID(2),
                availableDisplayIDs: [CGDirectDisplayID(1), CGDirectDisplayID(2)]
            ),
            CGDirectDisplayID(2)
        )
    }

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

    func testCompactCameraGeometryUsesContinuousBandWithCameraSafeContent() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1_512, height: 982)
        let left = NSRect(x: 0, y: 945, width: 586, height: 37)
        let right = NSRect(x: 926, y: 945, width: 586, height: 37)
        let geometry = PasteStackCompactGeometry.make(
            screenFrame: screenFrame,
            visibleFrame: NSRect(x: 0, y: 0, width: 1_512, height: 950),
            safeAreaInsets: NSEdgeInsets(top: 37, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: left,
            auxiliaryTopRightArea: right
        )

        XCTAssertTrue(geometry.isNotched)
        XCTAssertLessThanOrEqual(geometry.leftContentRect.maxX, left.maxX - 8)
        XCTAssertGreaterThanOrEqual(geometry.rightContentRect.minX, right.minX + 8)
        XCTAssertEqual(geometry.panelFrame.maxY, screenFrame.maxY, accuracy: 0.001)
        XCTAssertEqual(geometry.panelFrame.height, 37, accuracy: 0.001)
        XCTAssertEqual(geometry.panelFrame.width, 468, accuracy: 0.001)
        XCTAssertEqual(geometry.panelFrame.midX, screenFrame.midX, accuracy: 0.001)
        XCTAssertTrue(geometry.panelFrame.contains(geometry.leftContentRect))
        XCTAssertTrue(geometry.panelFrame.contains(geometry.rightContentRect))
        let localPanelBounds = NSRect(origin: .zero, size: geometry.panelFrame.size)
        XCTAssertTrue(geometry.localInteractiveRegions.allSatisfy {
            localPanelBounds.contains($0)
        })
        XCTAssertEqual(geometry.localInteractiveRegions, [localPanelBounds])
    }

    func testCompactNotchlessGeometryUsesCenteredSingleBand() {
        let geometry = PasteStackCompactGeometry.make(
            screenFrame: NSRect(x: 100, y: 40, width: 1_000, height: 800),
            visibleFrame: NSRect(x: 100, y: 40, width: 1_000, height: 760),
            safeAreaInsets: NSEdgeInsets()
        )

        XCTAssertFalse(geometry.isNotched)
        XCTAssertEqual(geometry.panelFrame.midX, 600, accuracy: 0.001)
        XCTAssertEqual(geometry.panelFrame.maxY, 840, accuracy: 0.001)
        XCTAssertEqual(geometry.localInteractiveRegions, [CGRect(origin: .zero, size: geometry.panelFrame.size)])
        XCTAssertTrue(geometry.panelFrame.contains(geometry.leftContentRect))
        XCTAssertTrue(geometry.panelFrame.contains(geometry.rightContentRect))
    }

    func testFinderCutFilenameRowExtendsBelowBandWithoutMovingCameraSafeContent() {
        for notched in [false, true] {
            let band = PasteStackCompactGeometry.make(
                screenFrame: NSRect(x: 100, y: 40, width: 1_512, height: 982),
                visibleFrame: NSRect(x: 100, y: 40, width: 1_512, height: 945),
                safeAreaInsets: NSEdgeInsets(top: notched ? 37 : 0, left: 0, bottom: 0, right: 0),
                auxiliaryTopLeftArea: notched ? NSRect(x: 100, y: 985, width: 586, height: 37) : nil,
                auxiliaryTopRightArea: notched ? NSRect(x: 1_026, y: 985, width: 586, height: 37) : nil
            )
            let cut = band.addingFinderCutFilenameRow()
            XCTAssertEqual(cut.panelFrame.maxY, band.panelFrame.maxY)
            XCTAssertEqual(cut.panelFrame.width, band.panelFrame.width)
            XCTAssertEqual(cut.panelFrame.height, band.panelFrame.height + 28)
            XCTAssertEqual(cut.leftContentRect, band.leftContentRect)
            XCTAssertEqual(cut.rightContentRect, band.rightContentRect)
            XCTAssertGreaterThanOrEqual(cut.localLeftContentRect.minY, 28)
            XCTAssertGreaterThanOrEqual(cut.localRightContentRect.minY, 28)
            XCTAssertEqual(cut.localInteractiveRegions, [CGRect(origin: .zero, size: cut.panelFrame.size)])
        }
    }

    @MainActor
    func testCompactPointerReentryReversesCollapseWithoutReturningToCompact() {
        let model = PasteStackPresentationModel()
        var preservesCurrentAlpha = false
        model.onIntent = { intent in
            if case let .expand(_, preservesCurrentAlpha: preserves) = intent {
                preservesCurrentAlpha = preserves
            }
        }
        let geometry = PasteStackCompactGeometry.make(
            screenFrame: NSRect(x: 0, y: 0, width: 1_000, height: 800),
            visibleFrame: NSRect(x: 0, y: 0, width: 1_000, height: 760),
            safeAreaInsets: NSEdgeInsets()
        )
        model.beginSession(geometry: geometry)
        model.requestExpand(source: .click)
        let expansionToken = model.generation
        model.finishExpansion(token: expansionToken)
        model.requestCollapse()
        XCTAssertEqual(model.state, .collapsing)

        model.pointerEntered()

        XCTAssertEqual(model.state, .expanding)
        XCTAssertNotEqual(model.generation, expansionToken)
        XCTAssertTrue(preservesCurrentAlpha)
    }

    @MainActor
    func testGeometryChangeReconcilesEveryActivePresentationTransition() {
        let model = PasteStackPresentationModel()
        let firstGeometry = PasteStackCompactGeometry.make(
            screenFrame: NSRect(x: 0, y: 0, width: 1_000, height: 800),
            visibleFrame: NSRect(x: 0, y: 0, width: 1_000, height: 760),
            safeAreaInsets: NSEdgeInsets()
        )
        let secondGeometry = PasteStackCompactGeometry.make(
            screenFrame: NSRect(x: 1_000, y: 0, width: 1_000, height: 800),
            visibleFrame: NSRect(x: 1_000, y: 0, width: 1_000, height: 760),
            safeAreaInsets: NSEdgeInsets()
        )
        let thirdGeometry = PasteStackCompactGeometry.make(
            screenFrame: NSRect(x: -1_000, y: 0, width: 1_000, height: 800),
            visibleFrame: NSRect(x: -1_000, y: 0, width: 1_000, height: 760),
            safeAreaInsets: NSEdgeInsets()
        )
        let fourthGeometry = PasteStackCompactGeometry.make(
            screenFrame: NSRect(x: 2_000, y: 0, width: 1_000, height: 800),
            visibleFrame: NSRect(x: 2_000, y: 0, width: 1_000, height: 760),
            safeAreaInsets: NSEdgeInsets()
        )
        model.beginSession(geometry: firstGeometry)

        model.requestExpand(source: .click)
        let staleExpansionToken = model.generation
        model.updateGeometry(secondGeometry)
        XCTAssertEqual(model.state, .expanding)
        XCTAssertNotEqual(model.generation, staleExpansionToken)
        model.finishExpansion(token: model.generation)
        XCTAssertEqual(model.state, .expanded)

        model.requestCollapse()
        let staleCollapseToken = model.generation
        model.updateGeometry(thirdGeometry)
        XCTAssertEqual(model.state, .compact)
        XCTAssertNotEqual(model.generation, staleCollapseToken)
        model.finishCollapse(token: staleCollapseToken)
        XCTAssertEqual(model.state, .compact)

        model.requestDismissal()
        let staleDismissalToken = model.generation
        model.updateGeometry(fourthGeometry)
        XCTAssertEqual(model.state, .dismissing)
        XCTAssertNotEqual(model.generation, staleDismissalToken)
        model.finishDismissal(token: model.generation)
        XCTAssertEqual(model.state, .hidden)
    }

    @MainActor
    func testCompactGeometryChangeCancelsPendingHoverAndRequiresFreshEntry() async {
        let model = PasteStackPresentationModel()
        let initialGeometry = PasteStackCompactGeometry.make(
            screenFrame: NSRect(x: 0, y: 0, width: 1_000, height: 800),
            visibleFrame: NSRect(x: 0, y: 0, width: 1_000, height: 760),
            safeAreaInsets: NSEdgeInsets()
        )
        let changedGeometry = PasteStackCompactGeometry.make(
            screenFrame: NSRect(x: 1_000, y: 0, width: 1_000, height: 800),
            visibleFrame: NSRect(x: 1_000, y: 0, width: 1_000, height: 760),
            safeAreaInsets: NSEdgeInsets()
        )
        model.beginSession(geometry: initialGeometry)
        model.pointerEntered()
        model.updateGeometry(changedGeometry)

        try? await Task.sleep(nanoseconds: 350_000_000)

        XCTAssertEqual(model.state, .compact)
        model.pointerEntered()
        XCTAssertEqual(model.state, .compact)
    }

    @MainActor
    func testMouseInteractionHoldPreventsCollapseUntilRelease() {
        let model = PasteStackPresentationModel()
        let geometry = PasteStackCompactGeometry.make(
            screenFrame: NSRect(x: 0, y: 0, width: 1_000, height: 800),
            visibleFrame: NSRect(x: 0, y: 0, width: 1_000, height: 760),
            safeAreaInsets: NSEdgeInsets()
        )
        model.beginSession(geometry: geometry)
        model.requestExpand(source: .click)
        let expansionToken = model.generation
        model.finishExpansion(token: expansionToken)
        model.beginInteractionHold()
        model.pointerExited()
        model.requestCollapse()
        XCTAssertEqual(model.state, .expanded)

        model.endInteractionHold()

        XCTAssertEqual(model.state, .expanded)
    }

    func testNotchlessPlacementAnchorsToPhysicalScreenTop() {
        let frame = TopNotchHistoryGeometry.frame(
            screenFrame: NSRect(x: 100, y: 40, width: 1_000, height: 800),
            visibleFrame: NSRect(x: 100, y: 40, width: 1_000, height: 760),
            safeAreaInsets: NSEdgeInsets()
        )

        XCTAssertEqual(frame.maxY, 840, accuracy: 0.001)
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

    func testCameraCollapsedFrameHidesInsideNotchGapAndSafeAreaBand() {
        let expanded = NSRect(x: 276, y: 669, width: 960, height: 313)
        let auxiliaryTopLeftArea = NSRect(x: 0, y: 945, width: 586, height: 37)
        let auxiliaryTopRightArea = NSRect(x: 926, y: 945, width: 586, height: 37)
        let collapsed = TopNotchHistoryGeometry.collapsedFrame(
            from: expanded,
            safeAreaInsets: NSEdgeInsets(top: 37, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: auxiliaryTopLeftArea,
            auxiliaryTopRightArea: auxiliaryTopRightArea
        )

        XCTAssertEqual(collapsed.maxY, expanded.maxY, accuracy: 0.001)
        XCTAssertEqual(collapsed.midX, expanded.midX, accuracy: 0.001)
        XCTAssertEqual(collapsed.minX, auxiliaryTopLeftArea.maxX, accuracy: 0.001)
        XCTAssertEqual(collapsed.maxX, auxiliaryTopRightArea.minX, accuracy: 0.001)
        XCTAssertEqual(collapsed.width, 340, accuracy: 0.001)
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
        let compactRect = CGRect(x: 370, y: 0, width: 340, height: 37)
        let path = TopNotchHistorySurfaceView.surfacePath(in: compactRect)

        XCTAssertFalse(path.contains(CGPoint(x: 369, y: 1)))
        XCTAssertTrue(path.contains(CGPoint(x: 540, y: 20)))
        XCTAssertFalse(path.contains(CGPoint(x: 711, y: 1)))
    }

    func testRevealAnimationStartsFromPreparedCompactMaskInsteadOfStalePresentationPath() {
        let bounds = CGRect(x: 0, y: 0, width: 960, height: 313)
        let compactRect = CGRect(x: 310, y: 0, width: 340, height: 37)
        let compactPath = TopNotchHistorySurfaceView.surfacePath(in: compactRect)
        let staleExpandedPath = TopNotchHistorySurfaceView.surfacePath(in: bounds)

        let startPath = TopNotchHistorySurfaceView.animationStartPath(
            modelPath: compactPath,
            presentationPath: staleExpandedPath,
            startsFromPresentation: false
        )

        XCTAssertEqual(startPath.boundingBoxOfPath, compactRect)
    }

    func testContentInsetClearsConcaveTopCorner() {
        XCTAssertGreaterThan(
            TopNotchHistoryGeometry.contentHorizontalInset,
            TopNotchHistoryGeometry.topCornerRadius
        )
        XCTAssertEqual(TopNotchHistoryGeometry.contentHorizontalInset - TopNotchHistoryGeometry.topCornerRadius, 14, accuracy: 0.001)
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

    @MainActor
    func testPasteStackPresentationKeepsAccessibilityExpansionUntilExplicitCollapse() {
        let geometry = PasteStackCompactGeometry.make(
            screenFrame: NSRect(x: 0, y: 0, width: 1_512, height: 982),
            visibleFrame: NSRect(x: 0, y: 0, width: 1_512, height: 950),
            safeAreaInsets: NSEdgeInsets(top: 37, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: NSRect(x: 0, y: 945, width: 586, height: 37),
            auxiliaryTopRightArea: NSRect(x: 926, y: 945, width: 586, height: 37)
        )
        let model = PasteStackPresentationModel()
        model.beginSession(geometry: geometry)
        XCTAssertEqual(model.state, .compact)

        model.requestExpand(source: .accessibility)
        let expansionToken = model.generation
        XCTAssertEqual(model.state, .expanding)
        model.finishExpansion(token: expansionToken)
        XCTAssertEqual(model.state, .expanded)

        model.pointerExited()
        model.requestCollapse()
        XCTAssertEqual(model.state, .expanded)

        model.requestExplicitCollapse()
        XCTAssertEqual(model.state, .collapsing)
        model.finishCollapse(token: model.generation)
        XCTAssertEqual(model.state, .compact)
    }

    func testCardDescriptorUsesBoundedTypeAwareMetadata() {
        let entry = HistoryEntry(
            id: UUID(),
            text: String(repeating: "x", count: 500),
            activityAt: Date(),
            representations: [HistoryRepresentationDescriptor(kind: .text, typeIdentifier: "public.utf8-plain-text")],
            isFavorite: true
        )

        let descriptor = TopNotchHistoryCardDescriptor.make(entry: entry)

        XCTAssertEqual(descriptor.kind, .text)
        XCTAssertTrue(descriptor.isFavorite)
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

    func testCardTextLayoutWrapsAndTruncatesOnlyTheLastVisibleLine() throws {
        let label = NSTextField(wrappingLabelWithString: "")

        TopNotchHistoryCardTextLayout.configure(label)

        let cell = try XCTUnwrap(label.cell as? NSTextFieldCell)
        XCTAssertEqual(label.maximumNumberOfLines, 5)
        XCTAssertEqual(label.lineBreakMode, .byWordWrapping)
        XCTAssertTrue(cell.wraps)
        XCTAssertTrue(cell.truncatesLastVisibleLine)
    }

    func testImageScrimFadesFromTransparentTopToReadableBottom() throws {
        let scrim = TopNotchHistoryImageScrimView(
            frame: NSRect(x: 0, y: 0, width: 220, height: 66)
        )
        scrim.layoutSubtreeIfNeeded()

        let colors = try XCTUnwrap(scrim.gradientLayer.colors as? [CGColor])
        let topColor = try XCTUnwrap(colors.first)
        let bottomColor = try XCTUnwrap(colors.last)
        XCTAssertTrue(scrim.isFlipped)
        XCTAssertEqual(scrim.gradientLayer.startPoint, CGPoint(x: 0.5, y: 0))
        XCTAssertEqual(scrim.gradientLayer.endPoint, CGPoint(x: 0.5, y: 1))
        XCTAssertEqual(scrim.gradientLayer.locations, [0, 0.55, 1])
        XCTAssertEqual(topColor.alpha, 0, accuracy: 0.001)
        XCTAssertEqual(bottomColor.alpha, 0.68, accuracy: 0.001)
        XCTAssertEqual(scrim.gradientLayer.frame, scrim.bounds)
    }

    func testHistorySearchRankKeepsTypedURLAheadOfIncidentalText() {
        let oldURL = HistoryEntry(
            id: UUID(),
            text: "http://localhost/old",
            activityAt: Date(timeIntervalSinceReferenceDate: 1),
            representations: [HistoryRepresentationDescriptor(kind: .url, typeIdentifier: "public.url")],
            referenceMetadata: [HistoryReferenceMetadata(
                displayName: "localhost",
                typeIdentifier: "public.url",
                domain: "localhost",
                searchText: "http://localhost/old"
            )]
        )
        let text = HistoryEntry(id: UUID(), text: "new localhost note", activityAt: Date(timeIntervalSinceReferenceDate: 2))

        XCTAssertEqual(HistorySearchRank.classify(entry: oldURL, query: "localhost"), .exactOrPrefixURL)
        XCTAssertEqual(HistorySearchRank.classify(entry: text, query: "localhost"), .otherMatch)
    }

    func testCollectionReconcilerSeparatesSnapshotSelectionAndThumbnailUpdates() {
        let firstID = UUID()
        let secondID = UUID()
        let unchanged = TopNotchHistoryCollectionReconciler.plan(
            force: false,
            lastRevision: 7,
            lastIDs: [firstID, secondID],
            snapshotRevision: 7,
            ids: [firstID, secondID],
            thumbnailUpdateRevisionsByEntryID: [:],
            lastThumbnailUpdateRevisionsByEntryID: [:],
            visibleEntryIDs: [firstID, secondID]
        )
        XCTAssertEqual(
            unchanged,
            TopNotchHistoryCollectionApplyPlan(reloadData: false, thumbnailEntryIDs: [])
        )

        let targeted = TopNotchHistoryCollectionReconciler.plan(
            force: false,
            lastRevision: 7,
            lastIDs: [firstID, secondID],
            snapshotRevision: 7,
            ids: [firstID, secondID],
            thumbnailUpdateRevisionsByEntryID: [secondID: 3],
            lastThumbnailUpdateRevisionsByEntryID: [secondID: 2],
            visibleEntryIDs: [firstID, secondID]
        )
        XCTAssertEqual(
            targeted,
            TopNotchHistoryCollectionApplyPlan(reloadData: false, thumbnailEntryIDs: [secondID])
        )

        XCTAssertEqual(
            TopNotchHistoryCollectionReconciler.plan(
                force: false,
                lastRevision: 7,
                lastIDs: [firstID, secondID],
                snapshotRevision: 7,
                ids: [firstID, secondID],
                thumbnailUpdateRevisionsByEntryID: [secondID: 4],
                lastThumbnailUpdateRevisionsByEntryID: [secondID: 3],
                visibleEntryIDs: [firstID]
            ),
            TopNotchHistoryCollectionApplyPlan(reloadData: false, thumbnailEntryIDs: [])
        )
        XCTAssertTrue(
            TopNotchHistoryCollectionReconciler.plan(
                force: false,
                lastRevision: 7,
                lastIDs: [firstID, secondID],
                snapshotRevision: 8,
                ids: [firstID, secondID],
                thumbnailUpdateRevisionsByEntryID: [firstID: 4, secondID: 5],
                lastThumbnailUpdateRevisionsByEntryID: [firstID: 3, secondID: 4],
                visibleEntryIDs: [firstID, secondID]
            ).reloadData
        )
    }

    func testCollectionReconcilerUpdatesFavoriteCardWithoutReloadingAllCards() {
        let id = UUID()
        let base = TopNotchHistoryCardDescriptor(
            id: id,
            isFavorite: false,
            kind: .text,
            title: "Text",
            detail: "favorite fixture",
            accessibilityLabel: "Text: favorite fixture"
        )
        let favorite = TopNotchHistoryCardDescriptor(
            id: id,
            isFavorite: true,
            kind: .text,
            title: "Text",
            detail: "favorite fixture",
            accessibilityLabel: "Text: favorite fixture"
        )

        let plan = TopNotchHistoryCollectionReconciler.plan(
            force: false,
            lastRevision: 1,
            lastIDs: [id],
            snapshotRevision: 2,
            ids: [id],
            thumbnailUpdateRevisionsByEntryID: [:],
            lastThumbnailUpdateRevisionsByEntryID: [:],
            visibleEntryIDs: [id],
            lastCards: [base],
            cards: [favorite]
        )

        XCTAssertFalse(plan.reloadData)
        XCTAssertEqual(plan.cardEntryIDs, [id])
    }

    func testCollectionSelectionReconcilerIsNoOpForAlreadyAppliedSelection() {
        let selected = IndexPath(item: 1, section: 0)
        XCTAssertFalse(TopNotchHistoryCollectionReconciler.selectionNeedsUpdate(
            current: [selected],
            target: selected
        ))
        XCTAssertTrue(TopNotchHistoryCollectionReconciler.selectionNeedsUpdate(
            current: [selected],
            target: IndexPath(item: 0, section: 0)
        ))
        XCTAssertTrue(TopNotchHistoryCollectionReconciler.selectionNeedsUpdate(
            current: [selected],
            target: nil
        ))
    }

    func testDeleteAdmissionRequiresExactShiftBackspaceAndAllowsFilteredSearch() {
        let id = UUID()
        let accepted = HistoryDeleteKeyAdmission.selectedEntryID(
            for: HistoryDeleteKeyEvent(key: .backspace, hasOnlyShiftModifier: true, isRepeat: false),
            isEventInHistoryWindow: true,
            isSearchFocused: true,
            query: "localhost",
            selectedEntryID: id
        )
        XCTAssertEqual(accepted, id)

        for event in [
            HistoryDeleteKeyEvent(key: .backspace, hasOnlyShiftModifier: false, isRepeat: false),
            HistoryDeleteKeyEvent(key: .backspace, hasOnlyShiftModifier: true, isRepeat: true),
            HistoryDeleteKeyEvent(key: .forwardDelete, hasOnlyShiftModifier: true, isRepeat: false),
            HistoryDeleteKeyEvent(key: .backspace, hasOnlyShiftModifier: true, isRepeat: false)
        ] {
            let result = HistoryDeleteKeyAdmission.selectedEntryID(
                for: event,
                isEventInHistoryWindow: event.key == .backspace,
                isSearchFocused: event.key != .forwardDelete,
                query: "",
                selectedEntryID: event.key == .backspace && !event.isRepeat && event.hasOnlyShiftModifier ? id : nil
            )
            if event.key != .backspace || !event.hasOnlyShiftModifier || event.isRepeat {
                XCTAssertNil(result)
            }
        }
    }
}

@MainActor
final class LayoutCorrectionNoticeTests: XCTestCase {
    func testNewErrorSurvivesOldTimerAndAnimationCompletion() {
        let model = LayoutCorrectionNoticeModel()
        var expired: [Int] = []
        model.onDismiss = { expired.append($0) }
        XCTAssertTrue(model.show(.failed("The focused text field is unavailable.")))
        let first = model.generation
        model.expire(token: first)
        XCTAssertEqual(expired, [first])
        XCTAssertTrue(model.show(.denied("Another Qipli input action is active.")))
        let second = model.generation
        model.finishDismissal(token: first)
        model.expire(token: first)
        XCTAssertNotNil(model.message)
        XCTAssertFalse(model.isDismissing)
        model.expire(token: second)
        XCTAssertEqual(expired, [first, second])
        model.finishDismissal(token: second)
        XCTAssertNil(model.message)
    }

    func testNoticeTimerRequestsDismissalAfterThreeSeconds() async {
        let model = LayoutCorrectionNoticeModel()
        let start = DispatchTime.now().uptimeNanoseconds
        let done = expectation(description: "notice expired")
        model.onDismiss = { token in
            XCTAssertEqual(token, model.generation)
            XCTAssertGreaterThanOrEqual(DispatchTime.now().uptimeNanoseconds - start, 3_000_000_000)
            done.fulfill()
        }
        model.show(.failed("The focused text field is unavailable."))
        await fulfillment(of: [done], timeout: 5)
        XCTAssertTrue(model.isDismissing)
        model.close()
    }

    func testSuccessDoesNotOpenNoticeAndCloseInvalidatesTimer() {
        let model = LayoutCorrectionNoticeModel()
        XCTAssertFalse(model.show(.completed(sourceID: "fixture")))
        XCTAssertNil(model.message)
        model.show(.failed("The text field did not respond in time."))
        let token = model.generation
        model.close()
        model.expire(token: token)
        XCTAssertNil(model.message)
        XCTAssertFalse(model.isDismissing)
    }

    func testNoticeRendersWithLongestFixedMessage() throws {
        let model = LayoutCorrectionNoticeModel()
        model.show(.failed("Text corrected, but the input context changed before layout switching."))
        model.setGeometry(width: 440, topInset: 32)
        let view = NSHostingView(rootView: LayoutCorrectionNoticeView(model: model))
        view.frame = NSRect(x: 0, y: 0, width: 440, height: 108)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.bounds.size, NSSize(width: 440, height: 108))
        XCTAssertLessThanOrEqual(view.fittingSize.height, 108)
        if let path = ProcessInfo.processInfo.environment["QIPLI_NOTICE_PREVIEW_PATH"],
           let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
        model.close()
        window.close()
    }

    func testRealCardMouseUpPreservesShiftThroughCallback() throws {
        let item = TopNotchHistoryCollectionItem()
        _ = item.view
        var modes: [HistoryPasteMode] = []
        item.configure(card: TopNotchHistoryCardDescriptor(id: UUID(), isFavorite: false,
            kind: .text, title: "Text", detail: "synthetic fixture", accessibilityLabel: "Text"),
            thumbnailData: nil, isSelected: true, requestThumbnail: {},
            doubleClick: { modes.append($0) }, toggleFavorite: { _ in })
        for (count, flags) in [(1, NSEvent.ModifierFlags.shift), (2, .shift), (2, [])] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: .zero,
                modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 1, clickCount: count, pressure: 0))
            item.view.mouseUp(with: event)
        }
        XCTAssertEqual(modes, [.plainText, .rich])
    }

    func testShiftMousePasteSelectsPlainText() {
        XCTAssertEqual(HistoryCardPasteAdmission.mode(for: .shift), .plainText)
        XCTAssertEqual(HistoryCardPasteAdmission.mode(for: [.shift, .capsLock]), .plainText)
        XCTAssertEqual(HistoryCardPasteAdmission.mode(for: []), .rich)
        XCTAssertEqual(HistoryCardPasteAdmission.mode(for: .capsLock), .rich)
    }
}

@MainActor
final class PanelEdgePresentationTests: XCTestCase {
    func testSharedPreferenceDefaultsPersistsAndRecoversUnknownValue() throws {
        let suite = "Qipli.PanelEdgeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = PanelPreferences(defaults: defaults)
        XCTAssertEqual(preferences.edge, .top)
        for edge in PanelEdge.allCases {
            preferences.setEdge(edge)
            XCTAssertEqual(PanelPreferences(defaults: defaults).edge, edge)
        }
        defaults.set("future-edge", forKey: PanelPreferences.edgeKey)
        XCTAssertEqual(PanelPreferences(defaults: defaults).edge, .top)
    }

    func testPanelsMeetPhysicalEdgeWhileControlsClearDockAndContainCompactEndpoint() {
        // Dock on either side/bottom, a secondary display with negative origin,
        // and a small display. The available frame is supplied by NSScreen.
        let frames = [
            (NSRect(x: 0, y: 0, width: 1512, height: 982), NSRect(x: 80, y: 0, width: 1432, height: 945)),
            (NSRect(x: 0, y: 0, width: 1512, height: 982), NSRect(x: 0, y: 0, width: 1432, height: 945)),
            (NSRect(x: 0, y: 0, width: 1512, height: 982), NSRect(x: 0, y: 80, width: 1512, height: 865)),
            (NSRect(x: -1920, y: -200, width: 1920, height: 1080), NSRect(x: -1920, y: -200, width: 1920, height: 1056)),
            (NSRect(x: 100, y: 50, width: 480, height: 384), NSRect(x: 100, y: 50, width: 480, height: 360))
        ]
        for edge in [PanelEdge.left, .right, .bottom] {
            for (screen, frame) in frames {
                for stack in [false, true] {
                    let expanded = PanelEdgeGeometry.expandedFrame(edge: edge, screenFrame: screen, visibleFrame: frame, isStack: stack)
                    let compact = PanelEdgeGeometry.compactGeometry(edge: edge, screenFrame: screen, visibleFrame: frame)
                    XCTAssertTrue(screen.contains(expanded), "\(edge)")
                    for attached in [expanded, compact.panelFrame] {
                        switch edge {
                        case .left: XCTAssertEqual(attached.minX, screen.minX)
                        case .right: XCTAssertEqual(attached.maxX, screen.maxX)
                        case .bottom: XCTAssertEqual(attached.minY, screen.minY)
                        case .top: break
                        }
                    }
                    XCTAssertTrue(expanded.contains(compact.panelFrame), "\(edge)")
                    XCTAssertTrue(CGRect(origin: .zero, size: expanded.size).contains(
                        PanelEdgeGeometry.localRect(compact.panelFrame, in: expanded)))
                    XCTAssertTrue(compact.panelFrame.contains(compact.leftContentRect))
                    XCTAssertTrue(compact.panelFrame.contains(compact.rightContentRect))
                    XCTAssertTrue(frame.contains(compact.leftContentRect))
                    XCTAssertTrue(frame.contains(compact.rightContentRect))
                }
            }
        }
    }

    func testRevealEndpointUsesChosenEdgeInFlippedSurfaceCoordinates() {
        let expanded = NSRect(x: -500, y: 120, width: 360, height: 640)
        for edge in PanelEdge.allCases {
            let collapsed = PanelEdgeGeometry.collapsedFrame(edge: edge, expandedFrame: expanded)
            let local = PanelEdgeGeometry.localRect(collapsed, in: expanded)
            XCTAssertTrue(CGRect(origin: .zero, size: expanded.size).contains(local))
            switch edge {
            case .top: XCTAssertEqual(local.minY, 0)
            case .bottom: XCTAssertEqual(local.maxY, expanded.height)
            case .left: XCTAssertEqual(local.minX, 0)
            case .right: XCTAssertEqual(local.maxX, expanded.width)
            }
        }
    }

    func testRelocatingStackDuringCollapseInvalidatesOldCompletion() {
        let model = PasteStackPresentationModel()
        let visible = NSRect(x: 0, y: 0, width: 1200, height: 800)
        model.beginSession(geometry: PanelEdgeGeometry.compactGeometry(edge: .left, visibleFrame: visible))
        model.requestExpand(source: .accessibility)
        model.finishExpansion(token: model.generation)
        model.requestExplicitCollapse()
        let oldToken = model.generation
        model.edge = .right
        model.updateGeometry(PanelEdgeGeometry.compactGeometry(edge: .right, visibleFrame: visible))
        XCTAssertEqual(model.state, .compact)
        XCTAssertFalse(model.isCurrent(token: oldToken, state: .collapsing))
        model.finishCollapse(token: oldToken)
        XCTAssertEqual(model.state, .compact)
        XCTAssertEqual(model.compactGeometry?.panelFrame.maxX, visible.maxX)
    }

    func testRelocatingExpandedStackPreservesAccessibilityHold() {
        let model = PasteStackPresentationModel()
        let visible = NSRect(x: 0, y: 0, width: 1200, height: 800)
        model.beginSession(geometry: PanelEdgeGeometry.compactGeometry(edge: .left, visibleFrame: visible))
        model.requestExpand(source: .accessibility)
        model.finishExpansion(token: model.generation)
        model.edge = .bottom
        model.updateGeometry(PanelEdgeGeometry.compactGeometry(edge: .bottom, visibleFrame: visible))
        model.pointerExited()
        XCTAssertEqual(model.state, .expanded)
        model.requestExplicitCollapse()
        XCTAssertEqual(model.state, .collapsing)
    }

    func testVerticalCollectionUsesOneColumnAndTracksResize() {
        let layout = HistoryCardFlowLayout()
        layout.scrollDirection = .vertical
        layout.sectionInset = NSEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
        let collection = NSCollectionView()
        collection.collectionViewLayout = layout
        let scroll = HistoryCardsScrollView(frame: .zero)
        scroll.documentView = collection
        layout.prepare()
        scroll.setFrameSize(NSSize(width: 320, height: 480))
        scroll.tile()
        layout.prepare()
        XCTAssertEqual(layout.itemSize.width, scroll.contentSize.width - 4, accuracy: 0.01)
        scroll.setFrameSize(NSSize(width: 280, height: 480))
        layout.prepare()
        XCTAssertEqual(layout.itemSize.width, scroll.contentSize.width - 4, accuracy: 0.01)
        layout.scrollDirection = .horizontal
        layout.prepare()
        XCTAssertEqual(layout.itemSize.width, 220)
    }

    func testMaskOnlyOverscansAttachmentAcrossCompactAndExpandedStates() throws {
        let surface = TopNotchHistorySurfaceView(frame: NSRect(x: 0, y: 0, width: 360, height: 640))
        for edge in [PanelEdge.left, .right, .bottom] {
            surface.edge = edge
            surface.prepareForExpandedPresentation()
            let mask = try XCTUnwrap(surface.layer?.mask as? CAShapeLayer)
            let actual = try XCTUnwrap(mask.path).boundingBoxOfPath.intersection(surface.bounds)
            let expected = PanelLiquidMotion.restingRect(in: surface.bounds, edge: edge)
            XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.001)
            XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.001)
            XCTAssertEqual(actual.width, expected.width, accuracy: 0.001)
            XCTAssertEqual(actual.height, expected.height, accuracy: 0.001)
            let compact = PanelEdgeGeometry.localRect(
                PanelEdgeGeometry.collapsedFrame(edge: edge, expandedFrame: surface.bounds), in: surface.bounds)
            surface.prepareForReveal(from: compact)
            XCTAssertEqual(try XCTUnwrap(mask.path).boundingBoxOfPath.intersection(surface.bounds), compact)
        }
    }

    func testLiquidRevealAndInterruptedReturnNeverDetachFromAnyEdge() throws {
        let bounds = CGRect(x: 0, y: 0, width: 360, height: 640)
        for edge in PanelEdge.allCases {
            let compact = PanelEdgeGeometry.localRect(
                PanelEdgeGeometry.collapsedFrame(edge: edge, expandedFrame: bounds), in: bounds)
            let start = PanelLiquidContour.path(in: compact, edge: edge, compact: true)
            let end = PanelLiquidContour.path(in: PanelLiquidMotion.restingRect(in: bounds, edge: edge), edge: edge)
            let entry = PanelLiquidMotion.paths(from: start, to: end, edge: edge, expanding: true)
            let interrupted = entry[19]
            let exit = PanelLiquidMotion.paths(from: interrupted, to: start, edge: edge, expanding: false)
            XCTAssertEqual(entry.first, start)
            XCTAssertEqual(entry.last, end)
            XCTAssertEqual(exit.first, interrupted)
            XCTAssertEqual(exit.last, start)
            for path in entry + exit {
                let outline = path.boundingBoxOfPath.intersection(bounds)
                for fraction in [CGFloat(0.25), 0.5, 0.75] {
                    let contact: CGPoint
                    switch edge {
                    case .top: contact = CGPoint(x: outline.minX + outline.width * fraction, y: 0)
                    case .bottom: contact = CGPoint(x: outline.minX + outline.width * fraction, y: bounds.maxY)
                    case .left: contact = CGPoint(x: 0, y: outline.minY + outline.height * fraction)
                    case .right: contact = CGPoint(x: bounds.maxX, y: outline.minY + outline.height * fraction)
                    }
                    XCTAssertTrue(path.contains(contact), "Gap at \(edge), \(contact)")
                }
            }
        }
    }

    func testLiquidSpreadLeadsDepthAndSurfaceInstallsKeyframes() throws {
        let bounds = CGRect(x: 0, y: 0, width: 1080, height: 328)
        let seed = CGRect(x: 430, y: 0, width: 220, height: 38)
        let surface = TopNotchHistorySurfaceView(frame: bounds)
        surface.prepareForReveal(from: seed)
        surface.animateReveal(duration: PanelDesign.revealDuration)
        let mask = try XCTUnwrap(surface.layer?.mask as? CAShapeLayer)
        let animation = try XCTUnwrap(mask.animation(forKey: "topNotchMaskTransition") as? CAKeyframeAnimation)
        let paths = try XCTUnwrap(animation.values as? [CGPath])
        XCTAssertGreaterThan(paths.count, 30)
        let early = paths[paths.count / 4].boundingBoxOfPath.intersection(bounds)
        let widthProgress = (early.width - seed.width) / (bounds.width - seed.width)
        let depthProgress = (early.height - seed.height) / (bounds.height - seed.height)
        XCTAssertGreaterThan(widthProgress, depthProgress + 0.1)
        surface.restoreExpandedPresentation()
        XCTAssertNil(mask.animation(forKey: "topNotchMaskTransition"))
    }

    func testLiquidRevealHasOneSmallSettlingReturnWithoutClipping() {
        for edge in PanelEdge.allCases {
            let bounds = edge.isVertical ? CGRect(x: 0, y: 0, width: 360, height: 640)
                : CGRect(x: 0, y: 0, width: 1080, height: 328)
            let seed = PanelEdgeGeometry.localRect(PanelEdgeGeometry.collapsedFrame(edge: edge, expandedFrame: bounds), in: bounds)
            let start = PanelLiquidContour.path(in: seed, edge: edge, compact: true)
            let target = PanelLiquidContour.path(in: PanelLiquidMotion.restingRect(in: bounds, edge: edge), edge: edge)
            let paths = PanelLiquidMotion.paths(from: start, to: target, edge: edge, expanding: true)
            let depths = paths.map { edge.isVertical ? $0.boundingBoxOfPath.width : $0.boundingBoxOfPath.height }
            let rest = depths.last!
            let peak = depths.max()!
            XCTAssertGreaterThan(peak - rest, 1, "The settling should be perceptible")
            XCTAssertLessThan(peak / rest, 1.016, "No strong bounce")
            let peakIndex = depths.firstIndex(of: peak)!
            XCTAssertGreaterThan(peakIndex, depths.count / 2)
            XCTAssertTrue(zip(depths[peakIndex...], depths[(peakIndex + 1)...]).allSatisfy { $0 >= $1 }, "Only one return, without oscillation")
            for path in paths {
                let rect = path.boundingBoxOfPath
                switch edge {
                case .top: XCTAssertLessThanOrEqual(rect.maxY, bounds.maxY); XCTAssertLessThan(rect.minY, bounds.minY)
                case .bottom: XCTAssertGreaterThanOrEqual(rect.minY, bounds.minY); XCTAssertGreaterThan(rect.maxY, bounds.maxY)
                case .left: XCTAssertLessThanOrEqual(rect.maxX, bounds.maxX); XCTAssertLessThan(rect.minX, bounds.minX)
                case .right: XCTAssertGreaterThanOrEqual(rect.minX, bounds.minX); XCTAssertGreaterThan(rect.maxX, bounds.maxX)
                }
            }
        }
    }
}
