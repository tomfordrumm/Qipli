import AppKit
import XCTest
@testable import Qipli

final class TopNotchHistoryShelfTests: XCTestCase {
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
