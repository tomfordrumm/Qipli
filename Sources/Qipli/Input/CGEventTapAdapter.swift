import ApplicationServices
import Carbon.HIToolbox
import Foundation

/// Core Graphics adapter. It begins as a listen-only tap, so ordinary Command-V is never changed.
final class CGEventTapAdapter: GlobalInputEventAdapting {
    var onHotKey: ((GlobalHotKey) -> Void)?
    var onStatusChange: ((GlobalInputStatus) -> Void)?

    private var recoveryPolicy = EventTapRecoveryPolicy(maximumAttempts: 2)
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var status: GlobalInputStatus = .stopped {
        didSet { onStatusChange?(status) }
    }

    @discardableResult
    func start() -> GlobalInputStatus {
        guard tap == nil else { return status }

        let keyDownMask = CGEventMask(1) << CGEventType.keyDown.rawValue
        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: keyDownMask,
            callback: Self.eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            status = .unavailable("Qipli could not create the global input listener. Check Accessibility access and try again.")
            return status
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        tap = newTap
        runLoopSource = source
        recoveryPolicy.recordHealthyEvent()
        status = .ready
        return status
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        if let tap {
            CFMachPortInvalidate(tap)
        }
        runLoopSource = nil
        tap = nil
        recoveryPolicy.recordHealthyEvent()
        status = .stopped
    }

    /// Platform-spike API for the later paste executor. This method never reads or logs pasteboard content.
    @discardableResult
    func postTaggedCommandV() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else {
            return false
        }

        for event in [keyDown, keyUp] {
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: SyntheticEventMarker.sourceUserData)
            event.post(tap: .cghidEventTap)
        }
        return true
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let adapter = Unmanaged<CGEventTapAdapter>.fromOpaque(userInfo).takeUnretainedValue()
        adapter.handle(type: type, event: event)
        return Unmanaged.passUnretained(event)
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            DispatchQueue.main.async { [weak self] in
                self?.recoverFromDisabledTap()
            }
        case .keyDown:
            recoveryPolicy.recordHealthyEvent()
            guard let hotKey = Self.hotKey(for: event) else { return }
            DispatchQueue.main.async { [weak self] in self?.onHotKey?(hotKey) }
        default:
            break
        }
    }

    /// Pure classification seam used by adapter tests without installing a global event tap.
    static func hotKey(for event: CGEvent) -> GlobalHotKey? {
        guard !SyntheticEventMarker.isQipliSynthetic(
            sourceUserData: event.getIntegerValueField(.eventSourceUserData)
        ) else {
            return nil
        }

        let flags = event.flags
        guard flags.contains(.maskCommand), flags.contains(.maskShift),
              !flags.contains(.maskAlternate), !flags.contains(.maskControl)
        else {
            return nil
        }

        switch event.getIntegerValueField(.keyboardEventKeycode) {
        case Int64(kVK_ANSI_V):
            return .history
        case Int64(kVK_ANSI_C):
            return .pasteStack
        default:
            return nil
        }
    }

    private func recoverFromDisabledTap() {
        guard let tap else {
            status = .unavailable("Qipli’s global input listener was disabled and could not be restored.")
            return
        }
        guard recoveryPolicy.permitsRecovery() else {
            status = .unavailable("macOS repeatedly disabled Qipli’s global input listener. Open Permission Status and try again.")
            return
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        guard CGEvent.tapIsEnabled(tap: tap) else {
            DispatchQueue.main.async { [weak self] in
                self?.recoverFromDisabledTap()
            }
            return
        }
        status = .ready
    }
}
