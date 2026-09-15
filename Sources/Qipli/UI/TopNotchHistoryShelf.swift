import AppKit
import SwiftUI

enum TopNotchPresentationState: Equatable {
    case hidden
    case appearing
    case visible
    case dismissing
}

enum TopNotchPresentationEvent: Equatable {
    case show
    case appearanceFinished
    case dismiss
    case dismissalFinished
}

enum TopNotchPresentationStateMachine {
    static func transition(
        _ state: TopNotchPresentationState,
        event: TopNotchPresentationEvent
    ) -> TopNotchPresentationState {
        switch (state, event) {
        case (.hidden, .show), (.dismissing, .show):
            .appearing
        case (.appearing, .appearanceFinished):
            .visible
        case (.visible, .dismiss), (.appearing, .dismiss):
            .dismissing
        case (.dismissing, .dismissalFinished):
            .hidden
        default:
            state
        }
    }
}

enum PasteStackPresentationState: Equatable {
    case hidden
    case compact
    case expanding
    case expanded
    case collapsing
    case dismissing
}

enum PasteStackPresentationEvent: Equatable {
    case show
    case expand
    case expansionFinished
    case collapse
    case collapseFinished
    case dismiss
    case dismissalFinished
}

enum PasteStackPresentationStateMachine {
    static func transition(
        _ state: PasteStackPresentationState,
        event: PasteStackPresentationEvent
    ) -> PasteStackPresentationState {
        switch (state, event) {
        case (.hidden, .show), (.dismissing, .show):
            .compact
        case (.compact, .expand), (.collapsing, .expand):
            .expanding
        case (.expanding, .expansionFinished):
            .expanded
        case (.expanded, .collapse), (.expanding, .collapse):
            .collapsing
        case (.collapsing, .collapseFinished):
            .compact
        case (.compact, .dismiss), (.expanding, .dismiss), (.expanded, .dismiss), (.collapsing, .dismiss):
            .dismissing
        case (.dismissing, .dismissalFinished):
            .hidden
        default:
            state
        }
    }
}

/// The bounded window and visible hit regions used by compact Paste Stack.
/// All rectangles are in global screen coordinates until converted by the
/// `local...` accessors below.
struct PasteStackCompactGeometry: Equatable {
    let panelFrame: NSRect
    let leftContentRect: NSRect
    let rightContentRect: NSRect
    let isNotched: Bool

    var localLeftContentRect: CGRect {
        leftContentRect.offsetBy(dx: -panelFrame.minX, dy: -panelFrame.minY)
    }

    var localRightContentRect: CGRect {
        rightContentRect.offsetBy(dx: -panelFrame.minX, dy: -panelFrame.minY)
    }

    var localInteractiveRegions: [CGRect] {
        [CGRect(origin: .zero, size: panelFrame.size)]
    }

    static func make(
        screenFrame: NSRect,
        visibleFrame: NSRect,
        safeAreaInsets: NSEdgeInsets,
        auxiliaryTopLeftArea: NSRect? = nil,
        auxiliaryTopRightArea: NSRect? = nil
    ) -> Self {
        let isNotched: Bool = {
            guard safeAreaInsets.top > 0,
                  let auxiliaryTopLeftArea,
                  let auxiliaryTopRightArea
            else { return false }
            return auxiliaryTopRightArea.minX > auxiliaryTopLeftArea.maxX
        }()
        let menuHeight = max(0, screenFrame.maxY - visibleFrame.maxY)
        let bandHeight = min(max(1, screenFrame.height), safeAreaInsets.top > 0 ? safeAreaInsets.top : max(24, menuHeight))
        let horizontalPadding: CGFloat = 10
        let verticalPadding: CGFloat = 4
        let top = screenFrame.maxY

        if isNotched, let leftArea = auxiliaryTopLeftArea, let rightArea = auxiliaryTopRightArea {
            let halfWidth = max(screenFrame.midX - leftArea.maxX, rightArea.minX - screenFrame.midX) + 64
            let width = min(screenFrame.width, halfWidth * 2)
            let frame = NSRect(x: screenFrame.midX - width / 2, y: top - bandHeight, width: width, height: bandHeight)
            let content = inset(frame, horizontal: horizontalPadding, vertical: verticalPadding)
            return Self(
                panelFrame: frame,
                leftContentRect: NSRect(x: content.minX, y: content.minY, width: max(0, leftArea.maxX - 8 - content.minX), height: content.height),
                rightContentRect: NSRect(x: rightArea.minX + 8, y: content.minY, width: max(0, content.maxX - rightArea.minX - 8), height: content.height),
                isNotched: true
            )
        }

        let width = min(max(180, visibleFrame.width), 200)
        let panelX = min(
            max(screenFrame.midX - width / 2, screenFrame.minX),
            max(screenFrame.minX, screenFrame.maxX - width)
        )
        let panelFrame = NSRect(
            x: panelX,
            y: top - bandHeight,
            width: min(width, screenFrame.width),
            height: bandHeight
        )
        let contentRect = inset(
            panelFrame,
            horizontal: horizontalPadding,
            vertical: verticalPadding
        )
        let gap: CGFloat = min(12, max(6, contentRect.width * 0.04))
        let leftWidth = max(1, contentRect.width * 0.58 - gap / 2)
        let leftContentRect = NSRect(
            x: contentRect.minX,
            y: contentRect.minY,
            width: min(leftWidth, contentRect.width),
            height: contentRect.height
        )
        let rightContentRect = NSRect(
            x: min(contentRect.maxX - max(1, contentRect.width - leftWidth - gap), contentRect.maxX),
            y: contentRect.minY,
            width: max(1, contentRect.width - leftWidth - gap),
            height: contentRect.height
        )
        return Self(
            panelFrame: panelFrame,
            leftContentRect: leftContentRect,
            rightContentRect: rightContentRect,
            isNotched: isNotched
        )
    }

    private static func inset(_ rect: NSRect, horizontal: CGFloat, vertical: CGFloat) -> NSRect {
        guard !rect.isEmpty else { return .zero }
        return rect.insetBy(
            dx: min(horizontal, rect.width / 2),
            dy: min(vertical, rect.height / 2)
        )
    }
}

enum TopNotchHistoryGeometry {
    static let defaultPanelSize = NSSize(width: 1_080, height: 276)
    static let minimumPanelSize = NSSize(width: 560, height: 220)
    static let pasteStackPanelSize = NSSize(width: 1_080, height: 224)
    static let pasteStackMinimumPanelSize = NSSize(width: 560, height: 190)
    static let topCornerRadius: CGFloat = 32
    static let bottomCornerRadius: CGFloat = 36
    static let contentHorizontalInset = topCornerRadius + 14
    private static let notchlessRevealWidth: CGFloat = 160

    /// Returns a frame anchored to the physical top edge of the display. On a
    /// notched display the content can still inset below the camera band.
    /// The function only consumes geometry values, which keeps placement
    /// deterministic and makes it safe to test without a live display.
    static func frame(
        screenFrame: NSRect,
        visibleFrame: NSRect,
        safeAreaInsets: NSEdgeInsets,
        auxiliaryTopLeftArea: NSRect? = nil,
        auxiliaryTopRightArea: NSRect? = nil,
        panelSize: NSSize = defaultPanelSize
    ) -> NSRect {
        let width = max(1, min(panelSize.width, visibleFrame.width))
        let height = max(1, min(panelSize.height, visibleFrame.height))
        let topAnchor = screenFrame.maxY
        let minX = visibleFrame.minX
        let maxX = max(minX, visibleFrame.maxX - width)
        let notchCenter = notchCenterX(
            screenFrame: screenFrame,
            auxiliaryTopLeftArea: auxiliaryTopLeftArea,
            auxiliaryTopRightArea: auxiliaryTopRightArea
        )
        let x = min(max(notchCenter - width / 2, minX), maxX)
        let y = max(screenFrame.minY, topAnchor - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private static func notchCenterX(
        screenFrame: NSRect,
        auxiliaryTopLeftArea: NSRect?,
        auxiliaryTopRightArea: NSRect?
    ) -> CGFloat {
        guard let auxiliaryTopLeftArea,
              let auxiliaryTopRightArea,
              auxiliaryTopRightArea.minX > auxiliaryTopLeftArea.maxX
        else {
            return screenFrame.midX
        }
        return (auxiliaryTopLeftArea.maxX + auxiliaryTopRightArea.minX) / 2
    }

    static func collapsedFrame(
        from expandedFrame: NSRect,
        safeAreaInsets: NSEdgeInsets = NSEdgeInsets(),
        auxiliaryTopLeftArea: NSRect? = nil,
        auxiliaryTopRightArea: NSRect? = nil
    ) -> NSRect {
        let cameraGapWidth: CGFloat? = {
            guard safeAreaInsets.top > 0,
                  let auxiliaryTopLeftArea,
                  let auxiliaryTopRightArea,
                  auxiliaryTopRightArea.minX > auxiliaryTopLeftArea.maxX
            else { return nil }
            return auxiliaryTopRightArea.minX - auxiliaryTopLeftArea.maxX
        }()
        // Keep the closed mask fully behind the physical camera housing. The
        // expanded shape supplies its own curved shoulders during the morph;
        // carrying those shoulders into the endpoint leaves visible black ears.
        let revealWidth = cameraGapWidth ?? notchlessRevealWidth
        let width = max(1, min(expandedFrame.width, revealWidth))
        let height = safeAreaInsets.top > 0
            ? max(1, min(expandedFrame.height, safeAreaInsets.top))
            : 1
        return NSRect(
            x: expandedFrame.midX - width / 2,
            y: expandedFrame.maxY - height,
            width: width,
            height: height
        )
    }
}

enum TopNotchDisplaySelection {
    static func resolvedPreferredDisplayID(
        preferredDisplayID: CGDirectDisplayID?,
        availableDisplayIDs: [CGDirectDisplayID]
    ) -> CGDirectDisplayID? {
        guard let preferredDisplayID,
              availableDisplayIDs.contains(preferredDisplayID)
        else { return nil }
        return preferredDisplayID
    }
}

@MainActor
final class TopNotchHistoryLayoutModel: ObservableObject {
    @Published var topContentInset: CGFloat = 0
}

final class TopNotchHistorySurfaceView: NSView {
    private let shapeMask = CAShapeLayer()
    private weak var presentationContentView: NSView?
    private var maskTarget: MaskTarget = .expanded
    private var interactiveRegions: [CGRect]?
    private var trackingAreasStorage: [NSTrackingArea] = []

    var onPointerEntered: (() -> Void)?
    var onPointerExited: (() -> Void)?

    private enum MaskTarget {
        case expanded
        case compact(CGRect)
        case compactRegions([CGRect])
    }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureSurface()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureSurface()
    }

    override func layout() {
        super.layout()
        updateMaskForCurrentLayout()
    }

    private func configureSurface() {
        wantsLayer = true
        layer?.isGeometryFlipped = true
        shapeMask.fillColor = NSColor.black.cgColor
        layer?.mask = shapeMask
    }

    func attachPresentationContentView(_ view: NSView) {
        presentationContentView = view
    }

    func prepareForReveal(from compactRect: CGRect) {
        shapeMask.removeAllAnimations()
        maskTarget = .compact(compactRect)
        updateMaskForCurrentLayout()
        presentationContentView?.alphaValue = 0
    }

    func prepareForExpandedPresentation(preservingContentAlpha: Bool = false) {
        shapeMask.removeAllAnimations()
        maskTarget = .expanded
        updateMaskForCurrentLayout()
        let presentationAlpha: CGFloat
        if preservingContentAlpha,
           let opacity = presentationContentView?.layer?.presentation()?.opacity {
            presentationAlpha = CGFloat(opacity)
        } else if preservingContentAlpha {
            presentationAlpha = presentationContentView?.alphaValue ?? 1
        } else {
            presentationAlpha = 0
        }
        presentationContentView?.layer?.removeAllAnimations()
        presentationContentView?.alphaValue = presentationAlpha
    }

    func showCompactSurface(regions: [CGRect]) {
        shapeMask.removeAllAnimations()
        maskTarget = .compactRegions(regions)
        updateMaskForCurrentLayout()
        presentationContentView?.layer?.removeAllAnimations()
        presentationContentView?.alphaValue = 1
    }

    func animateStackReveal(from rect: CGRect, duration: TimeInterval, reversing: Bool) {
        if !reversing {
            shapeMask.removeAllAnimations()
            maskTarget = .compactRegions([rect])
            updateMaskForCurrentLayout()
            presentationContentView?.alphaValue = 0
        }
        animateMask(to: .expanded, duration: duration, startsFromPresentation: reversing)
    }

    func animateStackCollapse(to rect: CGRect, duration: TimeInterval) {
        animateMask(to: .compactRegions([rect]), duration: duration, startsFromPresentation: true)
    }

    func animateReveal(duration: TimeInterval) {
        // `prepareForReveal` updates the model layer before the panel is ordered
        // onscreen. Its presentation layer can still contain the previous
        // expanded path until the next Core Animation commit, so revealing from
        // that path would collapse into an expanded-to-expanded no-op.
        animateMask(to: .expanded, duration: duration, startsFromPresentation: false)
    }

    func animateDismiss(to compactRect: CGRect, duration: TimeInterval) {
        animateMask(to: .compact(compactRect), duration: duration, startsFromPresentation: true)
    }

    func animateDismiss(toCompactRegions regions: [CGRect], duration: TimeInterval) {
        // Fade content while the window changes to its compact frame, then
        // install the compact mask at the endpoint.
        maskTarget = .compactRegions(regions)
        updateMaskForCurrentLayout()
        animateContentAlpha(to: 0, duration: duration)
    }

    func restoreExpandedPresentation() {
        shapeMask.removeAllAnimations()
        maskTarget = .expanded
        updateMaskForCurrentLayout()
        presentationContentView?.alphaValue = 1
    }

    func animateContentAlpha(to alpha: CGFloat) {
        presentationContentView?.animator().alphaValue = alpha
    }

    func animateContentAlpha(to alpha: CGFloat, duration: TimeInterval) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            presentationContentView?.animator().alphaValue = alpha
        }
    }

    func setInteractiveRegions(_ regions: [CGRect]?) {
        interactiveRegions = regions
        rebuildTrackingAreas()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        rebuildTrackingAreas()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let interactiveRegions,
           !interactiveRegions.contains(where: { $0.contains(point) }) {
            return nil
        }
        return super.hitTest(point)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onPointerEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onPointerExited?()
    }

    private func animateMask(
        to target: MaskTarget,
        duration: TimeInterval,
        startsFromPresentation: Bool
    ) {
        layoutSubtreeIfNeeded()
        let modelPath = shapeMask.path ?? path(for: maskTarget)
        let fromPath = Self.animationStartPath(
            modelPath: modelPath,
            presentationPath: shapeMask.presentation()?.path,
            startsFromPresentation: startsFromPresentation
        )
        let toPath = path(for: target)
        maskTarget = target

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeMask.path = toPath
        CATransaction.commit()

        let animation = CABasicAnimation(keyPath: "path")
        animation.fromValue = fromPath
        animation.toValue = toPath
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(
            controlPoints: 0.23,
            1,
            0.32,
            1
        )
        shapeMask.add(animation, forKey: "topNotchMaskTransition")
    }

    static func animationStartPath(
        modelPath: CGPath,
        presentationPath: CGPath?,
        startsFromPresentation: Bool
    ) -> CGPath {
        startsFromPresentation ? (presentationPath ?? modelPath) : modelPath
    }

    private func updateMaskForCurrentLayout() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeMask.frame = bounds
        shapeMask.path = path(for: maskTarget)
        CATransaction.commit()
    }

    private func path(for target: MaskTarget) -> CGPath {
        switch target {
        case .expanded:
            Self.surfacePath(in: bounds)
        case let .compact(rect):
            Self.surfacePath(in: rect.intersection(bounds))
        case let .compactRegions(regions):
            Self.compactSurfacePath(for: regions.map { $0.intersection(bounds) })
        }
    }

    private func rebuildTrackingAreas() {
        trackingAreasStorage.forEach(removeTrackingArea)
        trackingAreasStorage.removeAll(keepingCapacity: true)
        guard let interactiveRegions else { return }
        for rect in interactiveRegions where !rect.isEmpty {
            let trackingArea = NSTrackingArea(
                rect: rect,
                options: [.mouseEnteredAndExited, .activeAlways],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(trackingArea)
            trackingAreasStorage.append(trackingArea)
        }
    }

    static func surfacePath(in bounds: CGRect, topCornerRadius: CGFloat = TopNotchHistoryGeometry.topCornerRadius, bottomCornerRadius: CGFloat = TopNotchHistoryGeometry.bottomCornerRadius) -> CGPath {
        let topRadius = min(
            topCornerRadius,
            bounds.width / 4,
            bounds.height
        )
        let bottomRadius = min(
            bottomCornerRadius,
            max(0, (bounds.width - topRadius * 2) / 2),
            max(0, bounds.height - topRadius)
        )
        let path = CGMutablePath()

        // The top ears remain flush with the display edge and curl inward to
        // the panel walls. Bottom corners continue from those same walls, so
        // the outline has no flare or pointed wing at either lower corner.
        path.move(to: CGPoint(x: bounds.minX, y: bounds.minY))
        path.addQuadCurve(
            to: CGPoint(x: bounds.minX + topRadius, y: bounds.minY + topRadius),
            control: CGPoint(x: bounds.minX + topRadius, y: bounds.minY)
        )
        path.addLine(to: CGPoint(x: bounds.minX + topRadius, y: bounds.maxY - bottomRadius))
        path.addQuadCurve(
            to: CGPoint(x: bounds.minX + topRadius + bottomRadius, y: bounds.maxY),
            control: CGPoint(x: bounds.minX + topRadius, y: bounds.maxY)
        )
        path.addLine(to: CGPoint(
            x: bounds.maxX - topRadius - bottomRadius,
            y: bounds.maxY
        ))
        path.addQuadCurve(
            to: CGPoint(x: bounds.maxX - topRadius, y: bounds.maxY - bottomRadius),
            control: CGPoint(x: bounds.maxX - topRadius, y: bounds.maxY)
        )
        path.addLine(to: CGPoint(x: bounds.maxX - topRadius, y: bounds.minY + topRadius))
        path.addQuadCurve(
            to: CGPoint(x: bounds.maxX, y: bounds.minY),
            control: CGPoint(x: bounds.maxX - topRadius, y: bounds.minY)
        )
        path.addLine(to: CGPoint(x: bounds.minX, y: bounds.minY))
        path.closeSubpath()
        return path
    }

    static func compactSurfacePath(for regions: [CGRect]) -> CGPath {
        let path = CGMutablePath()
        for region in regions where !region.isEmpty {
            path.addPath(surfacePath(in: region, topCornerRadius: 8, bottomCornerRadius: 10))
        }
        return path
    }
}

protocol TopNotchScreenProviding: AnyObject {
    func currentScreen() -> NSScreen?
}

final class SystemTopNotchScreenProvider: TopNotchScreenProviding {
    func currentScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}

struct TopNotchHistoryCollectionApplyPlan: Equatable {
    let reloadData: Bool
    let thumbnailEntryIDs: [UUID]
    let cardEntryIDs: [UUID]

    init(reloadData: Bool, thumbnailEntryIDs: [UUID], cardEntryIDs: [UUID] = []) {
        self.reloadData = reloadData
        self.thumbnailEntryIDs = thumbnailEntryIDs
        self.cardEntryIDs = cardEntryIDs
    }
}

enum TopNotchHistoryCollectionReconciler {
    /// Per-entry revisions survive SwiftUI coalescing, so each visible card is
    /// refreshed only when its own thumbnail revision advanced.
    static func plan(
        force: Bool,
        lastRevision: Int,
        lastIDs: [UUID],
        snapshotRevision: Int,
        ids: [UUID],
        thumbnailUpdateRevisionsByEntryID: [UUID: Int],
        lastThumbnailUpdateRevisionsByEntryID: [UUID: Int],
        visibleEntryIDs: Set<UUID>,
        lastCards: [TopNotchHistoryCardDescriptor]? = nil,
        cards: [TopNotchHistoryCardDescriptor]? = nil
    ) -> TopNotchHistoryCollectionApplyPlan {
        guard !force, lastIDs == ids else {
            return TopNotchHistoryCollectionApplyPlan(reloadData: true, thumbnailEntryIDs: [])
        }
        if lastRevision != snapshotRevision, (lastCards == nil || cards == nil) {
            return TopNotchHistoryCollectionApplyPlan(reloadData: true, thumbnailEntryIDs: [])
        }
        return TopNotchHistoryCollectionApplyPlan(
            reloadData: false,
            thumbnailEntryIDs: ids.filter {
                visibleEntryIDs.contains($0)
                    && (thumbnailUpdateRevisionsByEntryID[$0] ?? -1)
                        > (lastThumbnailUpdateRevisionsByEntryID[$0] ?? -1)
            },
            cardEntryIDs: zip(lastCards ?? [], cards ?? []).compactMap { previous, current in
                previous != current ? current.id : nil
            }
        )
    }

    static func selectionNeedsUpdate(
        current: Set<IndexPath>,
        target: IndexPath?
    ) -> Bool {
        current != (target.map { Set([$0]) } ?? [])
    }
}

final class TopNotchHistoryInteractionBridge {
    private weak var collectionView: NSCollectionView?
    private var entryIDs: [UUID] = []

    func attach(collectionView: NSCollectionView) {
        self.collectionView = collectionView
    }

    func applySnapshot(entryIDs: [UUID], selectedEntryID: UUID?) {
        self.entryIDs = entryIDs
        applySelection(id: selectedEntryID, scroll: false)
    }

    /// A reused collection retains its clip origin even when the first card is
    /// already selected. Reset it explicitly for each user-initiated show, after
    /// panel layout and before the reveal animation.
    func resetViewportToStart() {
        guard let scrollView = collectionView?.enclosingScrollView else { return }
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func applySelection(id: UUID?, scroll: Bool = true) {
        guard let collectionView else { return }
        let targetIndexPath: IndexPath? = id.flatMap { entryID in
            entryIDs.firstIndex(of: entryID).map { IndexPath(item: $0, section: 0) }
        }
        if TopNotchHistoryCollectionReconciler.selectionNeedsUpdate(
            current: collectionView.selectionIndexPaths,
            target: targetIndexPath
        ) {
            collectionView.deselectAll(nil)
            if let targetIndexPath {
                collectionView.selectItems(at: [targetIndexPath], scrollPosition: [])
            }
        }
        if scroll, let targetIndexPath {
            collectionView.scrollToItems(
                at: [targetIndexPath],
                scrollPosition: .centeredHorizontally
            )
        }
    }
}

enum TopNotchHistoryCardKind: Equatable {
    case text
    case url
    case image
    case file
    case video

    var title: String {
        switch self {
        case .text: "Text"
        case .url: "URL"
        case .image: "Image"
        case .file: "File"
        case .video: "Video"
        }
    }

    var symbolName: String {
        switch self {
        case .text: "doc.on.clipboard"
        case .url: "link"
        case .image: "photo"
        case .file: "doc"
        case .video: "film"
        }
    }
}

struct TopNotchHistoryCardDescriptor: Equatable {
    let id: UUID
    let isFavorite: Bool
    let kind: TopNotchHistoryCardKind
    let title: String
    let detail: String
    let accessibilityLabel: String

    static func make(entry: HistoryEntry) -> Self {
        make(descriptor: HistoryOccurrenceDescriptor(
            id: entry.id,
            activityAt: entry.activityAt,
            isFavorite: entry.isFavorite,
            textPreview: entry.isTextOnly ? HistoryPreview.text(for: entry.text) : nil,
            representations: entry.representations,
            imageMetadata: entry.imageMetadata,
            referenceMetadata: entry.referenceMetadata
        ))
    }

    static func make(descriptor: HistoryOccurrenceDescriptor) -> Self {
        let kind: TopNotchHistoryCardKind
        if descriptor.representations.contains(where: { $0.kind == .inlineImage }) {
            kind = .image
        } else if descriptor.representations.contains(where: { $0.kind == .videoReference }) {
            kind = .video
        } else if descriptor.representations.contains(where: { $0.kind == .fileReference }) {
            kind = .file
        } else if descriptor.representations.contains(where: { $0.kind == .url }) {
            kind = .url
        } else {
            kind = .text
        }

        let detail: String
        switch kind {
        case .text:
            detail = descriptor.textPreview ?? ""
        case .image:
            let dimensions = descriptor.imageMetadata.first.map { "\($0.pixelWidth) × \($0.pixelHeight)" }
            detail = dimensions ?? "Image"
        case .url:
            detail = descriptor.referenceMetadata.first?.domain
                ?? descriptor.referenceMetadata.first?.searchText
                ?? "URL"
        case .file, .video:
            if let metadata = descriptor.referenceMetadata.first {
                detail = metadata.availability == .unavailable
                    ? "Unavailable: \(metadata.displayName)"
                    : metadata.displayName
            } else {
                detail = kind.title
            }
        }
        let boundedDetail = HistoryPreview.text(for: detail)
        return Self(
            id: descriptor.id,
            isFavorite: descriptor.isFavorite,
            kind: kind,
            title: kind.title,
            detail: boundedDetail,
            accessibilityLabel: "\(kind.title): \(boundedDetail)"
        )
    }
}

struct TopNotchHistoryShelfView: View {
    @ObservedObject var viewModel: HistoryViewModel
    @ObservedObject var permissionService: AccessibilityPermissionService
    @ObservedObject var layoutModel: TopNotchHistoryLayoutModel
    let openAccessibilitySettings: () -> Void
    let pasteEntry: (UUID) -> Void
    let close: () -> Void
    let interactionBridge: TopNotchHistoryInteractionBridge
    @FocusState private var searchIsFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 10) {
                searchField
                if let notice = viewModel.captureNotice {
                    Label(notice, systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                content
                footer
            }
            .padding(.top, layoutModel.topContentInset + 14)
            .padding(.horizontal, TopNotchHistoryGeometry.contentHorizontalInset)
            .padding(.bottom, 14)

            favoriteToggle
                .padding(.top, 14)
                .padding(.leading, TopNotchHistoryGeometry.contentHorizontalInset)
        }
        .frame(
            minWidth: TopNotchHistoryGeometry.minimumPanelSize.width,
            idealWidth: TopNotchHistoryGeometry.defaultPanelSize.width,
            maxWidth: .infinity,
            minHeight: TopNotchHistoryGeometry.minimumPanelSize.height,
            idealHeight: TopNotchHistoryGeometry.defaultPanelSize.height,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .environment(\.colorScheme, .dark)
        .onAppear {
            HistoryKeyboardActionScheduler.deferToNextMainRunLoop {
                searchIsFocused = true
            }
        }
        .onChange(of: viewModel.searchFocusRequestID) { _, _ in
            HistoryKeyboardActionScheduler.deferToNextMainRunLoop {
                searchIsFocused = true
            }
        }
    }

    private var favoriteToggle: some View {
        Button {
            viewModel.switchMode(to: viewModel.mode == .history ? .favorites : .history)
        } label: {
            Image(systemName: viewModel.mode == .favorites ? "star.fill" : "star")
                .frame(width: 18, height: 18)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .foregroundStyle(viewModel.mode == .favorites ? .yellow : .secondary)
        .contentShape(Rectangle())
        .accessibilityLabel(viewModel.mode == .favorites ? "Show all History" : "Show Favorites")
        .accessibilityValue(viewModel.mode == .favorites ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(viewModel.mode == .favorites ? "Search favorites" : "Search history", text: Binding(
                get: { viewModel.query },
                set: { viewModel.updateQuery($0) }
            ))
            .textFieldStyle(.plain)
            .focused($searchIsFocused)
            .accessibilityIdentifier("top-notch-history-search")
            .accessibilityHint("Type to filter history. Use Left and Right Arrow to choose an entry.")
            .background {
                TopNotchHistoryDeleteKeyMonitor(
                    isSearchFocused: { searchIsFocused },
                    query: { viewModel.query },
                    selectedEntryID: { viewModel.selectedEntryID },
                    onDelete: { id in
                        HistoryKeyboardActionScheduler.deferToNextMainRunLoop {
                            Task { @MainActor in await viewModel.delete(id: id) }
                        }
                    }
                )
                .frame(width: 0, height: 0)
            }
            Spacer(minLength: 0)
            Button(action: close) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close History")
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView("Loading history…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            Group {
                if viewModel.mode == .favorites {
                    ContentUnavailableView("No Favorites Yet", systemImage: "star", description: Text("Star a History card to find it here."))
                } else {
                    ContentUnavailableView("No History Yet", systemImage: "clipboard", description: Text("Copied items will appear here while Qipli is running."))
                }
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        case let .list(descriptors):
            if descriptors.isEmpty {
                if viewModel.isSearchInProgress {
                    ProgressView("Searching…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView(
                        viewModel.mode == .favorites ? "No Matching Favorites" : "No Matching History",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different search term.")
                    )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            } else {
                let cards = descriptors.map(TopNotchHistoryCardDescriptor.make(descriptor:))
                TopNotchHistoryCollectionView(
                    cards: cards,
                    snapshotRevision: viewModel.visibleSnapshotRevision,
                    thumbnailUpdateRevisionsByEntryID: viewModel.thumbnailUpdateRevisionsByEntryID,
                    selectedEntryID: viewModel.selectedEntryID,
                    interactionBridge: interactionBridge,
                    thumbnailData: viewModel.thumbnailData(for:),
                    requestThumbnail: viewModel.requestThumbnail(forEntryID:),
                    selectEntry: viewModel.select,
                    pasteEntry: { id in
                        guard canPaste else { return }
                        pasteEntry(id)
                    },
                    toggleFavorite: { id, isFavorite in
                        Task { @MainActor in await viewModel.setFavorite(id: id, isFavorite: isFavorite) }
                    },
                    loadMore: {
                        Task { @MainActor in await viewModel.loadMore() }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .error:
            VStack(spacing: 8) {
                Text("History is unavailable.").font(.headline)
                Text("Qipli could not read local history. Your system clipboard was not changed.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    Task { @MainActor in await viewModel.reload() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let failure = viewModel.pasteFailure {
                Text(failure.message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Paste failed. \(failure.message)")
            }
            if let favoriteFailure = viewModel.favoriteFailure {
                HStack(spacing: 8) {
                    Text(favoriteFailure.message)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Button("Retry") {
                        Task { @MainActor in await viewModel.retryFavorite() }
                    }
                    .font(.caption)
                }
                .accessibilityElement(children: .combine)
            }
            HStack(spacing: 8) {
                if permissionService.state != .granted {
                    Button("Open Accessibility Settings", action: openAccessibilitySettings)
                        .font(.caption)
                }
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    keyboardHintKey(systemName: "arrow.left")
                    keyboardHintKey(systemName: "arrow.right")
                    Text("Navigate  ·")
                    keyboardHintKey(systemName: "return")
                    Text("Paste  ·")
                    keyboardHintKey(systemName: "shift")
                    keyboardHintKey(systemName: "return")
                    Text("Plain")
                }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Use Left and Right Arrow to navigate. Press Return to paste with formatting. Press Shift-Return to paste as plain text.")
            }
        }
    }

    private var canPaste: Bool {
        permissionService.state == .granted && !viewModel.isPasteInProgress
    }

    private func keyboardHintKey(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 8, weight: .semibold))
            .frame(width: 14, height: 13)
            .background {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    }
            }
            .accessibilityHidden(true)
    }
}

struct TopNotchHistoryCollectionView: NSViewRepresentable {
    let cards: [TopNotchHistoryCardDescriptor]
    let snapshotRevision: Int
        let thumbnailUpdateRevisionsByEntryID: [UUID: Int]
    let selectedEntryID: UUID?
    let interactionBridge: TopNotchHistoryInteractionBridge
    let thumbnailData: (UUID) -> Data?
    let requestThumbnail: (UUID) -> Void
    let selectEntry: (UUID) -> Void
    let pasteEntry: (UUID) -> Void
    let toggleFavorite: (UUID, Bool) -> Void
    let loadMore: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let layout = NSCollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = NSSize(width: 220, height: 168)
        layout.minimumInteritemSpacing = 10
        layout.minimumLineSpacing = 10
        layout.sectionInset = NSEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)

        let collectionView = NSCollectionView()
        collectionView.collectionViewLayout = layout
        collectionView.isSelectable = true
        collectionView.allowsEmptySelection = true
        collectionView.allowsMultipleSelection = false
        collectionView.backgroundColors = [.clear]
        collectionView.register(
            TopNotchHistoryCollectionItem.self,
            forItemWithIdentifier: TopNotchHistoryCollectionItem.identifier
        )
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.setAccessibilityLabel("History cards")

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = collectionView
        interactionBridge.attach(collectionView: collectionView)
        context.coordinator.apply(parent: self, to: collectionView, force: true)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let collectionView = scrollView.documentView as? NSCollectionView else { return }
        context.coordinator.apply(parent: self, to: collectionView, force: false)
    }

    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        private var parent: TopNotchHistoryCollectionView
        private var lastRevision = -1
        private var lastIDs: [UUID] = []
        private var lastCards: [TopNotchHistoryCardDescriptor] = []
        private var lastThumbnailUpdateRevisionsByEntryID: [UUID: Int] = [:]
        private var isApplyingSelection = false

        init(parent: TopNotchHistoryCollectionView) { self.parent = parent }

        func apply(parent: TopNotchHistoryCollectionView, to collectionView: NSCollectionView, force: Bool) {
            self.parent = parent
            let ids = parent.cards.map(\.id)
            let visibleIndexPaths = collectionView.indexPathsForVisibleItems()
            let visibleEntryIDs: Set<UUID> = Set(visibleIndexPaths.compactMap { indexPath in
                guard parent.cards.indices.contains(indexPath.item) else { return nil }
                return parent.cards[indexPath.item].id
            })
            let plan = TopNotchHistoryCollectionReconciler.plan(
                force: force,
                lastRevision: lastRevision,
                lastIDs: lastIDs,
                snapshotRevision: parent.snapshotRevision,
                ids: ids,
                thumbnailUpdateRevisionsByEntryID: parent.thumbnailUpdateRevisionsByEntryID,
                lastThumbnailUpdateRevisionsByEntryID: lastThumbnailUpdateRevisionsByEntryID,
                visibleEntryIDs: visibleEntryIDs,
                lastCards: lastCards,
                cards: parent.cards
            )
            if plan.reloadData {
                lastRevision = parent.snapshotRevision
                lastIDs = ids
                lastCards = parent.cards
                collectionView.reloadData()
                lastThumbnailUpdateRevisionsByEntryID = parent.thumbnailUpdateRevisionsByEntryID
            } else {
                lastRevision = parent.snapshotRevision
                lastCards = parent.cards
                if plan.thumbnailEntryIDs.isEmpty == false {
                    for thumbnailEntryID in plan.thumbnailEntryIDs {
                        let indexPath = IndexPath(
                            item: ids.firstIndex(of: thumbnailEntryID) ?? NSNotFound,
                            section: 0
                        )
                        if let item = collectionView.item(at: indexPath) as? TopNotchHistoryCollectionItem {
                            item.updateThumbnail(data: parent.thumbnailData(thumbnailEntryID))
                        }
                        lastThumbnailUpdateRevisionsByEntryID[thumbnailEntryID] =
                            parent.thumbnailUpdateRevisionsByEntryID[thumbnailEntryID]
                    }
                }
                for entryID in plan.cardEntryIDs {
                    let indexPath = IndexPath(item: ids.firstIndex(of: entryID) ?? NSNotFound, section: 0)
                    if let item = collectionView.item(at: indexPath) as? TopNotchHistoryCollectionItem,
                       let card = parent.cards.first(where: { $0.id == entryID }) {
                        item.updateFavorite(card.isFavorite)
                    }
                }
            }
            isApplyingSelection = true
            parent.interactionBridge.applySnapshot(
                entryIDs: parent.cards.map(\.id),
                selectedEntryID: parent.selectedEntryID
            )
            isApplyingSelection = false
        }

        func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            parent.cards.count
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            itemForRepresentedObjectAt indexPath: IndexPath
        ) -> NSCollectionViewItem {
            let item = collectionView.makeItem(
                withIdentifier: TopNotchHistoryCollectionItem.identifier,
                for: indexPath
            ) as? TopNotchHistoryCollectionItem ?? TopNotchHistoryCollectionItem()
            let card = parent.cards[indexPath.item]
            item.configure(
                card: card,
                thumbnailData: parent.thumbnailData(card.id),
                isSelected: indexPath.item == parent.cards.firstIndex(where: { $0.id == parent.selectedEntryID }),
                requestThumbnail: { [weak self] in self?.parent.requestThumbnail(card.id) },
                doubleClick: { [weak self] in self?.parent.pasteEntry(card.id) },
                toggleFavorite: { [weak self] isFavorite in
                    self?.parent.toggleFavorite(card.id, isFavorite)
                }
            )
            return item
        }

        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
            guard !isApplyingSelection, let indexPath = indexPaths.first,
                  parent.cards.indices.contains(indexPath.item)
            else { return }
            parent.selectEntry(parent.cards[indexPath.item].id)
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            willDisplay item: NSCollectionViewItem,
            forRepresentedObjectAt indexPath: IndexPath
        ) {
            guard indexPath.item >= max(0, parent.cards.count - 10) else { return }
            parent.loadMore()
        }
    }
}

private final class TopNotchHistoryCollectionItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("TopNotchHistoryCollectionItem")
    private let cardView = TopNotchHistoryCardView()

    override var isSelected: Bool {
        didSet { cardView.updateSelection(isSelected) }
    }

    override func loadView() { view = cardView }

    func configure(
        card: TopNotchHistoryCardDescriptor,
        thumbnailData: Data?,
        isSelected: Bool,
        requestThumbnail: @escaping () -> Void,
        doubleClick: @escaping () -> Void,
        toggleFavorite: @escaping (Bool) -> Void
    ) {
        cardView.configure(
            card: card,
            thumbnailData: thumbnailData,
            isSelected: isSelected,
            requestThumbnail: requestThumbnail,
            doubleClick: doubleClick,
            toggleFavorite: toggleFavorite
        )
    }

    func updateThumbnail(data: Data?) {
        cardView.updateThumbnail(data: data)
    }

    func updateFavorite(_ isFavorite: Bool) {
        cardView.updateFavorite(isFavorite)
    }
}

enum HistoryDeletePhysicalKey: Equatable {
    case backspace
    case forwardDelete
    case other
}

struct HistoryDeleteKeyEvent: Equatable {
    let key: HistoryDeletePhysicalKey
    let hasOnlyShiftModifier: Bool
    let isRepeat: Bool

    init(key: HistoryDeletePhysicalKey, hasOnlyShiftModifier: Bool, isRepeat: Bool) {
        self.key = key
        self.hasOnlyShiftModifier = hasOnlyShiftModifier
        self.isRepeat = isRepeat
    }

    init(event: NSEvent) {
        let key: HistoryDeletePhysicalKey = switch event.keyCode {
        case 51: .backspace
        case 117: .forwardDelete
        default: .other
        }
        self.init(
            key: key,
            hasOnlyShiftModifier: event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .shift,
            isRepeat: event.isARepeat
        )
    }
}

enum HistoryDeleteKeyAdmission {
    static func selectedEntryID(
        for event: HistoryDeleteKeyEvent,
        isEventInHistoryWindow: Bool,
        isSearchFocused: Bool,
        query: String,
        selectedEntryID: UUID?
    ) -> UUID? {
        _ = query
        guard isEventInHistoryWindow,
              isSearchFocused,
              event.key == .backspace,
              event.hasOnlyShiftModifier,
              !event.isRepeat
        else { return nil }
        return selectedEntryID
    }
}

private struct TopNotchHistoryDeleteKeyMonitor: NSViewRepresentable {
    let isSearchFocused: () -> Bool
    let query: () -> String
    let selectedEntryID: () -> UUID?
    let onDelete: (UUID) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.configure(
            isSearchFocused: isSearchFocused,
            query: query,
            selectedEntryID: selectedEntryID,
            onDelete: onDelete
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isSearchFocused: isSearchFocused,
            query: query,
            selectedEntryID: selectedEntryID,
            onDelete: onDelete
        )
    }

    final class Coordinator {
        private var isSearchFocused: () -> Bool
        private var query: () -> String
        private var selectedEntryID: () -> UUID?
        private var onDelete: (UUID) -> Void
        private weak var hostView: NSView?
        private var monitor: Any?

        init(
            isSearchFocused: @escaping () -> Bool,
            query: @escaping () -> String,
            selectedEntryID: @escaping () -> UUID?,
            onDelete: @escaping (UUID) -> Void
        ) {
            self.isSearchFocused = isSearchFocused
            self.query = query
            self.selectedEntryID = selectedEntryID
            self.onDelete = onDelete
        }

        func attach(to view: NSView) {
            hostView = view
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.process(event) ?? event
            }
        }

        func configure(
            isSearchFocused: @escaping () -> Bool,
            query: @escaping () -> String,
            selectedEntryID: @escaping () -> UUID?,
            onDelete: @escaping (UUID) -> Void
        ) {
            self.isSearchFocused = isSearchFocused
            self.query = query
            self.selectedEntryID = selectedEntryID
            self.onDelete = onDelete
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }

        private func process(_ event: NSEvent) -> NSEvent? {
            guard let hostView,
                  hostView.window === event.window,
                  let entryID = HistoryDeleteKeyAdmission.selectedEntryID(
                      for: HistoryDeleteKeyEvent(event: event),
                      isEventInHistoryWindow: hostView.window?.isKeyWindow == true,
                      isSearchFocused: isSearchFocused(),
                      query: query(),
                      selectedEntryID: selectedEntryID()
                  )
            else { return event }
            onDelete(entryID)
            return nil
        }
    }
}

private final class TopNotchAspectFillImageView: NSImageView {
    override func draw(_ dirtyRect: NSRect) {
        guard let image, image.size.width > 0, image.size.height > 0 else { return }
        let scale = max(
            bounds.width / image.size.width,
            bounds.height / image.size.height
        )
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let imageRect = NSRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1)
    }
}

final class TopNotchHistoryImageScrimView: NSView {
    private(set) var gradientLayer = CAGradientLayer()

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureGradient()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureGradient()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = bounds
        CATransaction.commit()
    }

    private func configureGradient() {
        wantsLayer = true
        gradientLayer.colors = [
            NSColor.clear.cgColor,
            NSColor.black.withAlphaComponent(0.44).cgColor,
            NSColor.black.withAlphaComponent(0.68).cgColor,
        ]
        gradientLayer.locations = [0, 0.55, 1]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        layer?.addSublayer(gradientLayer)
    }
}

enum TopNotchHistoryCardTextLayout {
    static let maximumNumberOfLines = 5

    static func configure(_ label: NSTextField) {
        label.isEditable = false
        label.isSelectable = false
        label.maximumNumberOfLines = maximumNumberOfLines
        label.lineBreakMode = .byWordWrapping
        guard let cell = label.cell as? NSTextFieldCell else { return }
        cell.wraps = true
        cell.truncatesLastVisibleLine = true
    }
}

private final class TopNotchHistoryCardView: NSView {
    private let iconView = NSImageView()
    private let favoriteButton = NSButton()
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private let thumbnailView = TopNotchAspectFillImageView()
    private let imageFallbackView = NSImageView()
    private let imageScrim = TopNotchHistoryImageScrimView()
    private var regularDetailTopConstraint: NSLayoutConstraint!
    private var regularDetailBottomConstraint: NSLayoutConstraint!
    private var imageDetailTopConstraint: NSLayoutConstraint!
    private var imageDetailBottomConstraint: NSLayoutConstraint!
    private var isImageCard = false
    private var requestThumbnail: (() -> Void)?
    private var doubleClick: (() -> Void)?
    private var toggleFavorite: ((Bool) -> Void)?
    private var isFavorite = false
    private var isSelected = false
    private var isHovered = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    func configure(
        card: TopNotchHistoryCardDescriptor,
        thumbnailData: Data?,
        isSelected: Bool,
        requestThumbnail: @escaping () -> Void,
        doubleClick: @escaping () -> Void,
        toggleFavorite: @escaping (Bool) -> Void
    ) {
        detailLabel.stringValue = card.detail
        iconView.image = NSImage(systemSymbolName: card.kind.symbolName, accessibilityDescription: card.title)
        isImageCard = card.kind == .image
        if isImageCard {
            updateThumbnail(data: thumbnailData)
        } else {
            thumbnailView.image = nil
            thumbnailView.isHidden = true
            imageFallbackView.isHidden = true
            imageScrim.isHidden = true
        }
        iconView.contentTintColor = card.kind == .image ? .white : .secondaryLabelColor
        detailLabel.textColor = card.kind == .image ? .white : .labelColor
        regularDetailTopConstraint.isActive = card.kind != .image
        regularDetailBottomConstraint.isActive = card.kind != .image
        imageDetailTopConstraint.isActive = card.kind == .image
        imageDetailBottomConstraint.isActive = card.kind == .image
        self.requestThumbnail = requestThumbnail
        self.doubleClick = doubleClick
        self.toggleFavorite = toggleFavorite
        updateFavorite(card.isFavorite)
        if card.kind == .image, thumbnailData == nil { requestThumbnail() }
        setAccessibilityLabel(card.accessibilityLabel)
        updateSelection(isSelected)
    }

    func updateThumbnail(data: Data?) {
        guard isImageCard else { return }
        let image = data.flatMap(NSImage.init(data:))
        thumbnailView.image = image
        thumbnailView.isHidden = image == nil
        imageFallbackView.isHidden = image != nil
        imageScrim.isHidden = false
    }

    func updateFavorite(_ isFavorite: Bool) {
        self.isFavorite = isFavorite
        favoriteButton.state = isFavorite ? .on : .off
        favoriteButton.image = NSImage(
            systemSymbolName: isFavorite ? "star.fill" : "star",
            accessibilityDescription: isFavorite ? "Favorite" : "Not Favorite"
        )
        favoriteButton.toolTip = isFavorite ? "Remove from Favorites" : "Add to Favorites"
        favoriteButton.setAccessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
        favoriteButton.setAccessibilityValue(isFavorite ? "On" : "Off")
        favoriteButton.isHidden = !(isFavorite || isSelected || isHovered)
    }

    @objc private func favoriteButtonPressed() {
        toggleFavorite?(!isFavorite)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for trackingArea in trackingAreas { removeTrackingArea(trackingArea) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        favoriteButton.isHidden = false
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        favoriteButton.isHidden = !(isFavorite || isSelected)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        if event.clickCount == 2 { doubleClick?() }
    }

    private func configureView() {
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
        layer?.borderWidth = 1

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = .secondaryLabelColor
        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.contentsGravity = .resizeAspectFill
        thumbnailView.layer?.masksToBounds = true
        imageFallbackView.image = NSImage(
            systemSymbolName: "photo",
            accessibilityDescription: "Image preview unavailable"
        )
        imageFallbackView.imageScaling = .scaleProportionallyUpOrDown
        imageFallbackView.contentTintColor = .secondaryLabelColor

        detailLabel.font = .systemFont(ofSize: 13, weight: .medium)
        TopNotchHistoryCardTextLayout.configure(detailLabel)

        favoriteButton.isBordered = false
        favoriteButton.imagePosition = .imageOnly
        favoriteButton.contentTintColor = .secondaryLabelColor
        favoriteButton.target = self
        favoriteButton.action = #selector(favoriteButtonPressed)
        favoriteButton.focusRingType = .default
        favoriteButton.setAccessibilityRole(.button)
        favoriteButton.isHidden = true

        for subview in [thumbnailView, imageFallbackView, imageScrim, iconView, detailLabel, favoriteButton] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }
        regularDetailTopConstraint = detailLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 8)
        regularDetailBottomConstraint = detailLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -14)
        imageDetailTopConstraint = detailLabel.topAnchor.constraint(greaterThanOrEqualTo: iconView.bottomAnchor, constant: 4)
        imageDetailBottomConstraint = detailLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        NSLayoutConstraint.activate([
            thumbnailView.leadingAnchor.constraint(equalTo: leadingAnchor),
            thumbnailView.trailingAnchor.constraint(equalTo: trailingAnchor),
            thumbnailView.topAnchor.constraint(equalTo: topAnchor),
            thumbnailView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageFallbackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageFallbackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageFallbackView.topAnchor.constraint(equalTo: topAnchor),
            imageFallbackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageScrim.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageScrim.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageScrim.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageScrim.heightAnchor.constraint(equalToConstant: 66),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            favoriteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            favoriteButton.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            favoriteButton.widthAnchor.constraint(equalToConstant: 24),
            favoriteButton.heightAnchor.constraint(equalToConstant: 24),
            detailLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
        ])
        regularDetailTopConstraint.isActive = true
        regularDetailBottomConstraint.isActive = true
        thumbnailView.isHidden = true
        imageFallbackView.isHidden = true
        imageScrim.isHidden = true
        setAccessibilityRole(.group)
    }

    fileprivate func updateSelection(_ isSelected: Bool) {
        self.isSelected = isSelected
        layer?.borderWidth = isSelected ? 2 : 1
        let baseColor = NSColor(calibratedWhite: 0.08, alpha: 1)
        layer?.backgroundColor = (isSelected ? NSColor.controlAccentColor : baseColor)
            .withAlphaComponent(isSelected ? 0.30 : 1)
            .cgColor
        layer?.borderColor = (isSelected ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        setAccessibilityValue(isSelected ? "Selected" : nil)
        favoriteButton.isHidden = !(isFavorite || isSelected || isHovered)
    }
}
