import Foundation

/// A single clipboard occurrence. Equal text copied twice remains two entries.
struct HistoryEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let text: String
    /// Initial capture time, subsequently updated only after successful history paste dispatch.
    let activityAt: Date
}
