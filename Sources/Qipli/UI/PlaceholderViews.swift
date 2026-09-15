import AppKit
import SwiftUI

enum HistoryKeyboardActionScheduler {
    static func deferToNextMainRunLoop(_ action: @escaping () -> Void) {
        RunLoop.main.perform(inModes: [.common]) {
            action()
        }
    }
}

enum PasteStackPresentationSource {
    case hover
    case click
    case accessibility
}

enum PasteStackPresentationIntent {
    case expand(token: Int, preservesCurrentAlpha: Bool)
    case collapse(token: Int)
    case dismiss(token: Int)
}

@MainActor
final class PasteStackPresentationModel: ObservableObject {
    @Published private(set) var state: PasteStackPresentationState = .hidden
    @Published private(set) var compactGeometry: PasteStackCompactGeometry?

    var onIntent: ((PasteStackPresentationIntent) -> Void)?

    private(set) var generation = 0
    private var expandWorkItem: DispatchWorkItem?
    private var collapseWorkItem: DispatchWorkItem?
    private var pointerIsInside = false
    private var accessibilityHold = false
    private var interactionHoldCount = 0

    deinit {
        expandWorkItem?.cancel()
        collapseWorkItem?.cancel()
    }

    func beginSession(geometry: PasteStackCompactGeometry) {
        compactGeometry = geometry
        cancelScheduledTransitions()
        generation &+= 1
        state = PasteStackPresentationStateMachine.transition(state, event: .show)
        pointerIsInside = false
        accessibilityHold = false
        interactionHoldCount = 0
    }

    func close() {
        cancelScheduledTransitions()
        generation &+= 1
        state = .hidden
        compactGeometry = nil
        pointerIsInside = false
        accessibilityHold = false
        interactionHoldCount = 0
    }

    func updateGeometry(_ geometry: PasteStackCompactGeometry) {
        guard compactGeometry != geometry else { return }
        compactGeometry = geometry
        // A screen change invalidates both the old tracking region and any
        // hover decision made against it. A new region must receive a fresh
        // pointer-enter event before it can expand.
        cancelScheduledTransitions()
        generation &+= 1
        pointerIsInside = false

        switch state {
        case .expanding:
            // The old frame's animation completion is now stale. Restart the
            // reveal against the new frame with the new generation token.
            onIntent?(.expand(token: generation, preservesCurrentAlpha: false))
        case .collapsing:
            // A collapse that was interrupted by relocation can safely finish
            // at the new compact destination; leaving it in the old frame
            // would strand an invisible panel after its old completion fails.
            state = PasteStackPresentationStateMachine.transition(
                state,
                event: .collapseFinished
            )
        case .dismissing:
            // Re-arm dismissal so a stale completion cannot leave the panel
            // ordered on-screen after its display disappears.
            onIntent?(.dismiss(token: generation))
        case .hidden, .compact, .expanded:
            break
        }
    }

    func pointerEntered() {
        pointerIsInside = true
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
        if state == .collapsing {
            requestExpand(source: .hover)
            return
        }
        guard state == .compact else { return }
        scheduleExpand()
    }

    func pointerExited() {
        pointerIsInside = false
        expandWorkItem?.cancel()
        expandWorkItem = nil
        guard !accessibilityHold, interactionHoldCount == 0 else { return }
        guard state == .expanded || state == .expanding else { return }
        scheduleCollapse()
    }

    func beginInteractionHold() {
        interactionHoldCount += 1
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
    }

    func endInteractionHold() {
        interactionHoldCount = max(0, interactionHoldCount - 1)
        guard interactionHoldCount == 0,
              !pointerIsInside,
              !accessibilityHold,
              state == .expanded
        else { return }
        scheduleCollapse()
    }

    func requestExpand(source: PasteStackPresentationSource) {
        expandWorkItem?.cancel()
        expandWorkItem = nil
        guard state == .compact || state == .collapsing else { return }
        let reversesCollapse = state == .collapsing
        if source == .accessibility {
            accessibilityHold = true
        }
        generation &+= 1
        state = PasteStackPresentationStateMachine.transition(state, event: .expand)
        onIntent?(.expand(
            token: generation,
            preservesCurrentAlpha: reversesCollapse
        ))
    }

    func requestExplicitCollapse() {
        accessibilityHold = false
        requestCollapse(force: true)
    }

    func requestCollapse() {
        requestCollapse(force: false)
    }

    func finishExpansion(token: Int) {
        guard generation == token, state == .expanding else { return }
        state = PasteStackPresentationStateMachine.transition(state, event: .expansionFinished)
        if !pointerIsInside, !accessibilityHold {
            scheduleCollapse()
        }
    }

    func finishCollapse(token: Int) {
        guard generation == token, state == .collapsing else { return }
        state = PasteStackPresentationStateMachine.transition(state, event: .collapseFinished)
        if pointerIsInside {
            scheduleExpand()
        }
    }

    func requestDismissal() {
        guard state != .hidden else { return }
        cancelScheduledTransitions()
        accessibilityHold = false
        generation &+= 1
        state = PasteStackPresentationStateMachine.transition(state, event: .dismiss)
        onIntent?(.dismiss(token: generation))
    }

    func finishDismissal(token: Int) {
        guard generation == token, state == .dismissing else { return }
        state = PasteStackPresentationStateMachine.transition(state, event: .dismissalFinished)
    }

    func isCurrent(token: Int, state expectedState: PasteStackPresentationState) -> Bool {
        generation == token && state == expectedState
    }

    private func requestCollapse(force: Bool) {
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
        guard force || (!accessibilityHold && interactionHoldCount == 0) else { return }
        guard state == .expanded || state == .expanding else { return }
        generation &+= 1
        state = PasteStackPresentationStateMachine.transition(state, event: .collapse)
        onIntent?(.collapse(token: generation))
    }

    private func scheduleExpand() {
        expandWorkItem?.cancel()
        let expectedGeneration = generation
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.generation == expectedGeneration,
                  self.state == .compact,
                  self.pointerIsInside
            else { return }
            self.requestExpand(source: .hover)
        }
        expandWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func scheduleCollapse() {
        collapseWorkItem?.cancel()
        let expectedGeneration = generation
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.generation == expectedGeneration,
                  !self.pointerIsInside,
                  !self.accessibilityHold,
                  self.interactionHoldCount == 0
            else { return }
            self.requestCollapse()
        }
        collapseWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func cancelScheduledTransitions() {
        expandWorkItem?.cancel()
        collapseWorkItem?.cancel()
        expandWorkItem = nil
        collapseWorkItem = nil
    }
}

struct PasteStackPanelView: View {
    @ObservedObject var sessionController: StackSessionController
    @ObservedObject var presentationModel: PasteStackPresentationModel
    let expand: () -> Void
    let collapse: () -> Void
    let close: () -> Void

    var body: some View {
        Group {
            if presentationModel.state == .compact,
               let geometry = presentationModel.compactGeometry {
                compactPanel(geometry: geometry)
            } else {
                expandedPanel
            }
        }
        .accessibilityIdentifier("paste-stack-panel")
    }

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            stackContent
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, (presentationModel.compactGeometry?.panelFrame.height ?? 0) + 4)
        .padding(.horizontal, TopNotchHistoryGeometry.contentHorizontalInset)
        .padding(.bottom, 8)
        .frame(
            minWidth: TopNotchHistoryGeometry.pasteStackMinimumPanelSize.width,
            idealWidth: TopNotchHistoryGeometry.pasteStackPanelSize.width,
            maxWidth: .infinity,
            minHeight: TopNotchHistoryGeometry.pasteStackMinimumPanelSize.height,
            idealHeight: TopNotchHistoryGeometry.pasteStackPanelSize.height,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .environment(\.colorScheme, .dark)
    }

    private func compactPanel(geometry: PasteStackCompactGeometry) -> some View {
        Button(action: expand) {
            ZStack(alignment: .topLeading) {
                compactPreviews
                    .frame(width: geometry.localLeftContentRect.width, height: geometry.localLeftContentRect.height)
                    .clipped()
                    .offset(x: geometry.localLeftContentRect.minX, y: geometry.panelFrame.height - geometry.localLeftContentRect.maxY)
                compactStatus
                    .frame(width: geometry.localRightContentRect.width, height: geometry.localRightContentRect.height)
                    .clipped()
                    .offset(x: geometry.localRightContentRect.minX, y: geometry.panelFrame.height - geometry.localRightContentRect.maxY)
            }
            .frame(width: geometry.panelFrame.width, height: geometry.panelFrame.height, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .environment(\.colorScheme, .dark)
        .accessibilityAction(named: "Expand Paste Stack") {
            presentationModel.requestExpand(source: .accessibility)
        }
    }

    private var compactPreviews: some View {
        let previews = Array(sessionController.occurrences.suffix(3))
        return GeometryReader { proxy in
            let side = max(1, min(proxy.size.height - 6, proxy.size.width - 8))
            ZStack(alignment: .topLeading) {
                if previews.isEmpty {
                    Image(systemName: "square.on.square")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: side, height: side)
                } else {
                    ForEach(Array(previews.enumerated()), id: \.element.id) { index, occurrence in
                        let depth = CGFloat(previews.count - 1 - index)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(white: 0.24 + Double(index) * 0.08))
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5))
                            .frame(width: side, height: side)
                            .overlay(alignment: .topLeading) {
                                Text(compactPreview(for: occurrence.text))
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .allowsTightening(true)
                                    .padding(3)
                                    .frame(width: side, height: side, alignment: .topLeading)
                                    .clipped()
                            }
                            .offset(x: depth * 3, y: depth * 3)
                    }
                }
            }
            .offset(x: 8, y: max(0, (proxy.size.height - side - 6) / 2))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(previews.isEmpty ? "Paste Stack is empty" : "Recent Paste Stack items")
        .accessibilityValue(previews.map { compactPreview(for: $0.text) }.joined(separator: ", "))
    }

    private var compactStatus: some View {
        HStack(spacing: 5) {
            if hasProcessingOccurrence {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityLabel("Processing")
            }
            if statusMessage != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .accessibilityLabel("Paste Stack error")
            }
            if sessionController.hasReactivationPriority {
                Image(systemName: "arrow.counterclockwise")
                    .foregroundStyle(.orange)
            }
            Text("\(sessionController.occurrences.count)")
                .font(.system(size: 17, weight: .semibold).monospacedDigit())
                .accessibilityLabel("Copied items")
        }
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Paste Stack status")
        .accessibilityValue("\(sessionController.occurrences.count) copied")
    }

    private var pendingCount: Int {
        sessionController.occurrences.reduce(into: 0) { count, occurrence in
            if occurrence.state == .pending { count += 1 }
        }
    }

    private var hasProcessingOccurrence: Bool {
        sessionController.occurrences.contains { $0.state == .processing }
    }

    private func compactPreview(for text: String) -> String {
        let preview = StackPreview.text(for: text)
        guard preview.count > 32 else { return preview }
        return String(preview.prefix(31)) + "…"
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
            }
            .modifier(PasteStackHeaderButtonChrome())
            .accessibilityLabel("Cancel Paste Stack")
            .accessibilityHint("Cancels the unfinished stack.")
            .help("Cancel Paste Stack")

            Button(action: collapse) {
                Image(systemName: "arrow.up.to.line")
                    .font(.system(size: 13, weight: .semibold))
            }
            .modifier(PasteStackHeaderButtonChrome())
            .accessibilityLabel("Collapse Paste Stack")
            .accessibilityHint("Returns to the compact Paste Stack strip.")
            .help("Collapse Paste Stack")

            Text("Paste Stack")
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)
            directionToggle
        }
        .frame(height: 30)
        .accessibilityAction(named: "Collapse Paste Stack") {
            presentationModel.requestExplicitCollapse()
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
        } else {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(sessionController.occurrences) { occurrence in
                        occurrenceCard(occurrence)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var statusMessage: String? {
        if let pasteFailure = sessionController.pasteFailure {
            pasteFailure.message
        } else if sessionController.hasCopyCommandDispatchFailure {
            "Qipli could not send Copy to the active app. Try the Paste Stack shortcut again."
        } else if let message = sessionController.nonTextCaptureFailureMessage {
            message
        } else if sessionController.hasCaptureError {
            "Qipli could not save the last copied text. Copy it again to retry."
        } else if sessionController.hasNonTextCaptureNotice {
            "Non-text item saved to History. Paste Stack currently accepts text only."
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

    private func occurrenceCard(_ occurrence: StackOccurrence) -> some View {
        let index = occurrence.position
        let isReactivationPriority = sessionController.reactivationPriorityID == occurrence.id
        let isNext = !sessionController.hasReactivationPriority
            && sessionController.nextOccurrenceID == occurrence.id
        let isUsed = occurrence.state == .used
        let isPriorityNext = isNext || isReactivationPriority
        let accessibleMoves = controlState.accessibilityMoveDirections(position: index)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("\(index + 1)")
                    .font(.headline.monospacedDigit())
                if isNext {
                    Label("Next", systemImage: "arrow.right.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.tint)
                } else if isReactivationPriority {
                    Label("Next again", systemImage: "arrow.counterclockwise.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer(minLength: 0)
                if occurrence.state == .processing {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Preparing paste")
                } else if isUsed {
                    Label("Used", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(StackPreview.text(for: occurrence.text))
                .font(.system(size: 14, weight: .medium))
                .lineLimit(3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack(spacing: 4) {
                if canReorder {
                    Button {
                        execute(.moveOccurrence(occurrence.id, by: -1))
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .modifier(PasteStackCardButtonChrome())
                    .disabled(!accessibleMoves.contains(.up))
                    .accessibilityLabel(PasteStackPanelAccessibility.moveActionLabel(direction: .up))

                    Button {
                        execute(.moveOccurrence(occurrence.id, by: 1))
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .modifier(PasteStackCardButtonChrome())
                    .disabled(!accessibleMoves.contains(.down))
                    .accessibilityLabel(PasteStackPanelAccessibility.moveActionLabel(direction: .down))
                }
                Spacer(minLength: 0)
                if isUsed {
                    Button {
                        execute(.reactivate(occurrence.id))
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .modifier(PasteStackCardButtonChrome())
                    .accessibilityLabel(PasteStackPanelAccessibility.reactivateLabel(position: index))
                    .accessibilityHint("Makes this used item the next stack paste.")
                    .help("Reactivate")
                }
            }
        }
        .padding(10)
        .frame(width: 208, height: 136, alignment: .topLeading)
        .textSelection(.disabled)
        .opacity(isUsed && !isReactivationPriority ? 0.55 : 1)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isPriorityNext ? Color.accentColor.opacity(0.16) : Color.white.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isPriorityNext ? Color.accentColor.opacity(0.60) : Color.white.opacity(0.12))
                }
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

private struct PasteStackCardButtonChrome: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .buttonStyle(.plain)
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.45))
            .frame(width: 26, height: 26)
            .background(Color.white.opacity(isEnabled ? 0.08 : 0.03), in: Circle())
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
