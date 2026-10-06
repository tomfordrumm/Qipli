import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Pure metadata-only state machine for the standalone physical left-Option gesture.
struct CorrectionTriggerGesture {
    private(set) var leftOptionHeld = false
    private var leftOptionClean = false
    private var startedNeutral = false
    private(set) var neutralArmed = true

    mutating func flagsChanged(keyCode: Int64, flags: CGEventFlags,
                               trigger: CorrectionTrigger, enabled: Bool) -> Bool {
        var shouldTrigger = false
        if keyCode == Int64(kVK_Option) {
            let down = flags.contains(.maskAlternate)
            if down, !leftOptionHeld {
                startedNeutral = neutralArmed
                leftOptionClean = neutralArmed
            }
            if !down, leftOptionHeld, leftOptionClean, startedNeutral,
               enabled, trigger == .leftOption {
                shouldTrigger = true
            }
            leftOptionHeld = down
        } else if leftOptionHeld {
            leftOptionClean = false
        }
        neutralArmed = flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty
        return shouldTrigger
    }

    mutating func keyDown() -> Bool {
        guard leftOptionHeld else { return false }
        leftOptionClean = false
        return true
    }

    mutating func keyUp() {
        if leftOptionHeld { leftOptionClean = false }
    }

    mutating func mouseDown() {
        if leftOptionHeld { leftOptionClean = false }
    }

    mutating func reset(flags: CGEventFlags) {
        leftOptionHeld = false
        leftOptionClean = false
        startedNeutral = false
        neutralArmed = flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty
    }
}
