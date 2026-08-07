import ApplicationServices
import Carbon.HIToolbox
import Foundation

/// Core Graphics adapter. Its active filter consumes only Qipli's exact untagged global hotkeys.
final class CGEventTapAdapter: GlobalInputEventAdapting, TaggedPasteCommandDispatching {
    var onHotKey: ((GlobalHotKey) -> Void)?
    var onStatusChange: ((GlobalInputStatus) -> Void)?

    private var recoveryPolicy = EventTapRecoveryPolicy(maximumAttempts: 2)
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    static let eventTapOptions: CGEventTapOptions = .defaultTap
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
            options: Self.eventTapOptions,
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
        let hotKey = consumedHotKey(type: type, event: event)
        adapter.handle(type: type, event: event, hotKey: hotKey)
        return hotKey == nil ? Unmanaged.passUnretained(event) : nil
    }

    private func handle(type: CGEventType, event: CGEvent, hotKey: GlobalHotKey?) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            DispatchQueue.main.async { [weak self] in
                self?.recoverFromDisabledTap()
            }
        case .keyDown:
            recoveryPolicy.recordHealthyEvent()
            guard let hotKey else { return }
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

    /// This is the full active-filter contract: only the two Qipli shortcuts are removed from the target app's stream.
    static func consumedHotKey(type: CGEventType, event: CGEvent) -> GlobalHotKey? {
        guard type == .keyDown else { return nil }
        return hotKey(for: event)
    }

    private func recoverFromDisabledTap() {
        guard let tap else {
            status = .unavailable("Qipli’s global input listener was disabled and could not be restored.")
            return
        }

        recoverFromDisabledTap(
            attemptRecovery: {
                CGEvent.tapEnable(tap: tap, enable: true)
                return CGEvent.tapIsEnabled(tap: tap)
            },
            scheduleRetry: { work in
                DispatchQueue.main.async(execute: work)
            }
        )
    }

    #if DEBUG
    /// Deterministic adapter seam for XCTest. It never creates, enables, or disables a real event tap.
    func simulateDisabledTapForTesting(recoverySucceeds: @escaping () -> Bool) {
        recoverFromDisabledTap(
            attemptRecovery: recoverySucceeds,
            scheduleRetry: { work in work() }
        )
    }
    #endif

    private func recoverFromDisabledTap(
        attemptRecovery: @escaping () -> Bool,
        scheduleRetry: @escaping (@escaping () -> Void) -> Void
    ) {
        guard recoveryPolicy.permitsRecovery() else {
            status = .unavailable("macOS repeatedly disabled Qipli’s global input listener. Open Permission Status and try again.")
            return
        }

        guard attemptRecovery() else {
            scheduleRetry { [weak self] in
                self?.recoverFromDisabledTap(
                    attemptRecovery: attemptRecovery,
                    scheduleRetry: scheduleRetry
                )
            }
            return
        }
        status = .ready
    }
}
