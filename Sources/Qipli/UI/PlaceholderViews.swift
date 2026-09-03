import AppKit
import SwiftUI

enum HistoryKeyboardActionScheduler {
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
        .padding(.top, 4)
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
            .accessibilityHint("Cancels the unfinished stack.")
            .help("Cancel Paste Stack")

            Text("Paste Stack")
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)
            directionToggle
        }
        .frame(height: 30)
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
