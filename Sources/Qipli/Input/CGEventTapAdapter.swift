import ApplicationServices
import Carbon.HIToolbox
import Foundation

/// Core Graphics adapter. Its active filter consumes only Qipli's exact untagged global hotkeys.
final class CGEventTapAdapter: GlobalInputEventAdapting, TaggedPasteCommandDispatching, TaggedCopyCommandDispatching, TaggedMoveCommandDispatching {
    var onHotKey: ((GlobalHotKey) -> Void)?
    var onEscape: (() -> Void)?
    var onStackPaste: (() -> Void)?
    var onReactivatePrevious: (() -> Void)?
    var onFinderCutCommand: ((Bool) -> Void)?
    var onFinderCutMove: (() -> Void)?
    var shouldConsumeEscape: (() -> Bool)?
    var stackPasteInterception: (() -> StackPasteInputDisposition)?
    var reactivationPreviousInterception: (() -> StackReactivationInputDisposition)?
    var finderCutPasteInterception: ((Bool) -> FinderCutPasteInputDisposition)?
    var onStatusChange: ((GlobalInputStatus) -> Void)?
    var onCorrectionTrigger: (() -> Void)?
    var onCorrectionInputInvalidation: (() -> Void)?
    private let correctionSettingsLock = NSLock()
    private var correctionEnabled = false
    private var correctionTrigger: CorrectionTrigger = .leftOption
    let correctionLedger = CorrectionInputLedger()
    let correctionClassifier = CorrectionInputClassifier()
    var correctionFreshWordMonitor: CorrectionFreshWordMonitor?
    private var correctionGesture = CorrectionTriggerGesture()
    private var invalidationScheduled = false

    private var recoveryPolicy = EventTapRecoveryPolicy(maximumAttempts: 2)
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let shortcutSnapshotProvider: () -> ShortcutSnapshot
    private let historyHotKey = RegisteredHistoryHotKey()
    static let eventTapOptions: CGEventTapOptions = .defaultTap
    private(set) var status: GlobalInputStatus = .stopped {
        didSet { onStatusChange?(status) }
    }

    init(shortcutSnapshotProvider: @escaping () -> ShortcutSnapshot = { .defaults }) {
        self.shortcutSnapshotProvider = shortcutSnapshotProvider
    }

    @discardableResult
    func start() -> GlobalInputStatus {
        guard tap == nil else { return status }

        let eventMask = (CGEventMask(1) << CGEventType.keyDown.rawValue) |
            (CGEventMask(1) << CGEventType.flagsChanged.rawValue) |
            (CGEventMask(1) << CGEventType.keyUp.rawValue) |
            (CGEventMask(1) << CGEventType.leftMouseDown.rawValue) |
            (CGEventMask(1) << CGEventType.rightMouseDown.rawValue) |
            (CGEventMask(1) << CGEventType.otherMouseDown.rawValue)
        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: Self.eventTapOptions,
            eventsOfInterest: eventMask,
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
        historyHotKey.onPress = { [weak self] in self?.onHotKey?(.history) }
        historyHotKey.update(shortcutSnapshotProvider().history)
        correctionGesture.reset(flags: CGEventSource.flagsState(.combinedSessionState))
        recoveryPolicy.recordHealthyEvent()
        status = .ready
        return status
    }

    func stop() {
        historyHotKey.stop()
        correctionFreshWordMonitor?.stop()
        correctionLedger.resetWordMetadata()
        correctionLedger.markCompositionUncertain()
        correctionGesture.reset(flags: [.maskAlternate])
        scheduleCorrectionInvalidation(preserveWordBaseline: false)
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

    func refreshHistoryShortcut(_ binding: ShortcutBinding) {
        guard tap != nil else { return }
        historyHotKey.update(binding)
    }

    func updateCorrectionContext(source: CorrectionSource?, targetPID: pid_t, sourceID: String, enabled: Bool) {
        correctionClassifier.install(source: source, targetPID: targetPID)
        correctionLedger.setActiveSourceID(sourceID)
        // D-052 captures AX only on an explicit correction. No background polling.
    }

    func installCorrectionSettings(enabled: Bool, trigger: CorrectionTrigger) {
        correctionSettingsLock.lock(); defer { correctionSettingsLock.unlock() }
        correctionEnabled = enabled
        correctionTrigger = trigger
    }

    /// Platform-spike APIs for command dispatchers. They never read or log pasteboard content.
    @discardableResult
    func postTaggedCommandV() -> Bool {
        postTaggedCommand(keyCode: CGKeyCode(kVK_ANSI_V))
    }

    @discardableResult
    func postTaggedCommandC() -> Bool {
        postTaggedCommand(keyCode: CGKeyCode(kVK_ANSI_C), flags: .maskCommand)
    }

    @discardableResult
    func postTaggedCommandMove() -> Bool {
        postTaggedCommand(
            keyCode: CGKeyCode(kVK_ANSI_V),
            flags: [.maskCommand, .maskAlternate]
        )
    }

    private func postTaggedCommand(keyCode: CGKeyCode, flags: CGEventFlags = .maskCommand) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else {
            return false
        }

        for event in [keyDown, keyUp] {
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: SyntheticEventMarker.sourceUserData)
            event.post(tap: .cghidEventTap)
        }
        return true
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let adapter = Unmanaged<CGEventTapAdapter>.fromOpaque(userInfo).takeUnretainedValue()
        switch adapter.correctionShortcutEvent(type: type, event: event) {
        case .trigger:
            DispatchQueue.main.async { [weak adapter] in adapter?.onCorrectionTrigger?() }
            return nil
        case .consumeRepeat:
            return nil
        case .none:
            break
        }
        adapter.observeCorrectionEvent(type: type, event: event)
        let action = consumedAction(
            type: type,
            event: event,
            stackSessionIsActive: adapter.shouldConsumeEscape?() ?? false,
            stackPasteInterception: adapter.stackPasteInterception,
            reactivationPreviousInterception: adapter.reactivationPreviousInterception,
            finderCutPasteInterception: adapter.finderCutPasteInterception,
            shortcutSnapshot: adapter.shortcutSnapshotProvider(),
            historyHotKeyIsRegistered: adapter.historyHotKey.isRegistered
        )
        adapter.handle(type: type, event: event, action: action)
        return action?.consumesInput == true ? nil : Unmanaged.passUnretained(event)
    }

    private enum CorrectionShortcutEvent { case none, trigger, consumeRepeat }

    private func correctionShortcutEvent(type: CGEventType, event: CGEvent) -> CorrectionShortcutEvent {
        correctionSettingsLock.lock()
        let enabled = correctionEnabled
        let configuredTrigger = correctionTrigger
        correctionSettingsLock.unlock()
        guard enabled, type == .keyDown,
              !SyntheticEventMarker.isQipliSynthetic(
                sourceUserData: event.getIntegerValueField(.eventSourceUserData)
              ),
              case let .shortcut(binding) = configuredTrigger,
              binding.matches(
            keyCode: event.getIntegerValueField(.keyboardEventKeycode), flags: event.flags
              ) else { return .none }
        return event.getIntegerValueField(.keyboardEventAutorepeat) == 0 ? .trigger : .consumeRepeat
    }

    /// O(1), metadata-only event accounting. No AX, TIS, Unicode event payload, or keycode history.
    private func observeCorrectionEvent(type: CGEventType, event: CGEvent) {
        if SyntheticEventMarker.isQipliSynthetic(
            sourceUserData: event.getIntegerValueField(.eventSourceUserData)
        ) { return }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        switch type {
        case .flagsChanged:
            // The generation is also the operation epoch. A modifier transition
            // during an AX transaction makes its freshness closure fail.
            correctionLedger.noteModifierChange()
            correctionSettingsLock.lock()
            let enabled = correctionEnabled
            let trigger = correctionTrigger
            correctionSettingsLock.unlock()
            let shouldTrigger = correctionGesture.flagsChanged(
                keyCode: keyCode, flags: event.flags, trigger: trigger, enabled: enabled
            )
            correctionLedger.setLeftOption(correctionGesture.leftOptionHeld)
            if shouldTrigger {
                DispatchQueue.main.async { [weak self] in self?.onCorrectionTrigger?() }
            }
            if keyCode != Int64(kVK_Option), isCorrectionEnabledForInput {
                scheduleCorrectionInvalidation(preserveWordBaseline: true)
            }
        case .keyDown:
            if correctionGesture.keyDown() {
                if isCorrectionEnabledForInput {
                    let metadata = correctionClassifier.metadata(keyCode: keyCode, flags: event.flags)
                    if metadata.uncertain { correctionLedger.markCompositionUncertain() }
                    else { correctionLedger.resetWordMetadata() }
                    scheduleCorrectionInvalidation(preserveWordBaseline: false)
                }
                return
            }
            guard isCorrectionEnabledForInput else { return }
            if !event.flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty {
                // Modified typing, shortcuts and paste can never add fresh-word
                // units. Start a new baseline for subsequent ordinary typing.
                let metadata = correctionClassifier.metadata(keyCode: keyCode, flags: event.flags)
                if metadata.uncertain { correctionLedger.markCompositionUncertain() }
                else { correctionLedger.resetWordMetadata() }
                scheduleCorrectionInvalidation(preserveWordBaseline: false)
                return
            }
            let metadata = correctionClassifier.metadata(keyCode: keyCode, flags: event.flags)
            let timestamp = event.timestamp
            correctionLedger.noteKeyDown(timestamp: timestamp, sourceID: metadata.sourceID,
                targetPID: metadata.pid, expectedUTF16Units: metadata.units,
                isSpace: metadata.isSpace, isExternal: true,
                uncertainComposition: metadata.uncertain)
            if metadata.units == nil {
                if metadata.uncertain { correctionLedger.markCompositionUncertain() }
                else { correctionLedger.resetWordMetadata() }
                scheduleCorrectionInvalidation(preserveWordBaseline: false)
            } else {
                scheduleCorrectionInvalidation(preserveWordBaseline: true)
            }
        case .keyUp:
            correctionGesture.keyUp()
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            correctionLedger.resetWordMetadata()
            correctionLedger.markCompositionUncertain()
            correctionGesture.reset(flags: [.maskAlternate])
            scheduleCorrectionInvalidation(preserveWordBaseline: false)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            correctionGesture.mouseDown()
            guard isCorrectionEnabledForInput else { return }
            correctionLedger.resetWordMetadata()
            scheduleCorrectionInvalidation(preserveWordBaseline: false)
        default:
            break
        }
    }

    private var isCorrectionEnabledForInput: Bool {
        correctionSettingsLock.lock(); defer { correctionSettingsLock.unlock() }; return correctionEnabled
    }

    func scheduleCorrectionInvalidation(preserveWordBaseline: Bool) {
        // Clear provenance at the event that invalidates it, before returning the
        // event to the target. A queued main callback must never clear a baseline
        // established by later keyDown events. This is metadata-only, with no AX.
        if !preserveWordBaseline { correctionFreshWordMonitor?.invalidateForInputReset() }
        guard !invalidationScheduled else { return }
        invalidationScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.invalidationScheduled = false
            self.onCorrectionInputInvalidation?()
        }
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
                case .observeFinderCutCommand:
                    self?.onFinderCutCommand?(
                        event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                    )
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
                case .dispatchFinderCutMove:
                    self?.onFinderCutMove?()
                case .consumeFinderCutMove:
                    break
                }
            }
        default:
            break
        }
    }

    /// Pure classification seam used by adapter tests without installing a global event tap.
    static func hotKey(
        for event: CGEvent,
        shortcutSnapshot: ShortcutSnapshot = .defaults
    ) -> GlobalHotKey? {
        guard !SyntheticEventMarker.isQipliSynthetic(
            sourceUserData: event.getIntegerValueField(.eventSourceUserData)
        ) else {
            return nil
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if shortcutSnapshot.history.matches(keyCode: keyCode, flags: event.flags) {
            return .history
        }
        if shortcutSnapshot.pasteStack.matches(keyCode: keyCode, flags: event.flags) {
            return .pasteStack
        }
        return nil
    }

    /// This is the full active-filter contract before stack traversal starts.
    static func consumedHotKey(type: CGEventType, event: CGEvent) -> GlobalHotKey? {
        guard case let .hotKey(hotKey) = consumedAction(type: type, event: event, stackSessionIsActive: false) else {
            return nil
        }
        return hotKey
    }

    /// Full active-filter contract. Ordinary Command-V reaches Paste Stack first,
    /// then Finder Cut only while its main-actor admission gate is open.
    static func consumedAction(
        type: CGEventType,
        event: CGEvent,
        stackSessionIsActive: Bool,
        stackPasteInterception: (() -> StackPasteInputDisposition)? = nil,
        reactivationPreviousInterception: (() -> StackReactivationInputDisposition)? = nil,
        finderCutPasteInterception: ((Bool) -> FinderCutPasteInputDisposition)? = nil,
        shortcutSnapshot: ShortcutSnapshot = .defaults,
        historyHotKeyIsRegistered: Bool = false
    ) -> GlobalInputAction? {
        guard type == .keyDown,
              !SyntheticEventMarker.isQipliSynthetic(
                  sourceUserData: event.getIntegerValueField(.eventSourceUserData)
              )
        else {
            return nil
        }

        if let hotKey = hotKey(for: event, shortcutSnapshot: shortcutSnapshot) {
            // Pass History to Carbon without also scheduling an event-tap action.
            if hotKey == .history, historyHotKeyIsRegistered { return nil }
            return .hotKey(hotKey)
        }

        if shortcutSnapshot.reactivatePrevious.matches(
            keyCode: event.getIntegerValueField(.keyboardEventKeycode),
            flags: event.flags
        ) {
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
                switch finderCutPasteInterception?(
                    event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                ) ?? .passThrough {
                case .passThrough:
                    return nil
                case .consume:
                    return .consumeFinderCutMove
                case .consumeAndDispatch:
                    return .dispatchFinderCutMove
                }
            case .consume:
                return .consumePasteStackItem
            case .consumeAndDispatch:
                return .pasteStackItem
            }
        }

        if isExactFinderCutCommandX(event) {
            return .observeFinderCutCommand
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

    private static func isExactFinderCutCommandX(_ event: CGEvent) -> Bool {
        let flags = event.flags
        return event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_ANSI_X)
            && flags.contains(.maskCommand)
            && flags.intersection([.maskShift, .maskControl, .maskAlternate]).isEmpty
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
        let flags = CGEventSource.flagsState(.combinedSessionState)
        correctionGesture.reset(flags: flags)
        status = .ready
    }
}

private extension GlobalInputAction {
    var consumesInput: Bool {
        switch self {
        case .observeFinderCutCommand:
            false
        default:
            true
        }
    }
}

/// Registers only the History chord, so opening History does not depend on
/// observing the keyboard stream while another app owns Secure Event Input.
private final class RegisteredHistoryHotKey {
    var onPress: (() -> Void)?
    private var handler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var binding: ShortcutBinding?
    private static let signature: OSType = 0x51697048 // QipH
    var isRegistered: Bool { hotKey != nil }

    func update(_ binding: ShortcutBinding) {
        guard self.binding != binding || hotKey == nil else { return }
        stop()
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var identifier = EventHotKeyID()
                guard GetEventParameter(
                    event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &identifier
                ) == noErr,
                identifier.signature == RegisteredHistoryHotKey.signature,
                identifier.id == 1 else { return OSStatus(eventNotHandledErr) }
                let owner = Unmanaged<RegisteredHistoryHotKey>.fromOpaque(context).takeUnretainedValue()
                owner.onPress?()
                return noErr
            },
            1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler
        )
        guard installed == noErr else { stop(); return }
        let result = RegisterEventHotKey(
            UInt32(binding.keyCode), Self.carbonModifiers(binding.modifiers),
            EventHotKeyID(signature: Self.signature, id: 1),
            GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &hotKey
        )
        guard result == noErr else { stop(); return }
        self.binding = binding
    }

    private static func carbonModifiers(_ modifiers: ShortcutModifiers) -> UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
        binding = nil
    }

    deinit { stop() }
}
