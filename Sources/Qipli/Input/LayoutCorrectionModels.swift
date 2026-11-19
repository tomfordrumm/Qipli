import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation

struct CorrectionSource: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let isCurrent: Bool
    let keyMap: [CorrectionPhysicalKey: String]

    var isEligible: Bool { !keyMap.isEmpty }
}

struct CorrectionPhysicalKey: Hashable, Sendable {
    let keyCode: UInt16
    let level: UInt8 // bit 0: Shift, bit 1: Caps Lock
}

struct CorrectionMapping: Equatable, Sendable {
    let sourceID: String
    let text: String
}

enum CorrectionMappingError: Error, Equatable {
    case unsupportedCharacter
    case ambiguousSource
    case ambiguousDestination
    case unchanged
}

enum LayoutCorrectionMapper {
    static func origin(for text: String, from sources: [CorrectionSource], activeSourceID: String?) throws -> CorrectionSource {
        let sorted = sources.filter(\.isEligible).sorted { $0.id < $1.id }
        let known = text.filter { character in sorted.contains { $0.keyMap.values.contains(String(character)) } }
        guard !known.isEmpty else { throw CorrectionMappingError.unsupportedCharacter }
        if let current = sorted.first(where: { $0.id == activeSourceID }), represents(known, in: current) {
            return current
        }
        let eligible = sorted.filter { represents(known, in: $0) }
        guard eligible.count == 1, let only = eligible.first else {
            throw eligible.isEmpty ? CorrectionMappingError.unsupportedCharacter : .ambiguousSource
        }
        return only
    }

    static func map(
        _ text: String,
        from sources: [CorrectionSource],
        activeSourceID: String?,
        to destinationSourceID: String
    ) throws -> CorrectionMapping {
        guard !text.isEmpty else { throw CorrectionMappingError.unsupportedCharacter }
        let sorted = sources.filter(\.isEligible).sorted { $0.id < $1.id }
        let origin = try origin(for: text, from: sorted, activeSourceID: activeSourceID)
        guard let destination = sorted.first(where: { $0.id == destinationSourceID }) else {
            throw CorrectionMappingError.unsupportedCharacter
        }

        let mapped = try text.map { character -> String in
            let candidates = origin.keyMap.filter { $0.value == String(character) }.map(\.key)
            guard !candidates.isEmpty else {
                let existsInAnySource = sorted.contains { $0.keyMap.values.contains(String(character)) }
                guard !existsInAnySource else {
                    throw CorrectionMappingError.unsupportedCharacter
                }
                return String(character)
            }
            return try destinationOutput(for: candidates, in: destination)
        }
        let result = mapped.joined()
        guard result != text else { throw CorrectionMappingError.unchanged }
        return CorrectionMapping(sourceID: origin.id, text: result)
    }

    /// Keypad keys produce layout-independent digits/operators, and Caps Lock levels
    /// duplicate the plain/Shift output of punctuation keys. Treating those
    /// duplicates as equal candidates made `, . ; ' [ ] \` (б ю ж э х ъ ё in
    /// Russian) ambiguous. A character resolves through the most canonical
    /// tier: main keys before keypad, then plain, Shift, Caps Lock, Shift+Caps.
    /// Two keys of the same tier with different outputs remain ambiguous.
    static func destinationOutput(for candidates: [CorrectionPhysicalKey], in destination: CorrectionSource) throws -> String {
        let tiers = Dictionary(grouping: candidates) { key in
            (keypadKeyCodes.contains(key.keyCode) ? 4 : 0) + Int(key.level)
        }
        for rank in tiers.keys.sorted() {
            let outputs = tiers[rank, default: []].map { destination.keyMap[$0] }
            if outputs.allSatisfy({ $0 == nil }) { continue }
            let targets = Set(outputs.compactMap { $0 })
            guard outputs.allSatisfy({ $0 != nil }), targets.count == 1, let output = targets.first else {
                throw CorrectionMappingError.ambiguousDestination
            }
            return output
        }
        throw CorrectionMappingError.ambiguousDestination
    }

    static let keypadKeyCodes: Set<UInt16> = [
        UInt16(kVK_ANSI_KeypadDecimal), UInt16(kVK_ANSI_KeypadMultiply), UInt16(kVK_ANSI_KeypadPlus),
        UInt16(kVK_ANSI_KeypadClear), UInt16(kVK_ANSI_KeypadDivide), UInt16(kVK_ANSI_KeypadEnter),
        UInt16(kVK_ANSI_KeypadMinus), UInt16(kVK_ANSI_KeypadEquals),
        UInt16(kVK_ANSI_Keypad0), UInt16(kVK_ANSI_Keypad1), UInt16(kVK_ANSI_Keypad2), UInt16(kVK_ANSI_Keypad3),
        UInt16(kVK_ANSI_Keypad4), UInt16(kVK_ANSI_Keypad5), UInt16(kVK_ANSI_Keypad6), UInt16(kVK_ANSI_Keypad7),
        UInt16(kVK_ANSI_Keypad8), UInt16(kVK_ANSI_Keypad9),
    ]

    private static func represents(_ known: String, in source: CorrectionSource) -> Bool {
        known.allSatisfy { source.keyMap.values.contains(String($0)) }
    }
}

struct CorrectionInputMetadata: Equatable, Sendable {
    /// Operation epoch changes on every context/modifier change.
    let generation: UInt64
    /// Text epoch changes only when text/caret provenance is invalidated or extended.
    let inputGeneration: UInt64
    let timestamp: UInt64
    let sourceID: String
    let targetPID: pid_t
    let keyDownCount: UInt32
    let totalUTF16Units: UInt32
    let wordUTF16Units: UInt32
    let trailingSpaces: UInt8
    let leftOptionDown: Bool
}

/// Bounded sensitive physical-key buffer. Never persist or log keys or reconstructed text.
final class CorrectionInputLedger: @unchecked Sendable {
    static let wordLifetimeNanoseconds: UInt64 = 30_000_000_000
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var inputGeneration: UInt64 = 0
    private var keyDownCount: UInt32 = 0
    private var totalUTF16Units: UInt32 = 0
    private var wordUTF16Units: UInt32 = 0
    private var trailingSpaces: UInt8 = 0
    private var leftOptionDown = false
    private var lastTimestamp: UInt64 = 0
    private var blocked = false
    private var capturedSourceID: String?
    private var capturedPID: pid_t = 0
    private var activeSourceID = ""
    private var compositionUncertain = false
    private var keys: [CorrectionPhysicalKey] = []
    private var keyExpiryScheduled = false
    private var lastWordReset: DiagnosticWordReset?
    private var lastWordResetTimestamp: UInt64 = 0

    /// Diagnostic class of the most recent event that discarded a non-empty word, and its age.
    func lastWordLoss(now: UInt64 = DispatchTime.now().uptimeNanoseconds) -> (reason: DiagnosticWordReset, ageMilliseconds: UInt64)? {
        lock.lock(); defer { lock.unlock() }
        guard let lastWordReset else { return nil }
        return (lastWordReset, now >= lastWordResetTimestamp ? (now - lastWordResetTimestamp) / 1_000_000 : 0)
    }

    /// Caller holds the lock. Records only an actual loss of buffered keys.
    private func noteWordLoss(_ reason: DiagnosticWordReset) {
        guard !keys.isEmpty else { return }
        lastWordReset = reason
        lastWordResetTimestamp = DispatchTime.now().uptimeNanoseconds
    }

    func recentKeys(now: UInt64 = DispatchTime.now().uptimeNanoseconds) -> [CorrectionPhysicalKey] {
        lock.lock(); defer { lock.unlock() }
        guard !blocked, !compositionUncertain, now >= lastTimestamp,
              now - lastTimestamp < Self.wordLifetimeNanoseconds else { keys.removeAll(); return [] }
        return keys
    }

    private func scheduleKeyExpiry(after delay: Double = 30) {
        guard !keyExpiryScheduled else { return }
        keyExpiryScheduled = true
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.lock.lock(); defer { self.lock.unlock() }
            self.keyExpiryScheduled = false
            let now = DispatchTime.now().uptimeNanoseconds
            if now >= self.lastTimestamp, now - self.lastTimestamp >= Self.wordLifetimeNanoseconds {
                self.keys.removeAll()
            } else if !self.keys.isEmpty { self.scheduleKeyExpiry(after: Double(Self.wordLifetimeNanoseconds - min(Self.wordLifetimeNanoseconds, now &- self.lastTimestamp)) / 1_000_000_000) }
        }
    }

    func setActiveSourceID(_ sourceID: String) {
        lock.lock(); defer { lock.unlock() }
        if activeSourceID != sourceID {
            noteWordLoss(.sourceChanged)
            generation &+= 1
            inputGeneration &+= 1
            clearWordMetadata(preserveCompositionUncertain: true)
        }
        activeSourceID = sourceID
    }

    func beginInputGeneration() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        return inputGeneration
    }

    /// Invalidates in-flight work when physical modifiers change without erasing
    /// the metadata for the freshly typed word or a completed cycle capsule.
    func noteModifierChange() {
        lock.lock(); defer { lock.unlock() }
        generation &+= 1
    }

    func noteKeyDown(timestamp: UInt64, sourceID: String, targetPID: pid_t,
                     expectedUTF16Units: UInt8?, isSpace: Bool, isExternal: Bool,
                     uncertainComposition: Bool = false, physicalKey: CorrectionPhysicalKey? = nil,
                     nonTextReason: DiagnosticWordReset = .nonTextKey) {
        lock.lock(); defer { lock.unlock() }
        guard isExternal else { return }
        generation &+= 1
        inputGeneration &+= 1
        keyDownCount &+= 1
        if timestamp >= lastTimestamp, timestamp - lastTimestamp >= Self.wordLifetimeNanoseconds { keys.removeAll() }
        lastTimestamp = timestamp
        // A plain Space completes/cancels the uncertain composition. Discard its
        // output and admit only the next word, never the potentially composed one.
        if isSpace, blocked || compositionUncertain {
            clearWordMetadata(preserveCompositionUncertain: false)
            return
        }
        if capturedSourceID == nil {
            capturedSourceID = sourceID
            capturedPID = targetPID
        } else if capturedSourceID != sourceID || capturedPID != targetPID {
            noteWordLoss(.targetChanged)
            keys.removeAll(); blocked = true; compositionUncertain = true
        }
        guard let expectedUTF16Units, expectedUTF16Units > 0 else {
            noteWordLoss(uncertainComposition ? .composition : nonTextReason)
            keys.removeAll(); blocked = true; compositionUncertain = compositionUncertain || uncertainComposition; return
        }
        totalUTF16Units &+= UInt32(expectedUTF16Units)
        if isSpace {
            if trailingSpaces == 8 { noteWordLoss(.wordLimit); keys.removeAll(); blocked = true }
            else { trailingSpaces += 1 }
        } else {
            if trailingSpaces > 0 { wordUTF16Units = 0; keys.removeAll() }
            wordUTF16Units &+= UInt32(expectedUTF16Units)
            trailingSpaces = 0
            if let physicalKey, !blocked {
                if keys.isEmpty { lastWordReset = nil } // a new word supersedes an older loss
                if keys.count < 256 { keys.append(physicalKey); scheduleKeyExpiry() }
                else { noteWordLoss(.wordLimit); keys.removeAll(); blocked = true }
            }
        }
    }

    func invalidate(reason: DiagnosticWordReset = .other) {
        lock.lock(); defer { lock.unlock() }
        noteWordLoss(reason)
        generation &+= 1; inputGeneration &+= 1; keys.removeAll(); blocked = true
    }

    func resetWordMetadata(reason: DiagnosticWordReset = .other) {
        lock.lock(); defer { lock.unlock() }
        noteWordLoss(reason)
        generation &+= 1; inputGeneration &+= 1
        clearWordMetadata(preserveCompositionUncertain: true)
    }

    func markCompositionUncertain(reason: DiagnosticWordReset = .composition) {
        lock.lock(); defer { lock.unlock() }
        noteWordLoss(reason)
        generation &+= 1; inputGeneration &+= 1; keys.removeAll(); blocked = true; compositionUncertain = true
    }

    func isCompositionUncertain() -> Bool {
        lock.lock(); defer { lock.unlock() }; return compositionUncertain
    }

    func setLeftOption(_ down: Bool) {
        lock.lock(); defer { lock.unlock() }
        leftOptionDown = down
    }

    func snapshot() -> CorrectionInputMetadata {
        lock.lock(); defer { lock.unlock() }
        return CorrectionInputMetadata(generation: generation, inputGeneration: inputGeneration, timestamp: lastTimestamp,
            sourceID: capturedSourceID ?? activeSourceID, targetPID: capturedPID,
            keyDownCount: keyDownCount, totalUTF16Units: totalUTF16Units,
            wordUTF16Units: wordUTF16Units,
            trailingSpaces: trailingSpaces, leftOptionDown: leftOptionDown)
    }

    func isBlocked() -> Bool { lock.lock(); defer { lock.unlock() }; return blocked }
    func reset(reason: DiagnosticWordReset = .other) {
        lock.lock(); defer { lock.unlock() }
        noteWordLoss(reason)
        generation &+= 1; inputGeneration &+= 1
        clearWordMetadata(preserveCompositionUncertain: false)
    }

    private func clearWordMetadata(preserveCompositionUncertain: Bool) {
        keys.removeAll()
        keyDownCount = 0; totalUTF16Units = 0; wordUTF16Units = 0; trailingSpaces = 0; blocked = false
        capturedSourceID = nil; capturedPID = 0
        if !preserveCompositionUncertain { compositionUncertain = false }
    }
}
