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

enum TopNotchHistoryGeometry {
    static let defaultPanelSize = NSSize(width: 1_080, height: 276)
    static let minimumPanelSize = NSSize(width: 560, height: 220)
    static let topCornerRadius: CGFloat = 32
    static let bottomCornerRadius: CGFloat = 36
    static let contentHorizontalInset = topCornerRadius + 14
    private static let notchlessRevealWidth: CGFloat = 160

    /// Returns a frame whose top edge covers the camera/menu-bar band on a
    /// notched display and whose content can inset below it independently.
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
        let hasCameraSafeArea = safeAreaInsets.top > 0
        let topAnchor = hasCameraSafeArea
            ? screenFrame.maxY
            : visibleFrame.maxY
        let minX = visibleFrame.minX
        let maxX = max(minX, visibleFrame.maxX - width)
        let notchCenter = notchCenterX(
            screenFrame: screenFrame,
            auxiliaryTopLeftArea: auxiliaryTopLeftArea,
            auxiliaryTopRightArea: auxiliaryTopRightArea
        )
        let x = min(max(notchCenter - width / 2, minX), maxX)
        let maxY = min(topAnchor, visibleFrame.maxY)
        let y = hasCameraSafeArea
            ? max(screenFrame.minY, topAnchor - height)
            : max(visibleFrame.minY, maxY - height)
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
        let revealWidth = cameraGapWidth.map { $0 + topCornerRadius * 2 }
            ?? notchlessRevealWidth
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

@MainActor
final class TopNotchHistoryLayoutModel: ObservableObject {
    @Published var topContentInset: CGFloat = 0
}

final class TopNotchHistorySurfaceView: NSView {
    private let shapeMask = CAShapeLayer()
    private weak var presentationContentView: NSView?
    private var maskTarget: MaskTarget = .expanded

    private enum MaskTarget {
        case expanded
        case compact(CGRect)
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

    func animateReveal(duration: TimeInterval) {
        animateMask(to: .expanded, duration: duration)
    }

    func animateDismiss(to compactRect: CGRect, duration: TimeInterval) {
        animateMask(to: .compact(compactRect), duration: duration)
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

    private func animateMask(to target: MaskTarget, duration: TimeInterval) {
        layoutSubtreeIfNeeded()
        let fromPath = shapeMask.presentation()?.path
            ?? shapeMask.path
            ?? path(for: maskTarget)
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
        }
    }

    static func surfacePath(in bounds: CGRect) -> CGPath {
        let topRadius = min(
            TopNotchHistoryGeometry.topCornerRadius,
            bounds.width / 4,
            bounds.height
        )
        let bottomRadius = min(
            TopNotchHistoryGeometry.bottomCornerRadius,
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

    func applySelection(id: UUID?, scroll: Bool = true) {
        guard let collectionView else { return }
        guard let id, let index = entryIDs.firstIndex(of: id) else {
            collectionView.deselectAll(nil)
            return
        }
        let indexPath = IndexPath(item: index, section: 0)
        collectionView.deselectAll(nil)
        collectionView.selectItems(
            at: [indexPath],
            scrollPosition: scroll ? .centeredHorizontally : []
        )
        if scroll {
            collectionView.scrollToItems(at: [indexPath], scrollPosition: .centeredHorizontally)
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
    let kind: TopNotchHistoryCardKind
    let title: String
    let detail: String
    let accessibilityLabel: String

    static func make(entry: HistoryEntry) -> Self {
        make(descriptor: HistoryOccurrenceDescriptor(
            id: entry.id,
            activityAt: entry.activityAt,
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
        VStack(alignment: .leading, spacing: 10) {
            searchField
            content
            footer
        }
        .padding(.top, layoutModel.topContentInset + 14)
        .padding(.horizontal, TopNotchHistoryGeometry.contentHorizontalInset)
        .padding(.bottom, 14)
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

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search history", text: Binding(
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
                    selectedEntry: { viewModel.selectedEntry },
                    onDelete: { entry in
                        HistoryKeyboardActionScheduler.deferToNextMainRunLoop {
                            Task { @MainActor in await viewModel.delete(entry) }
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
            ContentUnavailableView("No History Yet", systemImage: "clipboard", description: Text("Copied items will appear here while Qipli is running."))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        case .list:
            let descriptors = viewModel.visibleDescriptors
            if descriptors.isEmpty {
                if viewModel.isSearchInProgress {
                    ProgressView("Searching…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView("No Matching History", systemImage: "magnifyingglass", description: Text("Try a different search term."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            } else {
                let cards = descriptors.map(TopNotchHistoryCardDescriptor.make(descriptor:))
                TopNotchHistoryCollectionView(
                    cards: cards,
                    snapshotRevision: viewModel.visibleSnapshotRevision,
                    selectedEntryID: viewModel.selectedEntryID,
                    interactionBridge: interactionBridge,
                    thumbnailData: { viewModel.thumbnailDataByEntryID[$0] },
                    requestThumbnail: viewModel.requestThumbnail(forEntryID:),
                    selectEntry: viewModel.select,
                    pasteEntry: { id in
                        guard canPaste else { return }
                        pasteEntry(id)
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
            HStack(spacing: 8) {
                if permissionService.state != .granted {
                    Button("Open Accessibility Settings", action: openAccessibilitySettings)
                        .font(.caption)
                }
                Spacer(minLength: 0)
                Text("← → Navigate  ·  Return Paste")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Use Left and Right Arrow to navigate. Press Return to paste.")
            }
        }
    }

    private var canPaste: Bool {
        permissionService.state == .granted && !viewModel.isPasteInProgress
    }
}

struct TopNotchHistoryCollectionView: NSViewRepresentable {
    let cards: [TopNotchHistoryCardDescriptor]
    let snapshotRevision: Int
    let selectedEntryID: UUID?
    let interactionBridge: TopNotchHistoryInteractionBridge
    let thumbnailData: (UUID) -> Data?
    let requestThumbnail: (UUID) -> Void
    let selectEntry: (UUID) -> Void
    let pasteEntry: (UUID) -> Void
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
        private var isApplyingSelection = false

        init(parent: TopNotchHistoryCollectionView) { self.parent = parent }

        func apply(parent: TopNotchHistoryCollectionView, to collectionView: NSCollectionView, force: Bool) {
            self.parent = parent
            let ids = parent.cards.map(\.id)
            if force || lastRevision != parent.snapshotRevision || lastIDs != ids {
                lastRevision = parent.snapshotRevision
                lastIDs = ids
                collectionView.reloadData()
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
                doubleClick: { [weak self] in self?.parent.pasteEntry(card.id) }
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
        doubleClick: @escaping () -> Void
    ) {
        cardView.configure(
            card: card,
            thumbnailData: thumbnailData,
            isSelected: isSelected,
            requestThumbnail: requestThumbnail,
            doubleClick: doubleClick
        )
    }
}

private struct TopNotchHistoryDeleteKeyMonitor: NSViewRepresentable {
    let isSearchFocused: () -> Bool
    let query: () -> String
    let selectedEntry: () -> HistoryEntry?
    let onDelete: (HistoryEntry) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.configure(
            isSearchFocused: isSearchFocused,
            query: query,
            selectedEntry: selectedEntry,
            onDelete: onDelete
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isSearchFocused: isSearchFocused,
            query: query,
            selectedEntry: selectedEntry,
            onDelete: onDelete
        )
    }

    final class Coordinator {
        private var isSearchFocused: () -> Bool
        private var query: () -> String
        private var selectedEntry: () -> HistoryEntry?
        private var onDelete: (HistoryEntry) -> Void
        private weak var hostView: NSView?
        private var monitor: Any?

        init(
            isSearchFocused: @escaping () -> Bool,
            query: @escaping () -> String,
            selectedEntry: @escaping () -> HistoryEntry?,
            onDelete: @escaping (HistoryEntry) -> Void
        ) {
            self.isSearchFocused = isSearchFocused
            self.query = query
            self.selectedEntry = selectedEntry
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
            selectedEntry: @escaping () -> HistoryEntry?,
            onDelete: @escaping (HistoryEntry) -> Void
        ) {
            self.isSearchFocused = isSearchFocused
            self.query = query
            self.selectedEntry = selectedEntry
            self.onDelete = onDelete
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }

        private func process(_ event: NSEvent) -> NSEvent? {
            guard let hostView,
                  hostView.window === event.window,
                  isSearchFocused(),
                  query().isEmpty,
                  !event.isARepeat,
                  event.keyCode == 51 || event.keyCode == 117,
                  event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
                  let entry = selectedEntry()
            else { return event }
            onDelete(entry)
            return nil
        }
    }
}

private final class TopNotchHistoryCardView: NSView {
    private let iconView = NSImageView()
    private let kindLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private let thumbnailView = NSImageView()
    private var requestThumbnail: (() -> Void)?
    private var doubleClick: (() -> Void)?

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
        doubleClick: @escaping () -> Void
    ) {
        kindLabel.stringValue = card.title
        detailLabel.stringValue = card.detail
        iconView.image = NSImage(systemSymbolName: card.kind.symbolName, accessibilityDescription: card.title)
        thumbnailView.image = thumbnailData.flatMap(NSImage.init(data:))
        thumbnailView.isHidden = card.kind != .image || thumbnailView.image == nil
        self.requestThumbnail = requestThumbnail
        self.doubleClick = doubleClick
        if card.kind == .image, thumbnailData == nil { requestThumbnail() }
        setAccessibilityLabel(card.accessibilityLabel)
        updateSelection(isSelected)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        if event.clickCount == 2 { doubleClick?() }
    }

    private func configureView() {
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = 14
        layer?.borderWidth = 1

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = .secondaryLabelColor
        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.cornerRadius = 8
        thumbnailView.layer?.masksToBounds = true

        kindLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        kindLabel.textColor = .secondaryLabelColor
        detailLabel.font = .systemFont(ofSize: 15, weight: .medium)
        detailLabel.maximumNumberOfLines = 5
        detailLabel.lineBreakMode = .byTruncatingTail

        let stack = NSStackView(views: [iconView, kindLabel, thumbnailView, detailLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -14),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            thumbnailView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            thumbnailView.heightAnchor.constraint(equalToConstant: 62)
        ])
        thumbnailView.isHidden = true
        setAccessibilityRole(.group)
    }

    fileprivate func updateSelection(_ isSelected: Bool) {
        let baseColor = NSColor(calibratedWhite: 0.08, alpha: 1)
        layer?.backgroundColor = (isSelected ? NSColor.controlAccentColor : baseColor)
            .withAlphaComponent(isSelected ? 0.30 : 1)
            .cgColor
        layer?.borderColor = (isSelected ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
    }
}
