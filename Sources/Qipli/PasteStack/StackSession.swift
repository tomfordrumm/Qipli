import Combine
import Foundation

/// One in-memory reference to a successfully persisted clipboard occurrence.
/// Duplicate text is intentionally represented by separate IDs.
struct StackOccurrence: Identifiable, Equatable, Sendable {
    let id: UUID
    let historyEntryID: UUID
    let text: String
    /// The append order for this session. Reordering is introduced in S005.
    let position: Int
}

/// Snapshot taken at pasteboard observation time. It binds deferred capture work
/// to both a particular session and the pasteboard watermark at its start.
struct StackCaptureContext: Equatable, Sendable {
    let sessionID: UUID
    let captureAfterChangeCount: Int
}

/// Minimal domain object for S004 collection. It deliberately has no traversal,
/// used-state, or persistence behavior; those belong to later slices.
final class StackSession {
    let captureContext: StackCaptureContext
    private(set) var occurrences: [StackOccurrence] = []

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
}

/// UI-facing lifetime owner for the one optional StackSession.
/// The session is released, rather than reset in place, when collection ends.
final class StackSessionController: ObservableObject {
    @Published private(set) var occurrences: [StackOccurrence] = []
    @Published private(set) var hasCaptureError = false

    private(set) var session: StackSession?

    var isActive: Bool { session != nil }
    /// Snapshot this on the pasteboard-observation turn before deferred work.
    /// It prevents older observations from entering a later session.
    var captureContext: StackCaptureContext? { session?.captureContext }

    /// Returns false for a repeated start, preserving the existing session intact.
    @discardableResult
    func startIfNeeded(captureAfterChangeCount: Int) -> Bool {
        guard session == nil else { return false }
        session = StackSession(captureAfterChangeCount: captureAfterChangeCount)
        occurrences = []
        hasCaptureError = false
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

    func cancel() {
        session = nil
        occurrences = []
        hasCaptureError = false
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
