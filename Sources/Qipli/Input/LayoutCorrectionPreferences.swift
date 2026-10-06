import Carbon.HIToolbox
import Combine
import Foundation

enum CorrectionTrigger: Codable, Equatable {
    case leftOption
    case shortcut(ShortcutBinding)
}

struct LayoutCorrectionSettings: Codable, Equatable {
    var isEnabled: Bool
    var trigger: CorrectionTrigger

    static let defaults = Self(isEnabled: false, trigger: .leftOption)
}

enum LayoutCorrectionPreferenceError: Error, Equatable, LocalizedError {
    case invalidTrigger
    case conflictingShortcut

    var errorDescription: String? {
        switch self {
        case .invalidTrigger: "Choose a supported shortcut with a primary modifier."
        case .conflictingShortcut: "That shortcut conflicts with another Qipli command."
        }
    }
}

/// Versioned, separate storage deliberately leaves legacy shortcut migration/reset unchanged.
@MainActor
final class LayoutCorrectionPreferences: ObservableObject {
    @Published private(set) var settings: LayoutCorrectionSettings
    private let defaults: UserDefaults
    private let storageKey = "qipli.layoutCorrectionPreferences"
    private let shortcutPreferences: ShortcutPreferences

    init(defaults: UserDefaults = .standard, shortcutPreferences: ShortcutPreferences) {
        self.defaults = defaults
        self.shortcutPreferences = shortcutPreferences
        if let data = defaults.data(forKey: storageKey),
           let envelope = try? PropertyListDecoder().decode(Envelope.self, from: data),
           envelope.version == 1,
           Self.valid(envelope.settings, shortcuts: shortcutPreferences.currentSnapshot) {
            settings = envelope.settings
        } else {
            settings = .defaults
        }
    }

    func setEnabled(_ enabled: Bool) { var next = settings; next.isEnabled = enabled; commit(next) }

    func setTrigger(_ trigger: CorrectionTrigger) throws {
        var next = settings; next.trigger = trigger
        guard Self.valid(next, shortcuts: shortcutPreferences.currentSnapshot) else {
            if case let .shortcut(binding) = trigger,
               !binding.modifiers.containsPrimaryModifier { throw LayoutCorrectionPreferenceError.invalidTrigger }
            throw LayoutCorrectionPreferenceError.conflictingShortcut
        }
        commit(next)
    }

    func validateLegacyShortcutUpdate(_ snapshot: ShortcutSnapshot) throws {
        guard Self.valid(settings, shortcuts: snapshot) else {
            throw LayoutCorrectionPreferenceError.conflictingShortcut
        }
    }

    private func commit(_ value: LayoutCorrectionSettings) {
        settings = value
        if let data = try? PropertyListEncoder().encode(Envelope(version: 1, settings: value)) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private struct Envelope: Codable { let version: Int; let settings: LayoutCorrectionSettings }

    private static func valid(_ value: LayoutCorrectionSettings, shortcuts: ShortcutSnapshot) -> Bool {
        guard case let .shortcut(binding) = value.trigger else { return true }
        guard binding.modifiers.containsPrimaryModifier, binding.keyCode <= 0x7F,
              !binding.keyRepresentation.isEmpty,
              binding.keyRepresentation.count <= 12,
              binding.modifiers.rawValue & ~ShortcutModifiers.allSupported.rawValue == 0,
              binding.keyRepresentation.unicodeScalars.allSatisfy({
                  !CharacterSet.controlCharacters.contains($0)
              }) else { return false }
        if binding.keyCode == UInt16(kVK_Escape) { return false }
        if binding.modifiers.contains(.command),
           [kVK_ANSI_A, kVK_ANSI_C, kVK_ANSI_F, kVK_ANSI_G, kVK_ANSI_H,
            kVK_ANSI_N, kVK_ANSI_O, kVK_ANSI_P, kVK_ANSI_Q, kVK_ANSI_R,
            kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X,
            kVK_ANSI_Z].contains(Int(binding.keyCode)) { return false }
        return ![shortcuts, .defaults].contains { snapshot in
            ShortcutCommand.allCases.contains {
                let other = snapshot.binding(for: $0)
                return other.keyCode == binding.keyCode && other.modifiers == binding.modifiers
            }
        }
    }
}
