import Combine
import Foundation

/// The UI state of one exact in-memory occurrence. A processing reservation is
/// deliberately separate from `used`: Qipli has not sent a paste command yet.
enum StackOccurrenceState: Equatable, Sendable {
    case pending
    case processing
    case used
}

/// One in-memory reference to a successfully persisted clipboard occurrence.
/// Duplicate text is intentionally represented by separate IDs.
struct StackOccurrence: Identifiable, Equatable, Sendable {
    let id: UUID
    let historyEntryID: UUID
    let text: String
    /// The contiguous base visible order for this session.
    let position: Int
    let state: StackOccurrenceState

    init(
        id: UUID,
        historyEntryID: UUID,
        text: String,
        position: Int,
        state: StackOccurrenceState = .pending
    ) {
        self.id = id
        self.historyEntryID = historyEntryID
        self.text = text
        self.position = position
        self.state = state
    }
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

/// The prior state to restore when deferred paste production cannot finish.
/// A reactivation never becomes pending: it remains used and keeps its
/// one-shot priority until a tagged command is successfully dispatched.
enum StackPasteReservationOrigin: Equatable, Sendable {
    case traversal
    case reactivation
}

enum StackNextOccurrenceResolver {
    /// Returns the exact next index in at most one traversal. When a reactivation
    /// priority exists, the same pass remembers the directional pending fallback.
    static func index(
        in occurrences: [StackOccurrence],
        direction: StackTraversalDirection,
        reactivationPriorityID: UUID?,
        didInspect: (() -> Void)? = nil
    ) -> Int? {
        var pendingFallback: Int?
        switch direction {
        case .direct:
            for index in occurrences.indices {
                didInspect?()
                let occurrence = occurrences[index]
                if occurrence.id == reactivationPriorityID, occurrence.state == .used {
                    return index
                }
                if pendingFallback == nil, occurrence.state == .pending {
                    pendingFallback = index
                    if reactivationPriorityID == nil { return index }
                }
            }
        case .reverse:
            for index in occurrences.indices.reversed() {
                didInspect?()
                let occurrence = occurrences[index]
                if occurrence.id == reactivationPriorityID, occurrence.state == .used {
                    return index
                }
                if pendingFallback == nil, occurrence.state == .pending {
                    pendingFallback = index
                    if reactivationPriorityID == nil { return index }
                }
            }
        }
        return pendingFallback
    }
}

/// Immutable snapshot handed from the synchronous event-tap reservation to
/// deferred paste production. It contains no mutable UI state.
struct StackPasteReservation: Equatable, Sendable {
    let sessionID: UUID
    let occurrence: StackOccurrence
    let origin: StackPasteReservationOrigin
}

/// In-memory Stack state machine. Its base order and traversal direction are
/// configurable only before S006 starts traversal; it has no paste side effects.
final class StackSession {
    let captureContext: StackCaptureContext
    private(set) var occurrences: [StackOccurrence] = []
    private(set) var occurrencesRevision: UInt64 = 0
    private(set) var traversalDirection: StackTraversalDirection = .direct
    private(set) var traversalHasStarted = false
    private(set) var reservedOccurrenceID: UUID?
    private(set) var reservedOccurrenceOrigin: StackPasteReservationOrigin?
    /// At most one already-used occurrence can take precedence over traversal.
    /// It intentionally survives a failed retry and is cleared only after its
    /// tagged paste command dispatch completes.
    private(set) var reactivationPriorityID: UUID?
    /// This is deliberately a single exact UUID, not an undo history. It is
    /// updated only after Qipli successfully dispatches tagged Command-V.
    private(set) var lastSuccessfullyDispatchedOccurrenceID: UUID?
    private let onNextTraversalVisit: (() -> Void)?

    var nextOccurrence: StackOccurrence? {
        guard let index = nextOccurrenceIndex else { return nil }
        return occurrences[index]
    }

    var hasPendingOccurrence: Bool { occurrences.contains { $0.state == .pending } }
    var reservedOccurrence: StackOccurrence? {
        guard let reservedOccurrenceID else { return nil }
        return occurrence(id: reservedOccurrenceID)
    }

    var canAdjustTraversal: Bool { !traversalHasStarted }

    init(captureAfterChangeCount: Int, onNextTraversalVisit: (() -> Void)? = nil) {
        captureContext = StackCaptureContext(
            sessionID: UUID(),
            captureAfterChangeCount: captureAfterChangeCount
        )
        self.onNextTraversalVisit = onNextTraversalVisit
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
        occurrencesRevision &+= 1
        return occurrence
    }

    /// Atomically selects either the one-shot reactivation priority or the
    /// traversal next occurrence, then locks traversal. The caller must either
    /// complete or release this reservation.
    func reserveNextOccurrenceForPaste() -> StackOccurrence? {
        guard reservedOccurrenceID == nil, let index = nextOccurrenceIndex else { return nil }
        let nextOccurrence = occurrences[index]
        traversalHasStarted = true
        reservedOccurrenceID = nextOccurrence.id
        reservedOccurrenceOrigin = nextOccurrence.id == reactivationPriorityID
            ? .reactivation
            : .traversal
        occurrences[index] = replacingState(of: nextOccurrence, with: .processing)
        occurrencesRevision &+= 1
        return occurrences[index]
    }

    @discardableResult
    func completeReservation(id: UUID) -> Bool {
        guard reservedOccurrenceID == id, let reservedOccurrenceOrigin else { return false }
        updateOccurrence(id: id, state: .used)
        reservedOccurrenceID = nil
        self.reservedOccurrenceOrigin = nil
        if reservedOccurrenceOrigin == .reactivation, reactivationPriorityID == id {
            reactivationPriorityID = nil
        }
        lastSuccessfullyDispatchedOccurrenceID = id
        return true
    }

    @discardableResult
    func releaseReservation(id: UUID) -> Bool {
        guard reservedOccurrenceID == id, let reservedOccurrenceOrigin else { return false }
        updateOccurrence(id: id, state: reservedOccurrenceOrigin == .reactivation ? .used : .pending)
        reservedOccurrenceID = nil
        self.reservedOccurrenceOrigin = nil
        return true
    }

    func isReservationCurrent(_ id: UUID) -> Bool {
        reservedOccurrenceID == id
    }

    var isCompleted: Bool {
        reservedOccurrenceID == nil
            && reactivationPriorityID == nil
            && !occurrences.isEmpty
            && occurrences.allSatisfy { $0.state == .used }
    }

    /// Makes one exact used occurrence the next paste without changing the
    /// pending traversal cursor. Repeating the same request is safe.
    @discardableResult
    func reactivateOccurrence(id: UUID) -> Bool {
        guard occurrence(id: id)?.state == .used
        else { return false }
        reactivationPriorityID = id
        return true
    }

    /// Reactivates only the latest successfully dispatched occurrence. An
    /// ordinary traversal reservation can continue unchanged while this becomes
    /// its subsequent one-shot priority. A reactivation reservation itself is
    /// processing (and therefore cannot be selected again).
    @discardableResult
    func reactivatePreviousOccurrence() -> StackReactivationInputDisposition {
        guard lastSuccessfullyDispatchedOccurrenceID != nil else { return .passThrough }
        guard let lastSuccessfullyDispatchedOccurrenceID,
              reactivateOccurrence(id: lastSuccessfullyDispatchedOccurrenceID)
        else { return .consume }
        return .consumeAndReactivate
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
                position: position,
                state: occurrence.state
            )
        }
        occurrencesRevision &+= 1
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

    private func occurrence(id: UUID) -> StackOccurrence? {
        occurrences.first { $0.id == id }
    }

    private var nextOccurrenceIndex: Int? {
        StackNextOccurrenceResolver.index(
            in: occurrences,
            direction: traversalDirection,
            reactivationPriorityID: reactivationPriorityID,
            didInspect: onNextTraversalVisit
        )
    }

    private func updateOccurrence(id: UUID, state: StackOccurrenceState) {
        guard let index = occurrences.firstIndex(where: { $0.id == id }) else { return }
        occurrences[index] = replacingState(of: occurrences[index], with: state)
        occurrencesRevision &+= 1
    }

    private func replacingState(
        of occurrence: StackOccurrence,
        with state: StackOccurrenceState
    ) -> StackOccurrence {
        StackOccurrence(
            id: occurrence.id,
            historyEntryID: occurrence.historyEntryID,
            text: occurrence.text,
            position: occurrence.position,
            state: state
        )
    }
}

enum StackPasteFailure: Equatable {
    case accessibilityRequired
    case pasteboardWriteFailed
    case commandDispatchFailed
    case inputUnavailable

    var message: String {
        switch self {
        case .accessibilityRequired:
            "Accessibility access is required before Qipli can send the next stack item. Restore access and try again."
        case .pasteboardWriteFailed:
            "Qipli could not prepare the system clipboard. Try the next stack item again."
        case .commandDispatchFailed:
            "Qipli could not send the paste command. The stack item is still pending; try again."
        case .inputUnavailable:
            "Qipli’s global input listener is unavailable. Restore Accessibility access and try again."
        }
    }
}

/// UI-facing lifetime owner for the one optional StackSession.
/// The session is released, rather than reset in place, when collection ends.
final class StackSessionController: ObservableObject {
    private(set) var traversalDirection: StackTraversalDirection = .direct
    private(set) var traversalHasStarted = false
    @Published private(set) var hasCaptureError = false
    @Published private(set) var hasNonTextCaptureNotice = false
    @Published private(set) var nonTextCaptureFailureMessage: String?
    @Published private(set) var hasCopyCommandDispatchFailure = false
    @Published private(set) var pasteFailure: StackPasteFailure?
    private(set) var reactivationPriorityID: UUID?
    private(set) var nextOccurrenceID: UUID?

    private(set) var session: StackSession?
    private let onNextTraversalVisit: (() -> Void)?
    private var publishedSessionID: UUID?
    private var publishedOccurrencesRevision: UInt64 = 0

    var isActive: Bool { session != nil }
    /// The session is the only long-lived owner of this array. Returning it on
    /// demand avoids retaining a second `@Published` Array buffer that forces a
    /// copy-on-write of the whole Stack on the next append.
    var occurrences: [StackOccurrence] { session?.occurrences ?? [] }
    var nextOccurrence: StackOccurrence? {
        guard let nextOccurrenceID else { return nil }
        return occurrences.first { $0.id == nextOccurrenceID }
    }
    var hasReactivationPriority: Bool { reactivationPriorityID != nil }
    var canAdjustTraversal: Bool { session?.canAdjustTraversal ?? false }
    var hasPendingOccurrence: Bool { session?.hasPendingOccurrence ?? false }
    var currentPasteReservation: StackPasteReservation? {
        guard let session,
              let occurrence = session.reservedOccurrence,
              let origin = session.reservedOccurrenceOrigin
        else { return nil }
        return StackPasteReservation(
            sessionID: session.captureContext.sessionID,
            occurrence: occurrence,
            origin: origin
        )
    }
    /// Snapshot this on the pasteboard-observation turn before deferred work.
    /// It prevents older observations from entering a later session.
    var captureContext: StackCaptureContext? { session?.captureContext }

    init(onNextTraversalVisit: (() -> Void)? = nil) {
        self.onNextTraversalVisit = onNextTraversalVisit
    }

    /// Returns false for a repeated start, preserving the existing session intact.
    @discardableResult
    func startIfNeeded(captureAfterChangeCount: Int) -> Bool {
        guard session == nil else { return false }
        session = StackSession(
            captureAfterChangeCount: captureAfterChangeCount,
            onNextTraversalVisit: onNextTraversalVisit
        )
        publishSessionState()
        setCaptureError(false)
        setNonTextCaptureNotice(false)
        setNonTextCaptureFailureMessage(nil)
        setCopyCommandDispatchFailure(false)
        setPasteFailure(nil)
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
        publishSessionState()
        setCaptureError(false)
        setNonTextCaptureNotice(false)
        setNonTextCaptureFailureMessage(nil)
    }

    /// Media is durable History content, but the first typed Stack remains
    /// text-only. This notice must not mutate the active stack session.
    func recordNonTextCapture(
        observedChangeCount: Int,
        for captureContext: StackCaptureContext?
    ) {
        guard let captureContext,
              session?.captureContext == captureContext,
              observedChangeCount > captureContext.captureAfterChangeCount
        else { return }
        setNonTextCaptureFailureMessage(nil)
        setNonTextCaptureNotice(true)
    }

    func recordNonTextCaptureFailure(
        message: String,
        observedChangeCount: Int,
        for captureContext: StackCaptureContext?
    ) {
        guard let captureContext,
              session?.captureContext == captureContext,
              observedChangeCount > captureContext.captureAfterChangeCount
        else { return }
        setNonTextCaptureFailureMessage(message)
        setNonTextCaptureNotice(false)
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
        setCaptureError(true)
    }

    func recordCopyCommandDispatchFailure() {
        guard isActive else { return }
        setCopyCommandDispatchFailure(true)
    }

    func clearCopyCommandDispatchFailure() {
        setCopyCommandDispatchFailure(false)
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

    /// This is called synchronously by the active event tap. It changes only
    /// private domain state; the deferred executor publishes the processing
    /// UI state after the current event-loop turn.
    func acceptNextPasteInput() -> StackPasteInputDisposition {
        guard let session else { return .passThrough }
        guard session.reservedOccurrenceID == nil else { return .consume }
        guard session.reserveNextOccurrenceForPaste() != nil else { return .passThrough }
        return .consumeAndDispatch
    }

    /// The event tap calls this synchronously. It changes only domain state;
    /// the callback schedules the observed-object update after the current
    /// event-loop turn so List layout is never mutated in-place.
    func acceptReactivatePreviousInput() -> StackReactivationInputDisposition {
        guard let session else { return .passThrough }
        return session.reactivatePreviousOccurrence()
    }

    /// Reactivate is exposed by UI only for used rows, but validates the exact
    /// UUID again so stale/deferred List actions cannot change another row.
    @discardableResult
    func reactivateOccurrence(id: UUID) -> Bool {
        guard let session, session.reactivateOccurrence(id: id) else { return false }
        publishSessionState()
        return true
    }

    func publishAcceptedReactivatePreviousState() {
        guard session?.reactivationPriorityID != nil else { return }
        publishSessionState()
    }

    func publishReservedPasteState() {
        guard session?.reservedOccurrenceID != nil else { return }
        setPasteFailure(nil)
        publishSessionState()
    }

    func isPasteReservationCurrent(_ reservation: StackPasteReservation) -> Bool {
        guard session?.captureContext.sessionID == reservation.sessionID else { return false }
        return session?.isReservationCurrent(reservation.occurrence.id) ?? false
    }

    func completePasteReservation(_ reservation: StackPasteReservation) -> Bool {
        guard session?.captureContext.sessionID == reservation.sessionID,
              let session,
              session.completeReservation(id: reservation.occurrence.id)
        else { return false }
        setPasteFailure(nil)
        publishSessionState()
        return true
    }

    func releasePasteReservation(_ reservation: StackPasteReservation, failure: StackPasteFailure) {
        guard session?.captureContext.sessionID == reservation.sessionID,
              let session,
              session.releaseReservation(id: reservation.occurrence.id)
        else { return }
        setPasteFailure(failure)
        publishSessionState()
    }

    func recordInputUnavailable() {
        guard let session else { return }
        if let reservationID = session.reservedOccurrenceID {
            _ = session.releaseReservation(id: reservationID)
        }
        setPasteFailure(.inputUnavailable)
        publishSessionState()
    }

    /// Called one deferred turn after publishing the final all-used snapshot.
    @discardableResult
    func finishCompletedSession(sessionID: UUID) -> Bool {
        guard session?.captureContext.sessionID == sessionID, session?.isCompleted == true else { return false }
        cancel()
        return true
    }

    func cancel() {
        session = nil
        publishSessionState()
        setCaptureError(false)
        setNonTextCaptureNotice(false)
        setNonTextCaptureFailureMessage(nil)
        setCopyCommandDispatchFailure(false)
        setPasteFailure(nil)
    }

    private func publishSessionState() {
        let newSessionID = session?.captureContext.sessionID
        let newOccurrencesRevision = session?.occurrencesRevision ?? 0
        let newDirection = session?.traversalDirection ?? .direct
        let newTraversalHasStarted = session?.traversalHasStarted ?? false
        let newReactivationPriorityID = session?.reactivationPriorityID
        let newNextOccurrenceID = session?.nextOccurrence?.id

        guard publishedSessionID != newSessionID
                || publishedOccurrencesRevision != newOccurrencesRevision
                || traversalDirection != newDirection
                || traversalHasStarted != newTraversalHasStarted
                || reactivationPriorityID != newReactivationPriorityID
                || nextOccurrenceID != newNextOccurrenceID
        else { return }

        objectWillChange.send()
        publishedSessionID = newSessionID
        publishedOccurrencesRevision = newOccurrencesRevision
        nextOccurrenceID = newNextOccurrenceID
        traversalDirection = newDirection
        traversalHasStarted = newTraversalHasStarted
        reactivationPriorityID = newReactivationPriorityID
    }

    private func setPasteFailure(_ newValue: StackPasteFailure?) {
        guard pasteFailure != newValue else { return }
        pasteFailure = newValue
    }

    private func setCaptureError(_ newValue: Bool) {
        guard hasCaptureError != newValue else { return }
        hasCaptureError = newValue
    }

    private func setNonTextCaptureNotice(_ newValue: Bool) {
        guard hasNonTextCaptureNotice != newValue else { return }
        hasNonTextCaptureNotice = newValue
    }

    private func setNonTextCaptureFailureMessage(_ newValue: String?) {
        guard nonTextCaptureFailureMessage != newValue else { return }
        nonTextCaptureFailureMessage = newValue
    }

    private func setCopyCommandDispatchFailure(_ newValue: Bool) {
        guard hasCopyCommandDispatchFailure != newValue else { return }
        hasCopyCommandDispatchFailure = newValue
    }
}

enum StackPreview {
    static let maximumCharacters = 180

    /// This affects only what the compact panel displays; occurrence.text remains exact.
    static func text(for fullText: String) -> String {
        BoundedTextPreview.text(for: fullText, maximumCharacters: maximumCharacters)
    }
}
