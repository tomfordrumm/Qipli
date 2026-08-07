import Foundation

/// A stable marker lets the event-tap callback distinguish Qipli's own synthetic input.
/// It prevents feedback loops; it is not used as an authenticity or security boundary.
enum SyntheticEventMarker {
    static let sourceUserData: Int64 = 0x5149_504C_49 // "QIPLI"

    static func isQipliSynthetic(sourceUserData: Int64) -> Bool {
        sourceUserData == self.sourceUserData
    }
}
