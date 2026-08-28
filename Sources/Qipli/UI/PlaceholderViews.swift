import AppKit
import SwiftUI

struct HistoryPanelView: View {
    @ObservedObject var viewModel: HistoryViewModel
    @ObservedObject var permissionService: AccessibilityPermissionService
    let openAccessibilitySettings: () -> Void
    let pasteEntry: (HistoryEntry) -> Void
    let close: () -> Void
    @State private var hoveredEntryID: UUID?
    @FocusState private var searchIsFocused: Bool
    @State private var handledPresentationViewportResetRequestID: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            searchField

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
            .frame(maxWidth: .infinity)
            .focused($searchIsFocused)
            .accessibilityIdentifier("history-search")
            .accessibilityHint("Type to filter history. Use Up and Down Arrow to choose an entry.")
            .background {
                HistorySearchDeleteKeyMonitor(
                    isSearchFocused: { searchIsFocused },
                    query: { viewModel.query },
                    state: { viewModel.state },
                    selectedEntry: { viewModel.selectedEntry },
                    onDelete: { entry in schedule(.delete(entry)) }
                )
                .frame(width: 0, height: 0)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
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
                        let isSelected = viewModel.selectedEntryID == entry.id
                        let showsDelete = isSelected || hoveredEntryID == entry.id
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
                            .accessibilityValue(isSelected ? "Selected" : "Not selected")
                            .highPriorityGesture(
                                TapGesture(count: 2).onEnded {
                                    schedule(.selectAndPaste(entry))
                                }
                            )

                            Button(role: .destructive) {
                                schedule(.delete(entry))
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Delete")
                            .accessibilityHint("Removes this history entry.")
                            .help("Delete")
                            .opacity(showsDelete ? 1 : 0)
                            .allowsHitTesting(showsDelete)
                            .accessibilityHidden(false)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.16))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(Color.accentColor.opacity(0.45), lineWidth: 1)
                                    }
                            }
                        }
                        .id(entry.id)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                        .alignmentGuide(.listRowSeparatorTrailing) { $0[.trailing] }
                        .contentShape(Rectangle())
                        .onHover { isHovering in
                            if isHovering {
                                hoveredEntryID = entry.id
                            } else if hoveredEntryID == entry.id {
                                hoveredEntryID = nil
                            }
                        }
                    }
                    .listStyle(.plain)
                    .contentMargins(.horizontal, 0, for: .scrollContent)
                    .scrollContentBackground(.hidden)
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
            if viewModel.isPasteInProgress {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Pasting…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Pasting selected history entry")
            }

            if let failure = viewModel.pasteFailure {
                Text(failure.message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if permissionService.state != .granted {
                HStack {
                    Text("Accessibility access is needed to paste.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Settings", action: openAccessibilitySettings)
                }
            }

            HStack {
                Spacer(minLength: 0)
                keyboardGuide
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var keyboardGuide: some View {
        HStack(spacing: 12) {
            keyboardGuideItem(HistoryKeyboardGuidePresentation.navigation)
            keyboardGuideItem(HistoryKeyboardGuidePresentation.paste)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HistoryKeyboardGuidePresentation.accessibilityLabel)
    }

    private func keyboardGuideItem(_ item: HistoryKeyboardGuideItem) -> some View {
        HStack(spacing: 5) {
            HStack(spacing: 2) {
                ForEach(item.symbolSystemNames, id: \.self) { symbolSystemName in
                    Image(systemName: symbolSystemName)
                        .font(.system(size: 8, weight: .semibold))
                        .frame(width: 16, height: 14)
                        .background {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                                }
                        }
                        .accessibilityHidden(true)
                }
            }

            Text(item.title)
        }
    }

    private var canPaste: Bool {
        permissionService.state == .granted && !viewModel.isPasteInProgress
    }

    private func schedule(_ intent: HistoryPanelIntent) {
        HistoryKeyboardActionScheduler.deferToNextMainRunLoop {
            HistoryPanelIntentExecutor(
                moveSelection: viewModel.moveSelection,
                select: viewModel.select,
                canPaste: { canPaste },
                pasteEntry: pasteEntry,
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

struct HistoryKeyboardGuideItem: Equatable {
    let symbolSystemNames: [String]
    let title: String
}

enum HistoryKeyboardGuidePresentation {
    static let navigation = HistoryKeyboardGuideItem(
        symbolSystemNames: ["arrow.up", "arrow.down"],
        title: "Navigation"
    )
    static let paste = HistoryKeyboardGuideItem(
        symbolSystemNames: ["return"],
        title: "Paste"
    )
    static let accessibilityLabel = "Use Up and Down Arrow to navigate. Press Return to paste."
}

/// Intent is separated from SwiftUI event callbacks so keyboard and row actions
/// can be verified without depending on an XCUI event loop.
enum HistoryPanelIntent: Equatable {
    case moveSelection(by: Int)
    case paste(HistoryEntry)
    case close
    case select(UUID)
    case selectAndPaste(HistoryEntry)
    case delete(HistoryEntry)
}

/// Physical delete keys normalized before the local AppKit monitor decides
/// whether a History action is allowed. This seam does not inspect text.
enum HistorySearchDeleteKey: Equatable {
    case backward
    case forward
    case other
}

struct HistorySearchDeleteEvent: Equatable {
    let key: HistorySearchDeleteKey
    let hasDisallowedModifiers: Bool
    let isRepeat: Bool

    init(key: HistorySearchDeleteKey, hasDisallowedModifiers: Bool, isRepeat: Bool) {
        self.key = key
        self.hasDisallowedModifiers = hasDisallowedModifiers
        self.isRepeat = isRepeat
    }

    init(event: NSEvent) {
        // These macOS virtual key codes distinguish physical Backspace (51)
        // from Forward Delete (117), independent of the input source.
        let key: HistorySearchDeleteKey = switch event.keyCode {
        case 51: .backward
        case 117: .forward
        default: .other
        }
        // Caps Lock, Fn and numeric keypad flags do not change the delete
        // command. Only semantic shortcut modifiers must pass through.
        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        let hasDisallowedModifiers = !event.modifierFlags
            .intersection(disallowedModifiers)
            .isEmpty
        self.init(
            key: key,
            hasDisallowedModifiers: hasDisallowedModifiers,
            isRepeat: event.isARepeat
        )
    }
}

/// Limits the Search field's local delete shortcut to the one case where it
/// represents a History action. All other delete keys continue to text editing.
enum HistorySearchDeleteAdmission {
    static func selectedEntry(
        query: String,
        state: HistoryViewState,
        selectedEntry: HistoryEntry?
    ) -> HistoryEntry? {
        guard query.isEmpty, case .list = state else { return nil }
        return selectedEntry
    }

    static func selectedEntry(
        for event: HistorySearchDeleteEvent,
        isSearchFocused: Bool,
        isEventInKeyWindow: Bool,
        query: String,
        state: HistoryViewState,
        selectedEntry: HistoryEntry?
    ) -> HistoryEntry? {
        guard isSearchFocused,
              isEventInKeyWindow,
              !event.hasDisallowedModifiers,
              !event.isRepeat,
              event.key == .backward || event.key == .forward
        else { return nil }

        return Self.selectedEntry(query: query, state: state, selectedEntry: selectedEntry)
    }
}

/// A lifecycle-owned local monitor is required because an NSTextField-backed
/// SwiftUI TextField consumes editing Delete before SwiftUI `.onKeyPress` sees it.
/// The monitor is hosted only behind History Search and returns the original
/// event for every case that is not an admitted exact-occurrence deletion.
private struct HistorySearchDeleteKeyMonitor: NSViewRepresentable {
    let isSearchFocused: () -> Bool
    let query: () -> String
    let state: () -> HistoryViewState
    let selectedEntry: () -> HistoryEntry?
    let onDelete: (HistoryEntry) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isSearchFocused: isSearchFocused,
            query: query,
            state: state,
            selectedEntry: selectedEntry,
            onDelete: onDelete
        )
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.configure(
            isSearchFocused: isSearchFocused,
            query: query,
            state: state,
            selectedEntry: selectedEntry,
            onDelete: onDelete
        )
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.invalidate()
    }

    final class Coordinator {
        private weak var hostView: NSView?
        private var monitor: Any?
        private var isSearchFocused: () -> Bool
        private var query: () -> String
        private var state: () -> HistoryViewState
        private var selectedEntry: () -> HistoryEntry?
        private var onDelete: (HistoryEntry) -> Void

        init(
            isSearchFocused: @escaping () -> Bool,
            query: @escaping () -> String,
            state: @escaping () -> HistoryViewState,
            selectedEntry: @escaping () -> HistoryEntry?,
            onDelete: @escaping (HistoryEntry) -> Void
        ) {
            self.isSearchFocused = isSearchFocused
            self.query = query
            self.state = state
            self.selectedEntry = selectedEntry
            self.onDelete = onDelete
        }

        deinit {
            invalidate()
        }

        func attach(to view: NSView) {
            hostView = view
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.process(event) ?? event
            }
        }

        func configure(
            isSearchFocused: @escaping () -> Bool,
            query: @escaping () -> String,
            state: @escaping () -> HistoryViewState,
            selectedEntry: @escaping () -> HistoryEntry?,
            onDelete: @escaping (HistoryEntry) -> Void
        ) {
            self.isSearchFocused = isSearchFocused
            self.query = query
            self.state = state
            self.selectedEntry = selectedEntry
            self.onDelete = onDelete
        }

        func invalidate() {
            guard let monitor else { return }
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        private func process(_ event: NSEvent) -> NSEvent? {
            guard let hostWindow = hostView?.window else { return event }
            let isEventInSearchKeyWindow = event.window === hostWindow && hostWindow.isKeyWindow
            guard let entry = HistorySearchDeleteAdmission.selectedEntry(
                for: HistorySearchDeleteEvent(event: event),
                isSearchFocused: isSearchFocused(),
                isEventInKeyWindow: isEventInSearchKeyWindow,
                query: query(),
                state: state(),
                selectedEntry: selectedEntry()
            ) else {
                return event
            }

            onDelete(entry)
            return nil
        }
    }
}

/// Executes a deferred History UI intent without depending on SwiftUI. Keeping
/// this small seam makes selection, paste and destructive actions testable.
@MainActor
struct HistoryPanelIntentExecutor {
    let moveSelection: (Int) -> Void
    let select: (UUID) -> Void
    let canPaste: () -> Bool
    let pasteEntry: (HistoryEntry) -> Void
    let close: () -> Void
    let delete: (HistoryEntry) -> Void

    func execute(_ intent: HistoryPanelIntent) {
        switch intent {
        case let .moveSelection(offset):
            moveSelection(offset)
        case let .paste(entry):
            pasteIfAvailable(entry)
        case .close:
            close()
        case let .select(id):
            select(id)
        case let .selectAndPaste(entry):
            select(entry.id)
            pasteIfAvailable(entry)
        case let .delete(entry):
            delete(entry)
        }
    }

    private func pasteIfAvailable(_ entry: HistoryEntry) {
        guard canPaste() else { return }
        pasteEntry(entry)
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
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            stackContent

            if let statusMessage {
                Divider()
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
        }
        .frame(width: 400, height: 360, alignment: .topLeading)
        .accessibilityIdentifier("paste-stack-panel")
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
            }
            .modifier(PasteStackHeaderButtonChrome())
            .accessibilityLabel("Cancel Paste Stack")
            .accessibilityHint("Closes the panel and cancels the unfinished stack.")
            .help("Cancel Paste Stack")

            Spacer(minLength: 0)

            Text("Paste Stack")
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            directionToggle
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background {
            PasteStackWindowDragRegion()
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var stackContent: some View {
        if sessionController.occurrences.isEmpty {
            ContentUnavailableView(
                "Copy text to add it",
                systemImage: "doc.on.clipboard",
                description: Text("This stack starts empty and collects new copies only.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        } else {
            List {
                ForEach(sessionController.occurrences) { occurrence in
                    occurrenceRow(occurrence)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                .onMove { source, destination in
                    execute(.moveOccurrences(source, to: destination))
                }
                .moveDisabled(!canReorder)
            }
            .listStyle(.plain)
            .contentMargins(.horizontal, 0, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var statusMessage: String? {
        if let pasteFailure = sessionController.pasteFailure {
            pasteFailure.message
        } else if sessionController.hasCopyCommandDispatchFailure {
            "Qipli could not send Copy to the active app. Try the Paste Stack shortcut again."
        } else if sessionController.hasCaptureError {
            "Qipli could not save the last copied text. Copy it again to retry."
        } else {
            nil
        }
    }

    private var directionToggle: some View {
        let configuration = PasteStackDirectionToggleConfiguration.resolve(
            direction: sessionController.traversalDirection
        )
        return Button {
            execute(.setTraversalDirection(configuration.nextDirection))
        } label: {
            Image(systemName: configuration.iconSystemName)
                .font(.system(size: 13, weight: .semibold))
        }
        .modifier(PasteStackHeaderButtonChrome())
        .disabled(!canChooseDirection)
        .accessibilityLabel(PasteStackPanelAccessibility.directionLabel)
        .accessibilityValue(configuration.accessibilityValue)
        .accessibilityHint(configuration.accessibilityHint)
        .help(configuration.accessibilityHint)
    }

    private func occurrenceRow(_ occurrence: StackOccurrence) -> some View {
        let index = occurrence.position
        let isReactivationPriority = sessionController.reactivationPriorityID == occurrence.id
        let isNext = !sessionController.hasReactivationPriority
            && sessionController.nextOccurrence?.id == occurrence.id
        let isUsed = occurrence.state == .used
        let isPriorityNext = isNext || isReactivationPriority
        let accessibleMoves = controlState.accessibilityMoveDirections(position: index)

        return HStack(alignment: .top, spacing: 8) {
            if occurrence.state == .pending && canReorder {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            Text("\(index + 1).")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
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
            if isReactivationPriority {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel(
                        occurrence.state == .processing
                            ? PasteStackPanelAccessibility.reactivatingItemLabel
                            : PasteStackPanelAccessibility.reactivatedNextItemLabel
                    )
            } else if isNext {
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundStyle(.tint)
                    .accessibilityLabel(PasteStackPanelAccessibility.nextItemLabel)
            }
            if isUsed {
                Button {
                    execute(.reactivate(occurrence.id))
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(PasteStackPanelAccessibility.reactivateLabel(position: index))
                .accessibilityHint("Makes this used item the next stack paste. Press Command-V to send it.")
                .help("Reactivate")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .opacity(isUsed && !isReactivationPriority ? 0.55 : 1)
        .background {
            if isPriorityNext {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.45))
                    }
            }
        }
        // Keep native separators full-width, independent of compact status icons.
        .frame(maxWidth: .infinity, alignment: .leading)
        .alignmentGuide(.listRowSeparatorLeading) { dimensions in
            dimensions[.leading]
        }
        .alignmentGuide(.listRowSeparatorTrailing) { dimensions in
            dimensions[.trailing]
        }
        .accessibilityElement(children: .contain)
        .accessibilityActions {
            if accessibleMoves.contains(.up) {
                Button(PasteStackPanelAccessibility.moveActionLabel(direction: .up)) {
                    execute(.moveOccurrence(occurrence.id, by: -1))
                }
            }
            if accessibleMoves.contains(.down) {
                Button(PasteStackPanelAccessibility.moveActionLabel(direction: .down)) {
                    execute(.moveOccurrence(occurrence.id, by: 1))
                }
            }
        }
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

    private func execute(_ intent: PasteStackPanelIntent) {
        PasteStackPanelIntentExecutor(
            occurrences: { sessionController.occurrences },
            canAdjustTraversal: { sessionController.canAdjustTraversal },
            setTraversalDirection: sessionController.setTraversalDirection,
            reorder: sessionController.reorder,
            reactivate: sessionController.reactivateOccurrence,
            schedule: PasteStackPanelIntentScheduler.schedule
        )
        .execute(intent)
    }
}

private struct PasteStackHeaderButtonChrome: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .buttonStyle(.plain)
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.55))
            .frame(width: 28, height: 28)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered && isEnabled ? Color.primary.opacity(0.08) : Color.clear)
            }
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
    }
}

private struct PasteStackWindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowDragView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowDragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

/// UI requests are deliberately occurrence-ID based. This lets native drag
/// reordering and VoiceOver move actions share the same model boundary.
enum PasteStackPanelIntent: Equatable {
    case setTraversalDirection(StackTraversalDirection)
    case moveOccurrence(UUID, by: Int)
    case moveOccurrences(IndexSet, to: Int)
    case reactivate(UUID)
}

@MainActor
struct PasteStackPanelIntentExecutor {
    let occurrences: () -> [StackOccurrence]
    let canAdjustTraversal: () -> Bool
    let setTraversalDirection: (StackTraversalDirection) -> Bool
    let reorder: ([UUID]) -> Bool
    let reactivate: (UUID) -> Bool
    let schedule: (@escaping () -> Void) -> Void

    init(
        occurrences: @escaping () -> [StackOccurrence],
        canAdjustTraversal: @escaping () -> Bool,
        setTraversalDirection: @escaping (StackTraversalDirection) -> Bool,
        reorder: @escaping ([UUID]) -> Bool,
        reactivate: @escaping (UUID) -> Bool = { _ in false },
        schedule: @escaping (@escaping () -> Void) -> Void
    ) {
        self.occurrences = occurrences
        self.canAdjustTraversal = canAdjustTraversal
        self.setTraversalDirection = setTraversalDirection
        self.reorder = reorder
        self.reactivate = reactivate
        self.schedule = schedule
    }

    func execute(_ intent: PasteStackPanelIntent) {
        switch intent {
        case let .setTraversalDirection(direction):
            guard canAdjustTraversal() else { return }
            schedule { _ = setTraversalDirection(direction) }
        case let .moveOccurrence(id, offset):
            guard canAdjustTraversal() else { return }
            guard let ids = PasteStackOrdering.moving(id: id, by: offset, in: occurrences()) else { return }
            schedule { _ = reorder(ids) }
        case let .moveOccurrences(source, destination):
            guard canAdjustTraversal() else { return }
            guard let ids = PasteStackOrdering.moving(source: source, to: destination, in: occurrences()) else { return }
            schedule { _ = reorder(ids) }
        case let .reactivate(id):
            schedule { _ = reactivate(id) }
        }
    }
}

/// Defers SwiftUI callbacks until the surrounding List update has finished.
/// Reorder IDs are captured before this boundary, then validated by
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

    func accessibilityMoveDirections(position: Int) -> [PasteStackPanelAccessibility.MoveDirection] {
        var directions: [PasteStackPanelAccessibility.MoveDirection] = []
        if canMove(position: position, by: -1) {
            directions.append(.up)
        }
        if canMove(position: position, by: 1) {
            directions.append(.down)
        }
        return directions
    }
}

struct PasteStackDirectionToggleConfiguration: Equatable {
    let iconSystemName: String
    let nextDirection: StackTraversalDirection
    let accessibilityValue: String
    let accessibilityHint: String

    static func resolve(direction: StackTraversalDirection) -> Self {
        switch direction {
        case .direct:
            Self(
                iconSystemName: "arrow.down",
                nextDirection: .reverse,
                accessibilityValue: "Top to bottom",
                accessibilityHint: "Switches to bottom to top"
            )
        case .reverse:
            Self(
                iconSystemName: "arrow.up",
                nextDirection: .direct,
                accessibilityValue: "Bottom to top",
                accessibilityHint: "Switches to top to bottom"
            )
        }
    }
}

enum PasteStackPanelAccessibility {
    enum MoveDirection: Equatable {
        case up
        case down
    }

    static let directionLabel = "Traversal direction"
    static let nextItemLabel = "Next item"
    static let reactivatedNextItemLabel = "Reactivated item is next"
    static let reactivatingItemLabel = "Preparing reactivated item"

    static func moveActionLabel(direction: MoveDirection) -> String {
        switch direction {
        case .up: "Move Up"
        case .down: "Move Down"
        }
    }

    static func reactivateLabel(position: Int) -> String {
        "Reactivate used item \(position + 1)"
    }
}
