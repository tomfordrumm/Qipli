import AppKit
import SwiftUI

@MainActor
protocol HistoryTableSelectionApplying: AnyObject {
    func applySelection(id: UUID?, resetViewport: Bool)
    func applySnapshot(
        entries: [HistoryEntry],
        revision: Int,
        selectedEntryID: UUID?,
        resetViewport: Bool
    )
}

/// Gives the AppKit key monitor a synchronous path to the visible table. SwiftUI
/// still owns the surrounding panel state, but arrow-key feedback does not wait
/// for an ObservableObject render pass.
@MainActor
final class HistoryTableInteractionBridge {
    private weak var target: (any HistoryTableSelectionApplying)?

    func attach(_ target: any HistoryTableSelectionApplying) {
        self.target = target
    }

    func detach(_ target: any HistoryTableSelectionApplying) {
        guard self.target === target else { return }
        self.target = nil
    }

    func applySelection(id: UUID?, resetViewport: Bool = false) {
        target?.applySelection(id: id, resetViewport: resetViewport)
    }

    func applySnapshot(
        entries: [HistoryEntry],
        revision: Int,
        selectedEntryID: UUID?,
        resetViewport: Bool
    ) {
        target?.applySnapshot(
            entries: entries,
            revision: revision,
            selectedEntryID: selectedEntryID,
            resetViewport: resetViewport
        )
    }
}

struct HistoryTableView: NSViewRepresentable {
    let entries: [HistoryEntry]
    let snapshotRevision: Int
    let selectedEntryID: UUID?
    let viewportResetRequestID: Int
    let interactionBridge: HistoryTableInteractionBridge
    let loadMore: () -> Void
    let thumbnailData: (HistoryEntry) -> Data?
    let requestThumbnail: (HistoryEntry) -> Void
    let selectEntry: (UUID) -> Void
    let pasteEntry: (HistoryEntry) -> Void
    let deleteEntry: (HistoryEntry) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let tableView = NSTableView()
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.allowsEmptySelection = false
        tableView.allowsMultipleSelection = false
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.intercellSpacing = .zero
        tableView.rowHeight = HistoryTableRowLayout.minimumRowHeight
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.pasteClickedRow(_:))
        tableView.setAccessibilityLabel("Clipboard history")

        let column = NSTableColumn(identifier: Coordinator.columnIdentifier)
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        scrollView.documentView = tableView
        scrollView.contentView.postsBoundsChangedNotifications = true

        context.coordinator.install(tableView: tableView, scrollView: scrollView)
        interactionBridge.attach(context.coordinator)
        context.coordinator.update(from: self)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(from: self)
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.interactionBridge.detach(coordinator)
        coordinator.invalidate()
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, HistoryTableSelectionApplying {
        fileprivate var interactionBridge: HistoryTableInteractionBridge
        private var entries: [HistoryEntry] = []
        private var rowByID: [UUID: Int] = [:]
        private var snapshotRevision: Int?
        private var selectedEntryID: UUID?
        private var handledViewportResetRequestID: Int?
        private var selectEntry: (UUID) -> Void
        private var pasteEntry: (HistoryEntry) -> Void
        private var deleteEntry: (HistoryEntry) -> Void
        private var loadMore: () -> Void = {}
        private var thumbnailData: (HistoryEntry) -> Data? = { _ in nil }
        private var requestThumbnail: (HistoryEntry) -> Void = { _ in }
        private weak var tableView: NSTableView?
        private weak var scrollView: NSScrollView?
        private var scrollObserver: NSObjectProtocol?
        private var isApplyingProgrammaticSelection = false
        private var rowHeightCache = HistoryTableRowHeightCache(capacity: 4_096)

        init(parent: HistoryTableView) {
            interactionBridge = parent.interactionBridge
            selectEntry = parent.selectEntry
            pasteEntry = parent.pasteEntry
            deleteEntry = parent.deleteEntry
            loadMore = parent.loadMore
            thumbnailData = parent.thumbnailData
            requestThumbnail = parent.requestThumbnail
        }

        func install(tableView: NSTableView, scrollView: NSScrollView) {
            self.tableView = tableView
            self.scrollView = scrollView
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.requestMoreIfNeeded()
                }
            }
        }

        func update(from parent: HistoryTableView) {
            if interactionBridge !== parent.interactionBridge {
                interactionBridge.detach(self)
                interactionBridge = parent.interactionBridge
                interactionBridge.attach(self)
            }
            selectEntry = parent.selectEntry
            pasteEntry = parent.pasteEntry
            deleteEntry = parent.deleteEntry
            loadMore = parent.loadMore
            thumbnailData = parent.thumbnailData
            requestThumbnail = parent.requestThumbnail

            let mustResetViewport = handledViewportResetRequestID != parent.viewportResetRequestID
            handledViewportResetRequestID = parent.viewportResetRequestID
            applySnapshot(
                entries: parent.entries,
                revision: parent.snapshotRevision,
                selectedEntryID: parent.selectedEntryID,
                resetViewport: mustResetViewport
            )
        }

        func applySnapshot(
            entries: [HistoryEntry],
            revision: Int,
            selectedEntryID: UUID?,
            resetViewport: Bool
        ) {
            if snapshotRevision != revision {
                snapshotRevision = revision
                self.entries = entries
                rowByID = Dictionary(uniqueKeysWithValues: entries.enumerated().map { ($0.element.id, $0.offset) })
                isApplyingProgrammaticSelection = true
                tableView?.reloadData()
                isApplyingProgrammaticSelection = false
            }
            applySelection(id: selectedEntryID, resetViewport: resetViewport)
        }

        func applySelection(id: UUID?, resetViewport: Bool) {
            guard let tableView else { return }
            let previousID = selectedEntryID
            selectedEntryID = id

            guard let id, let row = rowByID[id] else {
                if tableView.selectedRow != -1 {
                    isApplyingProgrammaticSelection = true
                    tableView.deselectAll(nil)
                    isApplyingProgrammaticSelection = false
                }
                refreshVisibleRows()
                return
            }

            if tableView.selectedRow != row {
                isApplyingProgrammaticSelection = true
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                isApplyingProgrammaticSelection = false
            }

            if resetViewport {
                resetViewportToTop()
            } else if previousID != id {
                tableView.scrollRowToVisible(row)
            }

            refreshVisibleRows()
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            entries.count
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard entries.indices.contains(row) else {
                return HistoryTableRowLayout.minimumRowHeight
            }

            let entry = entries[row]
            let columnWidth = tableView.tableColumns.first?.width ?? tableView.bounds.width
            let textWidth = max(1, columnWidth - HistoryTableRowLayout.horizontalChromeWidth)
            if let cachedHeight = rowHeightCache.height(
                for: entry.id,
                textWidth: textWidth
            ) {
                return cachedHeight
            }

            let height = HistoryTableRowLayout.height(
                for: HistoryPreview.text(for: entry.displayText),
                textWidth: textWidth
            )
            rowHeightCache.insert(height: height, for: entry.id, textWidth: textWidth)
            return height
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            HistoryTableRowView()
        }

        func tableView(
            _ tableView: NSTableView,
            viewFor tableColumn: NSTableColumn?,
            row: Int
        ) -> NSView? {
            guard entries.indices.contains(row) else { return nil }
            let cell = tableView.makeView(
                withIdentifier: Self.cellIdentifier,
                owner: self
            ) as? HistoryTableCellView ?? makeCell()
            let entry = entries[row]
            requestThumbnail(entry)
            cell.configure(
                preview: HistoryPreview.text(for: entry.displayText),
                thumbnailData: thumbnailData(entry),
                showsImage: entry.isImageEntry,
                isSelected: entry.id == selectedEntryID,
                deleteTarget: self,
                deleteAction: #selector(deleteEntryFromButton(_:))
            )
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isApplyingProgrammaticSelection,
                  let tableView,
                  entries.indices.contains(tableView.selectedRow)
            else { return }

            let row = tableView.selectedRow
            let entry = entries[row]
            selectedEntryID = entry.id
            selectEntry(entry.id)
            refreshVisibleRows()
        }

        @objc func pasteClickedRow(_ sender: Any?) {
            guard let tableView,
                  entries.indices.contains(tableView.clickedRow)
            else { return }
            let entry = entries[tableView.clickedRow]
            if selectedEntryID != entry.id {
                selectedEntryID = entry.id
                selectEntry(entry.id)
            }
            pasteEntry(entry)
        }

        @objc private func deleteEntryFromButton(_ sender: NSButton) {
            guard let tableView else { return }
            let row = tableView.row(for: sender)
            guard entries.indices.contains(row) else { return }
            deleteEntry(entries[row])
        }

        func invalidate() {
            if let scrollObserver {
                NotificationCenter.default.removeObserver(scrollObserver)
                self.scrollObserver = nil
            }
            tableView?.delegate = nil
            tableView?.dataSource = nil
            tableView?.target = nil
        }

        private func makeCell() -> HistoryTableCellView {
            let cell = HistoryTableCellView()
            cell.identifier = Self.cellIdentifier
            return cell
        }

        private func resetViewportToTop() {
            guard let tableView, let scrollView else { return }
            tableView.layoutSubtreeIfNeeded()
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func refreshVisibleRows() {
            guard let tableView else { return }
            let visibleRows = tableView.rows(in: tableView.visibleRect)
            guard visibleRows.location != NSNotFound else { return }
            let upperBound = min(entries.count, visibleRows.location + visibleRows.length)
            guard visibleRows.location < upperBound else { return }
            for row in visibleRows.location..<upperBound {
                let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? HistoryTableCellView
                cell?.setSelected(entries[row].id == selectedEntryID)
            }
        }

        private func requestMoreIfNeeded() {
            guard let scrollView else { return }
            let visibleBottom = scrollView.contentView.bounds.maxY
            let documentHeight = scrollView.documentView?.bounds.height ?? 0
            guard documentHeight > 0, visibleBottom >= documentHeight - 120 else { return }
            loadMore()
        }

        fileprivate static let columnIdentifier = NSUserInterfaceItemIdentifier("HistoryEntryColumn")
        private static let cellIdentifier = NSUserInterfaceItemIdentifier("HistoryEntryCell")
    }
}

struct HistoryTableRowHeightCache {
    private struct Entry {
        let textWidth: CGFloat
        let height: CGFloat
    }

    let capacity: Int
    private var entries: [UUID: Entry] = [:]
    private var evictionOrder: [UUID] = []
    private var nextEvictionIndex = 0

    init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        entries.reserveCapacity(capacity)
        evictionOrder.reserveCapacity(capacity)
    }

    var count: Int {
        entries.count
    }

    func height(for id: UUID, textWidth: CGFloat) -> CGFloat? {
        guard let entry = entries[id], abs(entry.textWidth - textWidth) < 0.5 else {
            return nil
        }
        return entry.height
    }

    mutating func insert(height: CGFloat, for id: UUID, textWidth: CGFloat) {
        if entries[id] != nil {
            entries[id] = Entry(textWidth: textWidth, height: height)
            return
        }

        if entries.count < capacity {
            entries[id] = Entry(textWidth: textWidth, height: height)
            evictionOrder.append(id)
            return
        }

        let evictedID = evictionOrder[nextEvictionIndex]
        entries.removeValue(forKey: evictedID)
        entries[id] = Entry(textWidth: textWidth, height: height)
        evictionOrder[nextEvictionIndex] = id
        nextEvictionIndex = (nextEvictionIndex + 1) % capacity
    }
}

@MainActor
enum HistoryTableRowLayout {
    static let minimumRowHeight: CGFloat = 38
    static let horizontalChromeWidth: CGFloat = 88

    private static let maximumLines = 3
    private static let verticalPadding: CGFloat = 8
    fileprivate static let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    private static let minimumTextHeight = measuredTextHeight(for: "Ag", textWidth: 1_000)
    private static let maximumTextHeight = measuredTextHeight(
        for: Array(repeating: "Ag", count: maximumLines).joined(separator: "\n"),
        textWidth: 1_000
    )

    static func height(for text: String, textWidth: CGFloat) -> CGFloat {
        let measuredHeight = measuredTextHeight(for: text, textWidth: textWidth)
        let textHeight = min(
            max(minimumTextHeight, measuredHeight),
            maximumTextHeight
        )
        return max(minimumRowHeight, ceil(textHeight + verticalPadding * 2))
    }

    private static func measuredTextHeight(for text: String, textWidth: CGFloat) -> CGFloat {
        ceil(
            (text as NSString).boundingRect(
                with: NSSize(width: max(1, textWidth), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font]
            ).height
        )
    }
}

private final class HistoryTableCellView: NSTableCellView {
    private let thumbnailView = NSImageView()
    private let previewField = NSTextField(labelWithString: "")
    private let deleteButton: NSButton
    private var isSelectedEntry = false
    private var isHovering = false
    private var trackingAreaReference: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        let image = NSImage(
            systemSymbolName: "trash",
            accessibilityDescription: "Delete"
        ) ?? NSImage()
        deleteButton = NSButton(image: image, target: nil, action: nil)
        super.init(frame: frameRect)

        previewField.translatesAutoresizingMaskIntoConstraints = false
        previewField.font = HistoryTableRowLayout.font
        previewField.lineBreakMode = .byTruncatingTail
        previewField.maximumNumberOfLines = 3
        previewField.cell?.wraps = true
        previewField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        previewField.setAccessibilityRole(.staticText)

        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.contentTintColor = .secondaryLabelColor
        thumbnailView.setAccessibilityRole(.image)

        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.isBordered = false
        deleteButton.bezelStyle = .accessoryBarAction
        deleteButton.contentTintColor = .secondaryLabelColor
        deleteButton.toolTip = "Delete"
        deleteButton.setAccessibilityLabel("Delete")
        deleteButton.setAccessibilityHelp("Removes this history entry.")

        addSubview(thumbnailView)
        addSubview(previewField)
        addSubview(deleteButton)
        NSLayoutConstraint.activate([
            thumbnailView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            thumbnailView.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: 28),
            thumbnailView.heightAnchor.constraint(equalToConstant: 28),
            previewField.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 8),
            previewField.centerYAnchor.constraint(equalTo: centerYAnchor),
            previewField.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -10),
            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            deleteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 24),
            deleteButton.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaReference = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateDeletePresentation()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateDeletePresentation()
    }

    func configure(
        preview: String,
        thumbnailData: Data?,
        showsImage: Bool,
        isSelected: Bool,
        deleteTarget: AnyObject,
        deleteAction: Selector
    ) {
        previewField.stringValue = preview
        previewField.setAccessibilityLabel(preview)
        if showsImage {
            thumbnailView.image = thumbnailData.flatMap(NSImage.init(data:))
                ?? NSImage(systemSymbolName: "photo", accessibilityDescription: "Image")
            thumbnailView.setAccessibilityLabel("Image preview")
        } else {
            thumbnailView.image = nil
            thumbnailView.setAccessibilityLabel(nil)
        }
        deleteButton.target = deleteTarget
        deleteButton.action = deleteAction
        setSelected(isSelected)
    }

    func setSelected(_ isSelected: Bool) {
        isSelectedEntry = isSelected
        updateDeletePresentation()
    }

    private func updateDeletePresentation() {
        let showsDelete = isSelectedEntry || isHovering
        deleteButton.alphaValue = showsDelete ? 1 : 0
        deleteButton.isEnabled = showsDelete
    }
}

private final class HistoryTableRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        let selectionRect = bounds.insetBy(dx: 2, dy: 3)
        let path = NSBezierPath(roundedRect: selectionRect, xRadius: 8, yRadius: 8)
        NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
        path.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.45).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

}
