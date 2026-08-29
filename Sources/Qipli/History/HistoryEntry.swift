import Foundation

/// A single clipboard occurrence. Equal text copied twice remains two entries.
struct HistoryEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let text: String
    /// Initial capture time, subsequently updated only after successful history paste dispatch.
    let activityAt: Date
}

enum BoundedTextPreview {
    /// Builds a display-only value without asking String for its full Character count.
    /// `didTraverse` is an internal measurement seam and must never retain payload data.
    static func text(
        for fullText: String,
        maximumCharacters: Int,
        didTraverse: ((Character) -> Void)? = nil
    ) -> String {
        precondition(maximumCharacters >= 0)
        var boundary = fullText.startIndex
        var traversed = 0
        while boundary != fullText.endIndex, traversed <= maximumCharacters {
            let character = fullText[boundary]
            didTraverse?(character)
            boundary = fullText.index(after: boundary)
            traversed += 1
        }

        guard traversed > maximumCharacters else { return fullText }
        let displayEnd = fullText.index(before: boundary)
        return String(fullText[..<displayEnd]) + "…"
    }
}

enum HistoryPreview {
    static let maximumCharacters = 240

    static func text(for fullText: String) -> String {
        BoundedTextPreview.text(for: fullText, maximumCharacters: maximumCharacters)
    }
}
