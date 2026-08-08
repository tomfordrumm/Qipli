import SwiftUI

struct HistoryPanelView: View {
    @ObservedObject var viewModel: HistoryViewModel
    @ObservedObject var permissionService: AccessibilityPermissionService
    let openAccessibilitySettings: () -> Void
    let pasteSelection: () -> Void
    let close: () -> Void
    @State private var confirmsClearAll = false
    @FocusState private var searchIsFocused: Bool
    @State private var handledPresentationViewportResetRequestID: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("History")
                    .font(.headline)
                Spacer()
                if case .list = viewModel.state {
                    Button("Clear All", role: .destructive) {
                        confirmsClearAll = true
                    }
                }
            }

            TextField("Search history", text: Binding(
                get: { viewModel.query },
                set: { viewModel.updateQuery($0) }
            ))
            .textFieldStyle(.roundedBorder)
            .focused($searchIsFocused)
            .accessibilityIdentifier("history-search")
            .onKeyPress(.upArrow) {
                schedule(.moveSelection(by: -1))
                return .handled
            }
            .onKeyPress(.downArrow) {
                schedule(.moveSelection(by: 1))
                return .handled
            }
            .onKeyPress(.return) {
                schedule(.pasteSelected)
                return .handled
            }
            .onKeyPress(.escape) {
                schedule(.close)
                return .handled
            }

            content

            footer
        }
        .padding(20)
        .frame(width: 460, height: 340, alignment: .topLeading)
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
        .alert("Clear all Qipli history?", isPresented: $confirmsClearAll) {
            Button("Clear All", role: .destructive) {
                viewModel.clearAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes Qipli’s local history. It does not change your current system clipboard.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView("Loading history…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            ContentUnavailableView("No History Yet", systemImage: "clipboard", description: Text("Copied text will appear here while Qipli is running."))
        case let .list(entries):
            if entries.isEmpty {
                ContentUnavailableView(
                    "No Matching History",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different search term.")
                )
            } else {
                ScrollViewReader { proxy in
                    List(entries) { entry in
                        HStack(alignment: .top, spacing: 12) {
                            Button {
                                schedule(.select(entry.id))
                            } label: {
                                Text(entry.text)
                                    .lineLimit(3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .highPriorityGesture(
                                TapGesture(count: 2).onEnded {
                                    schedule(.selectAndPaste(entry.id))
                                }
                            )

                            Button("Delete", role: .destructive) {
                                schedule(.delete(entry))
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 3)
                        .id(entry.id)
                        .listRowBackground(viewModel.selectedEntryID == entry.id ? Color.accentColor.opacity(0.18) : Color.clear)
                    }
                    .listStyle(.inset)
                    .onAppear {
                        scrollSelectionIntoView(using: proxy)
                        resetViewportForFreshPresentation(using: proxy)
                    }
                    .onChange(of: viewModel.selectedEntryID) { _, _ in
                        scrollSelectionIntoView(using: proxy)
                    }
                    .onChange(of: viewModel.presentationViewportResetRequestID) { _, _ in
                        resetViewportForFreshPresentation(using: proxy)
                    }
                }
            }
        case .error:
            VStack(alignment: .leading, spacing: 12) {
                Text("History is unavailable.")
                    .font(.headline)
                Text("Qipli could not read or update local history. Your system clipboard was not changed.")
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    viewModel.reload()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let failure = viewModel.pasteFailure {
                Text(failure.message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if permissionService.state != .granted {
                    Text("Accessibility access is needed to paste.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Settings", action: openAccessibilitySettings)
                } else {
                    Spacer()
                    Button("Paste", action: pasteSelection)
                        .disabled(viewModel.selectedEntry == nil)
                }
            }
        }
    }

    private var canPaste: Bool {
        permissionService.state == .granted
    }

    private func schedule(_ intent: HistoryPanelIntent) {
        HistoryKeyboardActionScheduler.deferToNextMainRunLoop {
            HistoryPanelIntentExecutor(
                moveSelection: viewModel.moveSelection,
                select: viewModel.select,
                hasSelectedEntry: { viewModel.selectedEntry != nil },
                canPaste: { canPaste },
                pasteSelection: pasteSelection,
                close: close,
                delete: viewModel.delete
            )
            .execute(intent)
        }
    }

    private func scrollSelectionIntoView(using proxy: ScrollViewProxy) {
        guard let selectedEntryID = viewModel.selectedEntryID else { return }
        HistoryKeyboardActionScheduler.deferToNextMainRunLoop {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                proxy.scrollTo(selectedEntryID)
            }
        }
    }

    private func resetViewportForFreshPresentation(using proxy: ScrollViewProxy) {
        let requestID = viewModel.presentationViewportResetRequestID
        guard handledPresentationViewportResetRequestID != requestID,
              let firstEntryID = viewModel.visibleEntries.first?.id
        else { return }

        handledPresentationViewportResetRequestID = requestID
        HistoryKeyboardActionScheduler.deferToNextMainRunLoop {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                proxy.scrollTo(firstEntryID, anchor: .top)
            }
        }
    }
}

/// Intent is separated from SwiftUI event callbacks so keyboard and row actions
/// can be verified without depending on an XCUI event loop.
enum HistoryPanelIntent: Equatable {
    case moveSelection(by: Int)
    case pasteSelected
    case close
    case select(UUID)
    case selectAndPaste(UUID)
    case delete(HistoryEntry)
}

/// Executes a deferred History UI intent without depending on SwiftUI. Keeping
/// this small seam makes selection, paste and destructive actions testable.
@MainActor
struct HistoryPanelIntentExecutor {
    let moveSelection: (Int) -> Void
    let select: (UUID) -> Void
    let hasSelectedEntry: () -> Bool
    let canPaste: () -> Bool
    let pasteSelection: () -> Void
    let close: () -> Void
    let delete: (HistoryEntry) -> Void

    func execute(_ intent: HistoryPanelIntent) {
        switch intent {
        case let .moveSelection(offset):
            moveSelection(offset)
        case .pasteSelected:
            pasteIfAvailable()
        case .close:
            close()
        case let .select(id):
            select(id)
        case let .selectAndPaste(id):
            select(id)
            pasteIfAvailable()
        case let .delete(entry):
            delete(entry)
        }
    }

    private func pasteIfAvailable() {
        guard canPaste(), hasSelectedEntry() else { return }
        pasteSelection()
    }
}

/// Keeps keyboard-driven state and window changes outside SwiftUI's current view-update transaction.
private enum HistoryKeyboardActionScheduler {
    static func deferToNextMainRunLoop(_ action: @escaping () -> Void) {
        RunLoop.main.perform(inModes: [.common]) {
            action()
        }
    }
}

struct PasteStackPanelView: View {
    @ObservedObject var sessionController: StackSessionController
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Paste Stack")
                    .font(.headline)
                Spacer()
                Text(stackStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if sessionController.occurrences.isEmpty {
                ContentUnavailableView(
                    "Copy text to add it",
                    systemImage: "doc.on.clipboard",
                    description: Text("This stack starts empty and collects new copies only.")
                )
            } else {
                traversalControls

                HStack {
                    Text(nextExplanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(reorderHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                List {
                    ForEach(sessionController.occurrences) { occurrence in
                        occurrenceRow(occurrence)
                    }
                    .onMove { source, destination in
                        execute(.moveOccurrences(source, to: destination))
                    }
                    .moveDisabled(!canReorder)
                }
                .listStyle(.inset)
            }

            if let pasteFailure = sessionController.pasteFailure {
                Text(pasteFailure.message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if sessionController.hasCopyCommandDispatchFailure {
                Text("Qipli could not send Copy to the active app. Try the Paste Stack shortcut again.")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if sessionController.hasCaptureError {
                Text("Qipli could not save the last copied text. Copy it again to retry.")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel Stack", action: cancel)
            }
        }
        .padding(16)
        .frame(width: 400, height: 360, alignment: .topLeading)
        .accessibilityIdentifier("paste-stack-panel")
    }

    private var traversalControls: some View {
        Picker("Traversal direction", selection: Binding(
            get: { sessionController.traversalDirection },
            set: { execute(.setTraversalDirection($0)) }
        )) {
            ForEach(StackTraversalDirection.allCases, id: \.self) { direction in
                Text(direction.displayName).tag(direction)
            }
        }
        .pickerStyle(.segmented)
        .disabled(!canChooseDirection)
        .accessibilityLabel(PasteStackPanelAccessibility.directionLabel)
        .accessibilityValue(sessionController.traversalDirection.displayName)
    }

    private func occurrenceRow(_ occurrence: StackOccurrence) -> some View {
        let index = occurrence.position
        let isNext = sessionController.nextOccurrence?.id == occurrence.id
        let isUsed = occurrence.state == .used

        return HStack(alignment: .top, spacing: 8) {
            Text("\(index + 1).")
                .foregroundStyle(.secondary)
            Text(StackPreview.text(for: occurrence.text))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            if occurrence.state == .processing {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Preparing paste")
            } else if isUsed {
                Label("Used", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Used item")
            }
            if isNext {
                Label("Next", systemImage: "arrow.right.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .accessibilityLabel(PasteStackPanelAccessibility.nextItemLabel)
            }
            VStack(spacing: 2) {
                Button {
                    execute(.moveOccurrence(occurrence.id, by: -1))
                } label: {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.borderless)
                .disabled(isUsed || !controlState.canMove(position: index, by: -1))
                .accessibilityLabel(PasteStackPanelAccessibility.moveLabel(position: index, direction: .up))
                .accessibilityHint("Alternative to dragging this stack item.")

                Button {
                    execute(.moveOccurrence(occurrence.id, by: 1))
                } label: {
                    Image(systemName: "arrow.down")
                }
                .buttonStyle(.borderless)
                .disabled(isUsed || !controlState.canMove(position: index, by: 1))
                .accessibilityLabel(PasteStackPanelAccessibility.moveLabel(position: index, direction: .down))
                .accessibilityHint("Alternative to dragging this stack item.")
            }
        }
        .padding(.vertical, 2)
        .opacity(isUsed ? 0.55 : 1)
        // Keep the native separator tied to the row bounds, not the conditional
        // Next label or trailing move controls.
        .frame(maxWidth: .infinity, alignment: .leading)
        .alignmentGuide(.listRowSeparatorLeading) { dimensions in
            dimensions[.leading]
        }
        .alignmentGuide(.listRowSeparatorTrailing) { dimensions in
            dimensions[.trailing]
        }
        .accessibilityElement(children: .contain)
    }

    private var canChooseDirection: Bool {
        controlState.canChooseDirection
    }

    private var canReorder: Bool {
        controlState.canReorder
    }

    private var controlState: PasteStackPanelControlState {
        PasteStackPanelControlState(
            occurrenceCount: sessionController.occurrences.count,
            canAdjustTraversal: sessionController.canAdjustTraversal
        )
    }

    private var nextExplanation: String {
        if sessionController.occurrences.contains(where: { $0.state == .processing }) {
            return "Preparing the selected stack item."
        }
        guard sessionController.nextOccurrence != nil else {
            return "All stack items were sent."
        }
        return switch sessionController.traversalDirection {
        case .direct: "Direct: the top item is next."
        case .reverse: "Reverse: the bottom item is next."
        }
    }

    private var reorderHint: String {
        if sessionController.traversalHasStarted {
            "Order is locked after traversal starts."
        } else if sessionController.occurrences.count < 2 {
            "Add another item to reorder."
        } else {
            "Drag rows or use arrows."
        }
    }

    private var stackStatus: String {
        if sessionController.occurrences.contains(where: { $0.state == .processing }) {
            return "Processing"
        }
        return sessionController.traversalHasStarted ? "Traversal started" : "Collecting"
    }

    private func execute(_ intent: PasteStackPanelIntent) {
        PasteStackPanelIntentExecutor(
            occurrences: { sessionController.occurrences },
            canAdjustTraversal: { sessionController.canAdjustTraversal },
            setTraversalDirection: sessionController.setTraversalDirection,
            reorder: sessionController.reorder,
            schedule: PasteStackPanelIntentScheduler.schedule
        )
        .execute(intent)
    }
}

/// UI requests are deliberately occurrence-ID based. This allows the native
/// drag behavior and accessible move buttons to share the same model boundary.
enum PasteStackPanelIntent: Equatable {
    case setTraversalDirection(StackTraversalDirection)
    case moveOccurrence(UUID, by: Int)
    case moveOccurrences(IndexSet, to: Int)
}

@MainActor
struct PasteStackPanelIntentExecutor {
    let occurrences: () -> [StackOccurrence]
    let canAdjustTraversal: () -> Bool
    let setTraversalDirection: (StackTraversalDirection) -> Bool
    let reorder: ([UUID]) -> Bool
    let schedule: (@escaping () -> Void) -> Void

    func execute(_ intent: PasteStackPanelIntent) {
        guard canAdjustTraversal() else { return }

        switch intent {
        case let .setTraversalDirection(direction):
            schedule { _ = setTraversalDirection(direction) }
        case let .moveOccurrence(id, offset):
            guard let ids = PasteStackOrdering.moving(id: id, by: offset, in: occurrences()) else { return }
            schedule { _ = reorder(ids) }
        case let .moveOccurrences(source, destination):
            guard let ids = PasteStackOrdering.moving(source: source, to: destination, in: occurrences()) else { return }
            schedule { _ = reorder(ids) }
        }
    }
}

/// Defers SwiftUI callbacks until the surrounding List or Picker update has
/// finished. Reorder IDs are captured before this boundary, then validated by
/// the state machine at execution time against its current session snapshot.
enum PasteStackPanelIntentScheduler {
    static func schedule(_ action: @escaping () -> Void) {
        RunLoop.main.perform(inModes: [.common]) {
            action()
        }
    }
}

enum PasteStackOrdering {
    static func moving(id: UUID, by offset: Int, in occurrences: [StackOccurrence]) -> [UUID]? {
        let ids = occurrences.map(\.id)
        guard let source = ids.firstIndex(of: id), offset != 0 else { return nil }
        let destination = source + offset
        guard ids.indices.contains(destination) else { return nil }

        var reordered = ids
        let movedID = reordered.remove(at: source)
        reordered.insert(movedID, at: destination)
        return reordered
    }

    static func moving(source: IndexSet, to destination: Int, in occurrences: [StackOccurrence]) -> [UUID]? {
        let ids = occurrences.map(\.id)
        guard !source.isEmpty,
              source.allSatisfy(ids.indices.contains),
              (0 ... ids.count).contains(destination)
        else { return nil }

        let moved = source.map { ids[$0] }
        var remaining = ids.enumerated().compactMap { source.contains($0.offset) ? nil : $0.element }
        let removedBeforeDestination = source.filter { $0 < destination }.count
        let insertionIndex = destination - removedBeforeDestination
        remaining.insert(contentsOf: moved, at: insertionIndex)
        return remaining
    }
}

struct PasteStackPanelControlState: Equatable {
    let occurrenceCount: Int
    let canAdjustTraversal: Bool

    var canChooseDirection: Bool { canAdjustTraversal && occurrenceCount > 0 }
    var canReorder: Bool { canAdjustTraversal && occurrenceCount > 1 }

    func canMove(position: Int, by offset: Int) -> Bool {
        canReorder && (0 ..< occurrenceCount).contains(position + offset)
    }
}

enum PasteStackPanelAccessibility {
    enum MoveDirection {
        case up
        case down
    }

    static let directionLabel = "Traversal direction"
    static let nextItemLabel = "Next item"

    static func moveLabel(position: Int, direction: MoveDirection) -> String {
        let verb = switch direction {
        case .up: "up"
        case .down: "down"
        }
        return "Move item \(position + 1) \(verb)"
    }
}

struct PermissionStatusView: View {
    @ObservedObject var permissionService: AccessibilityPermissionService
    let requestAccess: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Accessibility Permission")
                .font(.headline)
            Text(permissionService.state.explanation)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Allow Accessibility Access", action: requestAccess)
                Button("Open System Settings", action: openSettings)
            }
            Text(permissionService.state.menuDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 420, alignment: .leading)
    }
}
