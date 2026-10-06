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
            let candidates = origin.keyMap.filter { $0.value == String(character) }
            guard !candidates.isEmpty else {
                let existsInAnySource = sorted.contains { $0.keyMap.values.contains(String(character)) }
                guard !existsInAnySource else {
                    throw CorrectionMappingError.unsupportedCharacter
                }
                return String(character)
            }
            let mappedCandidates = candidates.map { key, _ -> String? in destination.keyMap[key] }
            guard mappedCandidates.allSatisfy({ $0 != nil }) else {
                throw CorrectionMappingError.ambiguousDestination
            }
            let targets = Set(mappedCandidates.compactMap { $0 })
            guard targets.count == 1, let output = targets.first else {
                throw CorrectionMappingError.ambiguousDestination
            }
            return output
        }
        let result = mapped.joined()
        guard result != text else { throw CorrectionMappingError.unchanged }
        return CorrectionMapping(sourceID: origin.id, text: result)
    }

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

/// Fixed-size event-tap ledger. It never retains keycodes, Unicode, or event objects.
final class CorrectionInputLedger: @unchecked Sendable {
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

    func setActiveSourceID(_ sourceID: String) {
        lock.lock(); defer { lock.unlock() }
        if activeSourceID != sourceID {
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
                     uncertainComposition: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        guard isExternal else { return }
        generation &+= 1
        inputGeneration &+= 1
        keyDownCount &+= 1
        lastTimestamp = timestamp
        if capturedSourceID == nil {
            capturedSourceID = sourceID
            capturedPID = targetPID
        } else if capturedSourceID != sourceID || capturedPID != targetPID {
            blocked = true; compositionUncertain = true
        }
        guard let expectedUTF16Units, expectedUTF16Units > 0 else {
            blocked = true; compositionUncertain = compositionUncertain || uncertainComposition; return
        }
        totalUTF16Units &+= UInt32(expectedUTF16Units)
        if isSpace {
            if trailingSpaces == 8 { blocked = true }
            else { trailingSpaces += 1 }
        } else {
            if trailingSpaces > 0 { wordUTF16Units = 0 }
            wordUTF16Units &+= UInt32(expectedUTF16Units)
            trailingSpaces = 0
        }
    }

    func invalidate() {
        lock.lock(); defer { lock.unlock() }
        generation &+= 1; inputGeneration &+= 1; blocked = true
    }

    func resetWordMetadata() {
        lock.lock(); defer { lock.unlock() }
        generation &+= 1; inputGeneration &+= 1
        clearWordMetadata(preserveCompositionUncertain: true)
    }

    func markCompositionUncertain() {
        lock.lock(); defer { lock.unlock() }
        generation &+= 1; inputGeneration &+= 1; blocked = true; compositionUncertain = true
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
    func reset() {
        lock.lock(); defer { lock.unlock() }
        generation &+= 1; inputGeneration &+= 1
        clearWordMetadata(preserveCompositionUncertain: false)
    }

    private func clearWordMetadata(preserveCompositionUncertain: Bool) {
        keyDownCount = 0; totalUTF16Units = 0; wordUTF16Units = 0; trailingSpaces = 0; blocked = false
        capturedSourceID = nil; capturedPID = 0
        if !preserveCompositionUncertain { compositionUncertain = false }
    }
}
