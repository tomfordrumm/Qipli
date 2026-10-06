import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Immutable key metadata is installed from the main-thread TIS snapshot; the tap only indexes it.
final class CorrectionInputClassifier: @unchecked Sendable {
    private let lock = NSLock()
    private var sourceID = ""
    private var targetPID: pid_t = 0
    private var table: [CorrectionPhysicalKey: String] = [:]

    func install(source: CorrectionSource?, targetPID: pid_t) {
        lock.lock(); defer { lock.unlock() }
        self.sourceID = source?.id ?? ""
        self.targetPID = targetPID
        table = source?.keyMap ?? [:]
    }

    func metadata(keyCode: Int64, flags: CGEventFlags) -> (sourceID: String, pid: pid_t, units: UInt8?, isSpace: Bool, uncertain: Bool) {
        lock.lock(); defer { lock.unlock() }
        guard (0..<128).contains(keyCode) else { return (sourceID, targetPID, nil, false, false) }
        let knownNonText = [36, 48, 51, 53, 71, 76, 114, 115, 116, 117, 119, 123, 124, 125, 126]
        if knownNonText.contains(Int(keyCode)) {
            return (sourceID, targetPID, nil, false, false)
        }
        // Modifier chords never contribute printable units to fresh-word proof. In
        // particular, Cmd-V must not make a pasted one-character token look typed.
        if flags.contains(.maskCommand) || flags.contains(.maskControl) ||
            flags.contains(.maskSecondaryFn) || flags.contains(.maskHelp) {
            return (sourceID, targetPID, nil, false, false)
        }
        var level: UInt8 = 0
        if flags.contains(.maskShift) { level |= 1 }
        if flags.contains(.maskAlphaShift) { level |= 2 }
        if flags.contains(.maskAlternate) {
            // Printable Option chords and possible dead-key paths are not admitted
            // as fresh word input; navigation/editing and Cmd/Ctrl chords are benign.
            let hasStaticOutput = table[CorrectionPhysicalKey(keyCode: UInt16(keyCode), level: level)] != nil
            let mayBeDeadKey = (0...50).contains(Int(keyCode))
            return (sourceID, targetPID, nil, false, hasStaticOutput || mayBeDeadKey)
        }
        guard let value = table[CorrectionPhysicalKey(keyCode: UInt16(keyCode), level: level)],
              value.utf16.count <= Int(UInt8.max) else {
            return (sourceID, targetPID, nil, false, (0...50).contains(Int(keyCode)))
        }
        return (sourceID, targetPID, UInt8(value.utf16.count), value == " ", false)
    }
}
