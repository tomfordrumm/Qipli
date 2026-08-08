import Combine
import Foundation

/// One in-memory reference to a successfully persisted clipboard occurrence.
/// Duplicate text is intentionally represented by separate IDs.
struct StackOccurrence: Identifiable, Equatable, Sendable {
    let id: UUID
    let historyEntryID: UUID
    let text: String
    /// The contiguous base visible order for this session.
    let position: Int
}

/// The direction used to choose the next pending occurrence from the visible base order.
enum StackTraversalDirection: String, CaseIterable, Hashable, Sendable {
    case direct
    case reverse

    var displayName: String {
        switch self {
        case .direct: "Direct"
        case .reverse: "Reverse"
        }
    }
}

/// Snapshot taken at pasteboard observation time. It binds deferred capture work
/// to both a particular session and the pasteboard watermark at its start.
struct StackCaptureContext: Equatable, Sendable {
    let sessionID: UUID
    let captureAfterChangeCount: Int
}

/// In-memory Stack state machine. Its base order and traversal direction are
/// configurable only before S006 starts traversal; it has no paste side effects.
final class StackSession {
    let captureContext: StackCaptureContext
    private(set) var occurrences: [StackOccurrence] = []
    private(set) var traversalDirection: StackTraversalDirection = .direct
    private(set) var traversalHasStarted = false

    var nextOccurrence: StackOccurrence? {
        switch traversalDirection {
        case .direct: occurrences.first
        case .reverse: occurrences.last
        }
    }

    var canAdjustTraversal: Bool { !traversalHasStarted }

    init(captureAfterChangeCount: Int) {
        captureContext = StackCaptureContext(
            sessionID: UUID(),
            captureAfterChangeCount: captureAfterChangeCount
        )
    }

    @discardableResult
    func append(historyEntry: HistoryEntry) -> StackOccurrence {
        let occurrence = StackOccurrence(
            id: UUID(),
            historyEntryID: historyEntry.id,
            text: historyEntry.text,
            position: occurrences.count
        )
        occurrences.append(occurrence)
        return occurrence
    }

    /// Replaces the base order atomically. Exact occurrence IDs, rather than
    /// text, make duplicate clipboard values safe to move independently.
    @discardableResult
    func reorder(occurrenceIDs: [UUID]) -> Bool {
        guard canAdjustTraversal,
              occurrenceIDs.count == occurrences.count,
              Set(occurrenceIDs).count == occurrences.count,
              Set(occurrenceIDs) == Set(occurrences.map(\.id))
        else { return false }

        let occurrencesByID = Dictionary(uniqueKeysWithValues: occurrences.map { ($0.id, $0) })
        occurrences = occurrenceIDs.enumerated().compactMap { position, id in
            guard let occurrence = occurrencesByID[id] else { return nil }
            return StackOccurrence(
                id: occurrence.id,
                historyEntryID: occurrence.historyEntryID,
                text: occurrence.text,
                position: position
            )
        }
        return true
    }

    @discardableResult
    func setTraversalDirection(_ direction: StackTraversalDirection) -> Bool {
        guard canAdjustTraversal else { return false }
        traversalDirection = direction
        return true
    }

    /// S006 calls this immediately before its first handled paste command.
    /// Keeping this mutation narrow makes the pre-paste configuration immutable.
    @discardableResult
    func markTraversalStarted() -> Bool {
        guard !traversalHasStarted else { return false }
        traversalHasStarted = true
        return true
    }
}

/// UI-facing lifetime owner for the one optional StackSession.
/// The session is released, rather than reset in place, when collection ends.
final class StackSessionController: ObservableObject {
    @Published private(set) var occurrences: [StackOccurrence] = []
    @Published private(set) var traversalDirection: StackTraversalDirection = .direct
    @Published private(set) var traversalHasStarted = false
    @Published private(set) var hasCaptureError = false
    @Published private(set) var hasCopyCommandDispatchFailure = false

    private(set) var session: StackSession?

    var isActive: Bool { session != nil }
    var nextOccurrence: StackOccurrence? { session?.nextOccurrence }
    var canAdjustTraversal: Bool { session?.canAdjustTraversal ?? false }
    /// Snapshot this on the pasteboard-observation turn before deferred work.
    /// It prevents older observations from entering a later session.
    var captureContext: StackCaptureContext? { session?.captureContext }

    /// Returns false for a repeated start, preserving the existing session intact.
    @discardableResult
    func startIfNeeded(captureAfterChangeCount: Int) -> Bool {
        guard session == nil else { return false }
        session = StackSession(captureAfterChangeCount: captureAfterChangeCount)
        publishSessionState()
        hasCaptureError = false
        hasCopyCommandDispatchFailure = false
        return true
    }

    /// A caller may append only after HistoryService has persisted the entry.
    func appendPersistedHistoryEntry(
        _ entry: HistoryEntry,
        observedChangeCount: Int,
        for captureContext: StackCaptureContext?
    ) {
        guard let captureContext,
              let session,
              session.captureContext == captureContext,
              observedChangeCount > captureContext.captureAfterChangeCount
        else { return }
        _ = session.append(historyEntry: entry)
        occurrences = session.occurrences
        hasCaptureError = false
    }

    /// Storage failures must be visible, but never create an in-memory orphan.
    func recordCaptureFailure(
        observedChangeCount: Int,
        for captureContext: StackCaptureContext?
    ) {
        guard let captureContext,
              session?.captureContext == captureContext,
              observedChangeCount > captureContext.captureAfterChangeCount
        else { return }
        hasCaptureError = true
    }

    func recordCopyCommandDispatchFailure() {
        guard isActive else { return }
        hasCopyCommandDispatchFailure = true
    }

    func clearCopyCommandDispatchFailure() {
        hasCopyCommandDispatchFailure = false
    }

    @discardableResult
    func reorder(occurrenceIDs: [UUID]) -> Bool {
        guard let session, session.reorder(occurrenceIDs: occurrenceIDs) else { return false }
        publishSessionState()
        return true
    }

    @discardableResult
    func setTraversalDirection(_ direction: StackTraversalDirection) -> Bool {
        guard let session, session.setTraversalDirection(direction) else { return false }
        publishSessionState()
        return true
    }

    /// This has no input interception or paste behavior in S005. It is the
    /// state-machine seam S006 will invoke before dispatching its first paste.
    @discardableResult
    func markTraversalStarted() -> Bool {
        guard let session, session.markTraversalStarted() else { return false }
        publishSessionState()
        return true
    }

    func cancel() {
        session = nil
        publishSessionState()
        hasCaptureError = false
        hasCopyCommandDispatchFailure = false
    }

    private func publishSessionState() {
        occurrences = session?.occurrences ?? []
        traversalDirection = session?.traversalDirection ?? .direct
        traversalHasStarted = session?.traversalHasStarted ?? false
    }
}

enum StackPreview {
    static let maximumCharacters = 180

    /// This affects only what the compact panel displays; occurrence.text remains exact.
    static func text(for fullText: String) -> String {
        guard fullText.count > maximumCharacters else { return fullText }
        return String(fullText.prefix(maximumCharacters)) + "…"
    }
}
