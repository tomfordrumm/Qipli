import Carbon.HIToolbox
import XCTest
@testable import Qipli

@MainActor
final class LayoutCorrectionPreferencesTests: XCTestCase {
    private func makePreferences() -> (UserDefaults, ShortcutPreferences, LayoutCorrectionPreferences) {
        let suiteName = "qipli.s037.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let shortcuts = ShortcutPreferences(defaults: defaults, storageKey: "\(suiteName).shortcuts")
        let correction = LayoutCorrectionPreferences(defaults: defaults, shortcutPreferences: shortcuts)
        return (defaults, shortcuts, correction)
    }

    func testCorrectionIsOffByDefaultAndRejectsEditingAndEscapeTriggers() {
        let (_, _, preferences) = makePreferences()
        XCTAssertFalse(preferences.settings.isEnabled)
        XCTAssertEqual(preferences.settings.trigger, .leftOption)

        let pasteAndMatchStyle = ShortcutBinding(keyCode: UInt16(kVK_ANSI_V),
            keyRepresentation: "V", modifiers: [.command, .option, .shift])
        XCTAssertThrowsError(try preferences.setTrigger(.shortcut(pasteAndMatchStyle)))

        let undo = ShortcutBinding(keyCode: UInt16(kVK_ANSI_Z),
            keyRepresentation: "Z", modifiers: [.command, .shift])
        XCTAssertThrowsError(try preferences.setTrigger(.shortcut(undo)))

        let escape = ShortcutBinding(keyCode: UInt16(kVK_Escape),
            keyRepresentation: "Esc", modifiers: [.command, .option])
        XCTAssertThrowsError(try preferences.setTrigger(.shortcut(escape)))
    }

    func testCorrectionTriggerCannotConflictWithCurrentOrDefaultQipliBindings() throws {
        let (_, shortcuts, correction) = makePreferences()
        let currentConflict = ShortcutBinding(keyCode: UInt16(kVK_ANSI_K),
            keyRepresentation: "K", modifiers: [.command, .option])
        try shortcuts.update(.history, binding: currentConflict)
        XCTAssertThrowsError(try correction.setTrigger(.shortcut(currentConflict)))
        let activeCorrection = ShortcutBinding(keyCode: UInt16(kVK_ANSI_J),
            keyRepresentation: "J", modifiers: [.control, .option])
        try correction.setTrigger(.shortcut(activeCorrection))
        let legacyConflict = shortcuts.currentSnapshot.replacing(.history, with: activeCorrection)
        XCTAssertThrowsError(try correction.validateLegacyShortcutUpdate(legacyConflict))

        let defaultConflict = ShortcutBinding(keyCode: UInt16(kVK_ANSI_Z),
            keyRepresentation: "Z", modifiers: [.command, .shift])
        XCTAssertThrowsError(try correction.setTrigger(.shortcut(defaultConflict)))
    }
}
