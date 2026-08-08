import ApplicationServices
import Carbon.HIToolbox
import Foundation

/// Core Graphics adapter. Its active filter consumes only Qipli's exact untagged global hotkeys.
final class CGEventTapAdapter: GlobalInputEventAdapting, TaggedPasteCommandDispatching, TaggedCopyCommandDispatching {
    var onHotKey: ((GlobalHotKey) -> Void)?
    var onEscape: (() -> Void)?
    var onStackPaste: (() -> Void)?
    var onReactivatePrevious: (() -> Void)?
    var shouldConsumeEscape: (() -> Bool)?
    var stackPasteInterception: (() -> StackPasteInputDisposition)?
    var reactivationPreviousInterception: (() -> StackReactivationInputDisposition)?
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

    /// Platform-spike APIs for command dispatchers. They never read or log pasteboard content.
    @discardableResult
    func postTaggedCommandV() -> Bool {
        postTaggedCommand(keyCode: CGKeyCode(kVK_ANSI_V))
    }

    @discardableResult
    func postTaggedCommandC() -> Bool {
        postTaggedCommand(keyCode: CGKeyCode(kVK_ANSI_C))
    }

    private func postTaggedCommand(keyCode: CGKeyCode) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
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
        let action = consumedAction(
            type: type,
            event: event,
            stackSessionIsActive: adapter.shouldConsumeEscape?() ?? false,
            stackPasteInterception: adapter.stackPasteInterception,
            reactivationPreviousInterception: adapter.reactivationPreviousInterception
        )
        adapter.handle(type: type, event: event, action: action)
        return action == nil ? Unmanaged.passUnretained(event) : nil
    }

    private func handle(type: CGEventType, event: CGEvent, action: GlobalInputAction?) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            DispatchQueue.main.async { [weak self] in
                self?.recoverFromDisabledTap()
            }
        case .keyDown:
            recoveryPolicy.recordHealthyEvent()
            guard let action else { return }
            DispatchQueue.main.async { [weak self] in
                switch action {
                case let .hotKey(hotKey):
                    self?.onHotKey?(hotKey)
                case .cancelPasteStack:
                    self?.onEscape?()
                case .pasteStackItem:
                    self?.onStackPaste?()
                case .consumePasteStackItem:
                    break
                case .reactivatePreviousStackItem:
                    self?.onReactivatePrevious?()
                case .consumeReactivatePreviousStackItem:
                    break
                }
            }
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

    /// This is the full active-filter contract before stack traversal starts.
    static func consumedHotKey(type: CGEventType, event: CGEvent) -> GlobalHotKey? {
        guard case let .hotKey(hotKey) = consumedAction(type: type, event: event, stackSessionIsActive: false) else {
            return nil
        }
        return hotKey
    }

    /// Full active-filter contract. Ordinary Command-V is intentionally absent:
    /// it continues to reach the source application until S006.
    static func consumedAction(
        type: CGEventType,
        event: CGEvent,
        stackSessionIsActive: Bool,
        stackPasteInterception: (() -> StackPasteInputDisposition)? = nil,
        reactivationPreviousInterception: (() -> StackReactivationInputDisposition)? = nil
    ) -> GlobalInputAction? {
        guard type == .keyDown,
              !SyntheticEventMarker.isQipliSynthetic(
                  sourceUserData: event.getIntegerValueField(.eventSourceUserData)
              )
        else {
            return nil
        }

        if let hotKey = hotKey(for: event) {
            return .hotKey(hotKey)
        }

        if isExactCommandShiftZ(event) {
            switch reactivationPreviousInterception?() ?? .passThrough {
            case .passThrough:
                return nil
            case .consume:
                return .consumeReactivatePreviousStackItem
            case .consumeAndReactivate:
                return .reactivatePreviousStackItem
            }
        }

        if isExactOrdinaryCommandV(event) {
            switch stackPasteInterception?() ?? .passThrough {
            case .passThrough:
                return nil
            case .consume:
                return .consumePasteStackItem
            case .consumeAndDispatch:
                return .pasteStackItem
            }
        }

        guard stackSessionIsActive,
              event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_Escape),
              event.flags.intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand]).isEmpty
        else {
            return nil
        }
        return .cancelPasteStack
    }

    private static func isExactOrdinaryCommandV(_ event: CGEvent) -> Bool {
        let flags = event.flags
        return event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_ANSI_V)
            && flags.contains(.maskCommand)
            && flags.intersection([.maskShift, .maskControl, .maskAlternate]).isEmpty
    }

    private static func isExactCommandShiftZ(_ event: CGEvent) -> Bool {
        let flags = event.flags
        return event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_ANSI_Z)
            && flags.contains(.maskCommand)
            && flags.contains(.maskShift)
            && flags.intersection([.maskControl, .maskAlternate]).isEmpty
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
