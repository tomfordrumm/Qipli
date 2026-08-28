import AppKit
import Carbon.HIToolbox
import Combine
import Foundation

enum ShortcutCommand: String, CaseIterable, Codable, Equatable {
    case history
    case pasteStack
    case reactivatePrevious

    var title: String {
        switch self {
        case .history:
            "Open history"
        case .pasteStack:
            "Open Paste Stack"
        case .reactivatePrevious:
            "Restore previous item"
        }
    }
}

struct ShortcutModifiers: OptionSet, Codable, Equatable, Hashable {
    let rawValue: UInt

    static let command = Self(rawValue: 1 << 0)
    static let control = Self(rawValue: 1 << 1)
    static let option = Self(rawValue: 1 << 2)
    static let shift = Self(rawValue: 1 << 3)
    static let allSupported: Self = [.command, .control, .option, .shift]

    init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(UInt.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    init(eventFlags: CGEventFlags) {
        var modifiers: Self = []
        if eventFlags.contains(.maskCommand) { modifiers.insert(.command) }
        if eventFlags.contains(.maskControl) { modifiers.insert(.control) }
        if eventFlags.contains(.maskAlternate) { modifiers.insert(.option) }
        if eventFlags.contains(.maskShift) { modifiers.insert(.shift) }
        self = modifiers
    }

    init(eventFlags: NSEvent.ModifierFlags) {
        var modifiers: Self = []
        let flags = eventFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        self = modifiers
    }

    var containsPrimaryModifier: Bool {
        !intersection([.command, .control, .option]).isEmpty
    }

    var displayPrefix: String {
        var result = ""
        if contains(.control) { result += "⌃" }
        if contains(.option) { result += "⌥" }
        if contains(.shift) { result += "⇧" }
        if contains(.command) { result += "⌘" }
        return result
    }
}

struct ShortcutBinding: Codable, Equatable, Hashable {
    let keyCode: UInt16
    let keyRepresentation: String
    let modifiers: ShortcutModifiers

    var displayValue: String {
        modifiers.displayPrefix + keyRepresentation
    }

    func matches(keyCode eventKeyCode: Int64, flags: CGEventFlags) -> Bool {
        Int64(keyCode) == eventKeyCode && modifiers == ShortcutModifiers(eventFlags: flags)
    }

    static func from(event: NSEvent) -> Self {
        let keyCode = event.keyCode
        return Self(
            keyCode: keyCode,
            keyRepresentation: ShortcutKeyRepresentation.resolve(
                keyCode: keyCode,
                charactersIgnoringModifiers: event.charactersIgnoringModifiers
            ),
            modifiers: ShortcutModifiers(eventFlags: event.modifierFlags)
        )
    }
}

struct ShortcutSnapshot: Codable, Equatable {
    let history: ShortcutBinding
    let pasteStack: ShortcutBinding
    let reactivatePrevious: ShortcutBinding

    static let defaults = Self(
        history: ShortcutBinding(
            keyCode: UInt16(kVK_ANSI_V),
            keyRepresentation: "V",
            modifiers: [.command, .shift]
        ),
        pasteStack: ShortcutBinding(
            keyCode: UInt16(kVK_ANSI_C),
            keyRepresentation: "C",
            modifiers: [.command, .shift]
        ),
        reactivatePrevious: ShortcutBinding(
            keyCode: UInt16(kVK_ANSI_Z),
            keyRepresentation: "Z",
            modifiers: [.command, .shift]
        )
    )

    func binding(for command: ShortcutCommand) -> ShortcutBinding {
        switch command {
        case .history:
            history
        case .pasteStack:
            pasteStack
        case .reactivatePrevious:
            reactivatePrevious
        }
    }

    func replacing(_ command: ShortcutCommand, with binding: ShortcutBinding) -> Self {
        switch command {
        case .history:
            Self(history: binding, pasteStack: pasteStack, reactivatePrevious: reactivatePrevious)
        case .pasteStack:
            Self(history: history, pasteStack: binding, reactivatePrevious: reactivatePrevious)
        case .reactivatePrevious:
            Self(history: history, pasteStack: pasteStack, reactivatePrevious: binding)
        }
    }
}

enum ShortcutValidationError: Error, Equatable, LocalizedError {
    case missingPrimaryModifier
    case invalidKey
    case duplicate
    case protectedCombination

    var errorDescription: String? {
        switch self {
        case .missingPrimaryModifier:
            "Add Command, Control, or Option to the shortcut."
        case .invalidKey:
            "Choose a key together with the shortcut modifiers."
        case .duplicate:
            "That shortcut is already assigned to another Qipli command."
        case .protectedCombination:
            "That shortcut is reserved for a standard editing command."
        }
    }
}

enum ShortcutValidator {
    private struct BindingSignature: Hashable {
        let keyCode: UInt16
        let modifiers: ShortcutModifiers
    }

    static func validate(_ snapshot: ShortcutSnapshot) throws {
        let bindings = ShortcutCommand.allCases.map(snapshot.binding(for:))
        for binding in bindings {
            guard binding.modifiers.containsPrimaryModifier else {
                throw ShortcutValidationError.missingPrimaryModifier
            }
            guard binding.modifiers.rawValue & ~ShortcutModifiers.allSupported.rawValue == 0,
                  binding.keyCode <= 0x7F,
                  !binding.keyRepresentation.isEmpty,
                  binding.keyRepresentation.count <= 12,
                  binding.keyRepresentation.unicodeScalars.allSatisfy({
                      !CharacterSet.controlCharacters.contains($0)
                  })
            else {
                throw ShortcutValidationError.invalidKey
            }
            guard !isProtected(binding) else {
                throw ShortcutValidationError.protectedCombination
            }
        }
        let signatures = bindings.map {
            BindingSignature(keyCode: $0.keyCode, modifiers: $0.modifiers)
        }
        guard Set(signatures).count == signatures.count else {
            throw ShortcutValidationError.duplicate
        }
    }

    private static func isProtected(_ binding: ShortcutBinding) -> Bool {
        guard binding.modifiers == [.command] else { return false }
        return [kVK_ANSI_A, kVK_ANSI_C, kVK_ANSI_V, kVK_ANSI_X, kVK_ANSI_Z]
            .contains(Int(binding.keyCode))
    }
}

protocol ShortcutSnapshotProviding: AnyObject {
    var currentSnapshot: ShortcutSnapshot { get }
}

final class ShortcutPreferences: ObservableObject, ShortcutSnapshotProviding {
    @Published private(set) var snapshot: ShortcutSnapshot
    @Published private(set) var recoveredDefaults: Bool

    private struct StoredEnvelope: Codable {
        let version: Int
        let snapshot: ShortcutSnapshot
    }

    private static let storageVersion = 1
    private static let defaultStorageKey = "qipli.shortcutPreferences"

    private let defaults: UserDefaults
    private let storageKey: String
    private let lock = NSLock()
    private var lockedSnapshot: ShortcutSnapshot

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = ShortcutPreferences.defaultStorageKey
    ) {
        self.defaults = defaults
        self.storageKey = storageKey

        let loaded = Self.load(defaults: defaults, storageKey: storageKey)
        snapshot = loaded.snapshot
        lockedSnapshot = loaded.snapshot
        recoveredDefaults = loaded.recoveredDefaults

        if loaded.recoveredDefaults {
            persist(loaded.snapshot)
        }
    }

    var currentSnapshot: ShortcutSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return lockedSnapshot
    }

    func update(_ command: ShortcutCommand, binding: ShortcutBinding) throws {
        let candidate = snapshot.replacing(command, with: binding)
        try ShortcutValidator.validate(candidate)
        replace(with: candidate, recoveredDefaults: false)
    }

    func resetToDefaults() {
        replace(with: .defaults, recoveredDefaults: false)
    }

    private func replace(with snapshot: ShortcutSnapshot, recoveredDefaults: Bool) {
        persist(snapshot)
        lock.lock()
        lockedSnapshot = snapshot
        lock.unlock()
        self.snapshot = snapshot
        self.recoveredDefaults = recoveredDefaults
    }

    private func persist(_ snapshot: ShortcutSnapshot) {
        let envelope = StoredEnvelope(version: Self.storageVersion, snapshot: snapshot)
        guard let data = try? PropertyListEncoder().encode(envelope) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func load(
        defaults: UserDefaults,
        storageKey: String
    ) -> (snapshot: ShortcutSnapshot, recoveredDefaults: Bool) {
        guard let data = defaults.data(forKey: storageKey) else {
            return (.defaults, false)
        }
        guard let envelope = try? PropertyListDecoder().decode(StoredEnvelope.self, from: data),
              envelope.version == storageVersion,
              (try? ShortcutValidator.validate(envelope.snapshot)) != nil
        else {
            return (.defaults, true)
        }
        return (envelope.snapshot, false)
    }
}

private enum ShortcutKeyRepresentation {
    static func resolve(keyCode: UInt16, charactersIgnoringModifiers: String?) -> String {
        switch Int(keyCode) {
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Space: return "Space"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape: return "Esc"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "Home"
        case kVK_End: return "End"
        case kVK_PageUp: return "Page Up"
        case kVK_PageDown: return "Page Down"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default:
            let value = charactersIgnoringModifiers?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased() ?? ""
            return value.isEmpty ? "Key (keyCode)" : value
        }
    }
}
