import AppKit
import XCTest
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
