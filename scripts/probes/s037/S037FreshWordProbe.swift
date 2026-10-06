#if DEBUG
import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics

struct S037ManualAXSnapshot {
    let element: AXUIElement
    let identity: CFHashCode
    let pid: pid_t
    let range: CFRange
}

enum S037ManualAXWorker {
    static func readFocusedTarget() -> S037ManualAXSnapshot? {
        // Self-process AX entry points execute AppKit directly rather than
        // messaging another process. Own fixture AppKit must stay on main.
        guard Thread.isMainThread else { return DispatchQueue.main.sync { readFocusedTarget() } }
        let app = AXUIElementCreateApplication(getpid())
        _ = AXUIElementSetMessagingTimeout(app, 0.15)
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focusedValue, CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeBitCast(focusedValue, to: AXUIElement.self)
        _ = AXUIElementSetMessagingTimeout(element, 0.15)
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid == getpid(),
              readAttribute(kAXIdentifierAttribute as CFString, element) as? String == "s037.freshword.synthetic.editor",
              readAttribute(kAXRoleAttribute as CFString, element) as? String == (kAXTextAreaRole as String),
              let range = selectedRange(element) else { return nil }
        return S037ManualAXSnapshot(element: element, identity: CFHash(element), pid: pid, range: range)
    }

    static func selectBoundedSixUnitRange(_ snapshot: S037ManualAXSnapshot, range: CFRange, sourceID: String?, isCurrent: () -> Bool) -> (Bool, Int32) {
        guard Thread.isMainThread else {
            return DispatchQueue.main.sync { selectBoundedSixUnitRange(snapshot, range: range, sourceID: sourceID, isCurrent: isCurrent) }
        }
        guard range.length == 6,
              isCurrent(), NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid(),
              let fresh = readFocusedTarget(),
              CFEqual(fresh.element, snapshot.element),
              fresh.identity == snapshot.identity,
              fresh.range.location == range.location + 9,
              fresh.range.length == 0,
              sourceID != nil, currentSourceID() == sourceID,
              let parameter = rangeValue(range) else { return (false, -1) }
        var value: CFTypeRef?
        let error = AXUIElementCopyParameterizedAttributeValue(
            snapshot.element,
            kAXStringForRangeParameterizedAttribute as CFString,
            parameter,
            &value
        )
        guard error == .success, let value = value as? String,
              (value as NSString).length == 6,
              isCurrent(), NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid(),
              let selectedValue = rangeValue(range),
              AXUIElementSetAttributeValue(snapshot.element, kAXSelectedTextRangeAttribute as CFString, selectedValue) == .success,
              selectedRange(snapshot.element).map({ $0.location == range.location && $0.length == 6 }) == true else {
            return (false, error.rawValue)
        }
        return (isCurrent(), error.rawValue)
    }

    private static func readAttribute(_ name: CFString, _ element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
        return value
    }

    private static func selectedRange(_ element: AXUIElement) -> CFRange? {
        guard let value = readAttribute(kAXSelectedTextRangeAttribute as CFString, element),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cfRange, &range) else { return nil }
        return range
    }

    private static func rangeValue(_ range: CFRange) -> AXValue? {
        var mutable = range
        return AXValueCreate(.cfRange, &mutable)
    }

    private static func currentSourceID() -> String? {
        // HIToolbox asserts its main-queue ownership for TIS properties. The AX
        // worker holds no admission lock while asking main for this metadata.
        let read: () -> String? = {
            guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
                  let rawID = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
            return unsafeBitCast(rawID, to: CFString.self) as String
        }
        return Thread.isMainThread ? read() : DispatchQueue.main.sync(execute: read)
    }
}

private final class S037ManualAdmissionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var widths: [UInt16: Int] = [:]
    private var identity: CFHashCode?
    private var baselineLocation: Int?
    private var sourceID: String?
    private var lastAXSample: TimeInterval = 0
    private var foreground = false
    private var valid = false
    private var invalid = false
    private var requestedSample = false
    private var sampleInFlight = false
    private var letters = 0
    private var spaces = 0
    private var totalUnits = 0
    private var keyEvents = 0
    private var leftDown = false
    private var rightDown = false
    private var leftCancelled = false
    private var triggered = false
    private var revision: UInt64 = 0
    private var lastInputAt: TimeInterval = 0
    private var failureReason = "none"

    func configure(layoutWidths: [UInt16: Int]) {
        lock.lock(); defer { lock.unlock() }
        widths = layoutWidths
    }

    func resetAttempt() {
        lock.lock(); defer { lock.unlock() }
        revision &+= 1
        identity = nil; baselineLocation = nil; lastAXSample = 0
        valid = false; invalid = false; requestedSample = true
        letters = 0; spaces = 0; totalUnits = 0; keyEvents = 0
        leftDown = false; rightDown = false; leftCancelled = false; triggered = false
        lastInputAt = 0; failureReason = "none"
    }

    func setForeground(_ value: Bool) {
        lock.lock(); defer { lock.unlock() }
        foreground = value
        if !value {
            valid = false
            if totalUnits > 0 { invalid = true; failureReason = "foreground-lost" }
            else { baselineLocation = nil; identity = nil; lastAXSample = 0 }
        }
    }

    func requestSample() {
        lock.lock(); defer { lock.unlock() }
        requestedSample = true
    }

    func admit(at now: TimeInterval) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return foreground && valid && !invalid && lastAXSample > 0 && now - lastAXSample <= 0.20
    }

    func consume(type: CGEventType, keyCode: UInt16, flags: CGEventFlags) {
        lock.lock(); defer { lock.unlock() }
        guard valid, !invalid else { return }
        guard type != .keyUp else { return }
        revision &+= 1
        lastInputAt = ProcessInfo.processInfo.systemUptime
        if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
            if totalUnits > 0 { invalid = true }
            else { valid = false; baselineLocation = nil; identity = nil; lastAXSample = 0 }
            return
        }
        if triggered {
            if type == .keyDown || type == .flagsChanged { invalid = true }
            return
        }
        if type == .flagsChanged {
            if keyCode == UInt16(kVK_RightOption) {
                rightDown = flags.contains(.maskAlternate)
                if leftDown && rightDown { leftCancelled = true }
                return
            }
            if keyCode == UInt16(kVK_Option) {
                if flags.contains(.maskAlternate) {
                    leftDown = true
                    leftCancelled = rightDown || Self.hasChord(flags)
                } else if leftDown {
                    leftDown = false
                    triggered = !leftCancelled && !rightDown && letters == 6 && spaces == 3 && totalUnits == 9
                    if !triggered && keyEvents > 0 { invalid = true }
                }
                requestedSample = true
                return
            }
            if leftDown && Self.hasChord(flags) { leftCancelled = true }
            return
        }
        guard type == .keyDown else { return }
        if leftDown || Self.hasChord(flags) || rightDown {
            if totalUnits > 0 { invalid = true }
            else { valid = false; baselineLocation = nil; identity = nil; lastAXSample = 0 }
            return
        }
        keyEvents += 1
        if keyCode == UInt16(kVK_Space), letters == 6, spaces < 3 {
            spaces += 1
            totalUnits += 1
        } else if let width = widths[keyCode], width > 0, spaces == 0 || (letters > 0 && spaces > 0) {
            letters += width
            totalUnits += width
            if letters > 6 { invalid = true }
        } else {
            invalid = true
        }
        requestedSample = true
    }

    func sourceChanged(_ newSourceID: String?) {
        lock.lock(); defer { lock.unlock() }
        guard newSourceID != sourceID else { return }
        sourceID = newSourceID
        if totalUnits == 0 {
            baselineLocation = nil
            identity = nil
            lastAXSample = 0
            valid = false
            requestedSample = true
        } else {
            invalid = true
            valid = false
        }
    }

    func beginSample() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard requestedSample, !sampleInFlight else { return false }
        requestedSample = false
        sampleInFlight = true
        return true
    }

    var sampleRevision: UInt64 {
        lock.lock(); defer { lock.unlock() }
        return revision
    }

    func isCurrentTrigger(_ expectedRevision: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return foreground && valid && !invalid && triggered && revision == expectedRevision
    }

    func completeSample(_ snapshot: S037ManualAXSnapshot?, sourceID newSourceID: String?, revision sampleRevision: UInt64, at now: TimeInterval) -> (Bool, CFRange?) {
        lock.lock(); defer { lock.unlock() }
        sampleInFlight = false
        guard sampleRevision == revision else { requestedSample = true; return (false, nil) }
        guard foreground, let snapshot, snapshot.pid == getpid(), snapshot.range.length == 0 else {
            valid = false
            if totalUnits > 0 { invalid = true; failureReason = "focused-range-unavailable" }
            else { baselineLocation = nil; identity = nil; lastAXSample = 0; requestedSample = true }
            return (false, nil)
        }
        if sourceID != newSourceID {
            sourceID = newSourceID
            if totalUnits > 0 { invalid = true }
            else { baselineLocation = nil; identity = nil }
        }
        if let identity, identity != snapshot.identity {
            valid = false
            if totalUnits > 0 { invalid = true }
            else { self.identity = nil; baselineLocation = nil; requestedSample = true }
            return (false, nil)
        }
        if baselineLocation == nil {
            guard totalUnits == 0, snapshot.range.location == 0 else {
                invalid = true; failureReason = "pre-input-baseline-not-empty"
                return (false, nil)
            }
            identity = snapshot.identity
            baselineLocation = snapshot.range.location
        }
        guard let identity, identity == snapshot.identity, let baselineLocation, !invalid else {
            valid = false
            invalid = true
            failureReason = "identity-source-or-input-invalid"
            return (false, nil)
        }
        guard snapshot.range.location - baselineLocation == totalUnits else {
            // Event taps observe keyDown before the target applies it. An AX reply
            // may therefore lag a recent key even with an unchanged generation.
            if now - lastInputAt < 0.30 {
                lastAXSample = now
                requestedSample = true
                return (false, nil)
            }
            valid = false; invalid = true; failureReason = "caret-delta-mismatch"
            return (false, nil)
        }
        self.identity = identity
        sourceID = newSourceID
        lastAXSample = now
        valid = true
        if triggered {
            return (true, CFRange(location: snapshot.range.location - 9, length: 6))
        }
        return (false, nil)
    }

    var status: (letters: Int, spaces: Int, totalUnits: Int, keyEvents: Int, invalid: Bool, reason: String) {
        lock.lock(); defer { lock.unlock() }
        return (letters, spaces, totalUnits, keyEvents, invalid, failureReason)
    }

    private static func hasChord(_ flags: CGEventFlags) -> Bool {
        flags.contains(.maskShift) || flags.contains(.maskControl) || flags.contains(.maskCommand)
    }
}

/// DEBUG-only experiment for bounded own-window fresh-input metadata.
@MainActor
enum S037FreshWordProbe {
    private static var activeRun: Runner?

    static func run(completion: @escaping ([String]) -> Void) {
        let runner = Runner(completion: completion)
        activeRun = runner
        runner.start()
    }

    static func runManualPhysical(progress: ((String) -> Void)? = nil, completion: @escaping ([String]) -> Void) {
        let runner = Runner(completion: completion, manualPhysicalMode: true, progress: progress)
        activeRun = runner
        runner.start()
    }

    @MainActor
    private final class Runner: NSObject, NSWindowDelegate {
        nonisolated private static let eventMarker: Int64 = 0x5330_3337_4657
        private static let selectedTextLimit = 16
        private static var lastBoundedRangeAXErrorCode: Int32 = 0
        nonisolated private static let sixKeyCodes: [UInt16] = [5, 4, 11, 2, 17, 45] // G H B D T N physical positions.

        private struct KeyClass {
            let utf16Units: Int
            let isLetter: Bool
        }

        private struct CaretSample {
            let generation: UInt64
            let location: Int
            let length: Int
            let pid: pid_t
            let identity: CFHashCode
            let sourceID: String
            let sampledAt: TimeInterval
        }

        private struct Ledger {
            var generation: UInt64 = 0
            var wordUnits = 0
            var trailingSpaces = 0
            var totalUnits = 0
            var keyEvents = 0
            var firstCaret: Int?
            var latestSample: CaretSample?
            var invalid = false
            var staleSamples = 0

            mutating func record(_ key: KeyClass?, isSpace: Bool, sourceChanged: Bool) -> UInt64 {
                if totalUnits == 0 {
                    guard let baseline = latestSample,
                          baseline.generation == generation,
                          baseline.length == 0 else {
                        invalid = true
                        generation &+= 1
                        return generation
                    }
                    firstCaret = baseline.location
                }
                generation &+= 1
                guard !invalid, !sourceChanged else {
                    invalid = true
                    return generation
                }
                guard let key, key.isLetter, key.utf16Units > 0 else {
                    if isSpace, wordUnits > 0, trailingSpaces < 8 {
                        trailingSpaces += 1
                        totalUnits += 1
                    } else {
                        invalid = true
                    }
                    return generation
                }
                if trailingSpaces == 0 || wordUnits == 0 {
                    wordUnits += key.utf16Units
                    totalUnits += key.utf16Units
                } else {
                    // A word after a separator starts a new candidate.
                    wordUnits = key.utf16Units
                    trailingSpaces = 0
                    totalUnits = key.utf16Units
                    firstCaret = latestSample?.location
                }
                return generation
            }

            mutating func invalidate() {
                generation &+= 1
                invalid = true
                latestSample = nil
            }

            mutating func accept(_ sample: CaretSample) {
                guard sample.generation == generation, !invalid else {
                    staleSamples += 1
                    return
                }
                if firstCaret == nil { firstCaret = sample.location - totalUnits }
                latestSample = sample
            }
        }

        private let completion: ([String]) -> Void
        private let progress: ((String) -> Void)?
        nonisolated let manualPhysicalMode: Bool
        nonisolated let manualGate = S037ManualAdmissionGate()
        private let manualAXQueue = DispatchQueue(label: "com.qipli.s037.manual-ax", qos: .userInitiated)
        private var manualPollTimer: DispatchSourceTimer?
        private var manualSampleInFlight = false
        private var manualArmedLabelShown = false
        private var manualInstruction: NSTextField?
        private var lines: [String] = []
        private var window: NSWindow?
        private var editor: NSTextView?
        private var tap: CFMachPort?
        private var runLoopSource: CFRunLoopSource?
        private var notificationToken: NSObjectProtocol?
        private var currentSourceID: String?
        private var keyClasses: [UInt16: KeyClass] = [:]
        private var ledger = Ledger()
        private let lock = NSLock()
        private var targetAXElement: AXUIElement?
        private var targetIdentity: CFHashCode?
        private var targetPID: pid_t = 0
        private var keyIndex = 0
        private var spacesInTrace = 0
        private var traceLabel = ""
        private var finished = false

        init(completion: @escaping ([String]) -> Void, manualPhysicalMode: Bool = false, progress: ((String) -> Void)? = nil) {
            self.completion = completion
            self.manualPhysicalMode = manualPhysicalMode
            self.progress = progress
        }

        func start() {
            if manualPhysicalMode { NSApp.setActivationPolicy(.regular) }
            guard let source = Self.currentSource() else {
                finish("freshWord=SKIPPED; reason=current-source-unavailable")
                return
            }
            currentSourceID = source.id
            keyClasses = Self.buildLetterClassifier(source: source.source)
            guard manualPhysicalMode || Self.sixKeyCodes.allSatisfy({ keyClasses[$0]?.isLetter == true }) else {
                finish("freshWord=SKIPPED; reason=synthetic-physical-keys-not-letters-in-current-source")
                return
            }

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: manualPhysicalMode ? 230 : 150),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Qipli Dev — S037 fresh-word metadata probe"
            if manualPhysicalMode {
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                window.level = .floating
            }
            window.center()
            window.isReleasedWhenClosed = false

            let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 80))
            editor.string = ""
            editor.isRichText = false
            editor.allowsUndo = false
            editor.identifier = NSUserInterfaceItemIdentifier("s037.freshword.synthetic.editor")
            let instruction = NSTextField(labelWithString: manualPhysicalMode
                ? "Synthetic probe: type six letters, then three spaces, then release left Option."
                : "Synthetic probe: the harness will enter a fixed key sequence.")
            var fixtureViews: [NSView] = [instruction, editor]
            if manualPhysicalMode {
                let reset = NSButton(title: "Начать заново", target: self, action: #selector(resetManualAttempt))
                fixtureViews.append(reset)
            }
            let content = NSStackView(views: fixtureViews)
            content.orientation = .vertical
            content.alignment = .leading
            content.spacing = 10
            content.translatesAutoresizingMaskIntoConstraints = false
            let container = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: manualPhysicalMode ? 230 : 150))
            container.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
                content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
                content.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
                content.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -16)
            ])
            window.contentView = container
            window.delegate = self
            manualInstruction = instruction
            self.window = window
            self.editor = editor
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            window.makeFirstResponder(editor)

            guard installTap() else {
                finish("freshWord=SKIPPED; reason=event-tap-unavailable")
                return
            }
            installSourceObserver()
            if manualPhysicalMode {
                traceLabel = "manual"
                manualGate.configure(layoutWidths: Dictionary(uniqueKeysWithValues: keyClasses.compactMap { code, key in
                    key.isLetter ? (code, key.utf16Units) : nil
                }))
                startManualSampling()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.beginTrace(label: "word6", spaces: 0)
            }
        }

        private func installTap() -> Bool {
            let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) |
                (CGEventMask(1) << CGEventType.keyUp.rawValue) |
                (CGEventMask(1) << CGEventType.flagsChanged.rawValue) |
                (CGEventMask(1) << CGEventType.leftMouseDown.rawValue) |
                (CGEventMask(1) << CGEventType.rightMouseDown.rawValue) |
                (CGEventMask(1) << CGEventType.otherMouseDown.rawValue)
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: Self.eventTapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else { return false }
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            self.tap = tap
            runLoopSource = source
            return true
        }

        private func installSourceObserver() {
            let name = Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
            notificationToken = DistributedNotificationCenter.default().addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                DispatchQueue.main.async { @MainActor [weak self] in
                    self?.sourceChanged()
                }
            }
        }

        private func beginTrace(label: String, spaces: Int) {
            guard !finished, let window, let editor else { return }
            traceLabel = label
            spacesInTrace = spaces
            keyIndex = 0
            editor.string = ""
            editor.setSelectedRange(NSRange(location: 0, length: 0))
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            window.makeFirstResponder(editor)
            ledger = Ledger()
            guard prepareTarget() else {
                finish("\(label)=SKIPPED; reason=own-focused-editor-AX-unavailable")
                return
            }
            captureCaret(generation: 0, delayDelivery: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
                guard let self, !self.finished else { return }
                guard self.focusedTargetIsStable() else {
                    self.finish("\(label)=SKIPPED; reason=own-focused-editor-AX-unavailable")
                    return
                }
                let baseline = self.snapshotLedger().latestSample
                guard let baseline,
                      baseline.generation == 0,
                      baseline.length == 0,
                      baseline.pid == self.targetPID,
                      baseline.identity == self.targetIdentity,
                      baseline.sourceID == self.currentSourceID,
                      baseline.location == 0 else {
                    self.finish("\(label)=SKIPPED; reason=pre-input-AX-baseline-unavailable")
                    return
                }
                self.postNextLetter()
            }
        }

        private func postNextLetter() {
            guard !finished else { return }
            if keyIndex < Self.sixKeyCodes.count {
                postPhysicalKey(Self.sixKeyCodes[keyIndex])
                keyIndex += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.postNextLetter()
                }
                return
            }
            if keyIndex < Self.sixKeyCodes.count + spacesInTrace {
                postPhysicalKey(UInt16(kVK_Space))
                keyIndex += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.postNextLetter()
                }
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.verifyTrace()
            }
        }

        private func postPhysicalKey(_ keyCode: UInt16) {
            guard let source = CGEventSource(stateID: .combinedSessionState),
                  let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: false),
                  focusedTargetIsStable()
            else {
                finish("\(traceLabel)=FAIL; reason=physical-key-event-create")
                return
            }
            for event in [down, up] {
                event.setIntegerValueField(.eventSourceUserData, value: Self.eventMarker)
                event.postToPid(targetPID)
            }
        }

        private func verifyTrace() {
            guard focusedTargetIsStable(),
                  let currentSourceID,
                  !snapshotLedger().invalid,
                  let sample = snapshotLedger().latestSample,
                  sample.pid == targetPID,
                  sample.identity == targetIdentity,
                  sample.sourceID == currentSourceID,
                  sample.length == 0,
                  let start = snapshotLedger().firstCaret,
                  sample.location - start == snapshotLedger().totalUnits else {
                finish("\(traceLabel)=FAIL; reason=caret-ledger-mismatch")
                return
            }

            // This explicit probe verification point is the only place fixture
            // characters are read, via a bounded AX range.
            let wordRange = CFRange(
                location: sample.location - snapshotLedger().trailingSpaces - snapshotLedger().wordUnits,
                length: snapshotLedger().wordUnits
            )
            guard wordRange.length > 0, wordRange.length <= Self.selectedTextLimit else {
                finish("\(traceLabel)=FAIL; reason=word-range-outside-probe-bound; requestedUTF16=\(wordRange.length)")
                return
            }
            guard let text = Self.boundedText(of: targetAXElement, range: wordRange) else {
                finish("\(traceLabel)=FAIL; reason=bounded-word-range-read; axErrorCode=\(Self.lastBoundedRangeAXErrorCode); rangeLength=\(wordRange.length)")
                return
            }
            guard (text as NSString).length == wordRange.length else {
                finish("\(traceLabel)=FAIL; reason=bounded-word-range-length-mismatch; requestedUTF16=\(wordRange.length); returnedUTF16=\((text as NSString).length)")
                return
            }
            let stale = snapshotLedger().staleSamples
            append("\(traceLabel)=PASS; keyEvents=\(snapshotLedger().keyEvents); baseline=pre-input; caretDelta=\(sample.location - start); wordRangeLength=\(wordRange.length); trailingSpaces=\(snapshotLedger().trailingSpaces); staleSamplesDiscarded=\(stale); payloadRead=explicit-bounded-range-only")

            if traceLabel == "word6" {
                beginTrace(label: "word6-one-space", spaces: 1)
            } else if traceLabel == "word6-one-space" {
                beginTrace(label: "word6-three-spaces", spaces: 3)
            } else if traceLabel == "word6-three-spaces" {
                runInvalidationChecks()
            }
        }

        private func runInvalidationChecks() {
            let previousSource = currentSourceID ?? "unknown"
            lock.lock()
            ledger = Ledger()
            seedLedgerBaseline(sourceID: previousSource)
            _ = ledger.record(KeyClass(utf16Units: 1, isLetter: true), isSpace: false, sourceChanged: false)
            let staleGeneration = ledger.generation &- 1
            ledger.accept(CaretSample(
                generation: staleGeneration,
                location: 99,
                length: 0,
                pid: getpid(),
                identity: targetIdentity ?? 0,
                sourceID: previousSource,
                sampledAt: ProcessInfo.processInfo.systemUptime
            ))
            let staleDiscarded = ledger.staleSamples == 1 && ledger.latestSample?.location == 0
            ledger.invalidate()
            let generationInvalidated = ledger.invalid
            ledger = Ledger()
            seedLedgerBaseline(sourceID: previousSource)
            _ = ledger.record(KeyClass(utf16Units: 1, isLetter: true), isSpace: false, sourceChanged: false)
            _ = ledger.record(nil, isSpace: false, sourceChanged: true)
            let sourceInvalidated = ledger.invalid
            lock.unlock()

            append("staleGeneration=\(staleDiscarded ? "PASS" : "FAIL"); sourceIDChange=\(sourceInvalidated ? "PASS" : "FAIL"); generationInvalidation=\(generationInvalidated ? "PASS" : "FAIL"); sourceChange=simulatedMetadataOnly")

            // A real physical navigation event must invalidate the pending word
            // from the tap metadata before the caret is sampled again.
            lock.lock()
            ledger = Ledger()
            seedLedgerBaseline(sourceID: previousSource)
            _ = ledger.record(KeyClass(utf16Units: 1, isLetter: true), isSpace: false, sourceChanged: false)
            lock.unlock()
            postPhysicalKey(UInt16(kVK_LeftArrow))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                guard let self else { return }
                let caretInvalidated = self.snapshotLedger().invalid
                self.append("caretNavigationInvalidation=\(caretInvalidated ? "PASS" : "FAIL"); payloadRead=SKIPPED")
                self.finish("probe=finished; externalTargets=none; physicalInput=synthetic-posted-keycodes; sourceSwitch=not-performed")
            }
        }

        private func prepareTarget() -> Bool {
            guard let app = NSWorkspace.shared.frontmostApplication,
                  app.processIdentifier == getpid(),
                  let focused = Self.ownFocusedElement(),
                  Self.attribute(kAXIdentifierAttribute as CFString, from: focused) as? String == "s037.freshword.synthetic.editor",
                  Self.selectedRange(of: focused) != nil,
                  let pid = Self.pid(of: focused), pid == getpid() else { return false }
            targetAXElement = focused
            targetIdentity = CFHash(focused)
            targetPID = pid
            return currentSourceID != nil
        }

        private func focusedTargetIsStable() -> Bool {
            guard let targetAXElement,
                  let focused = Self.ownFocusedElement(),
                  CFEqual(focused, targetAXElement),
                  Self.pid(of: focused) == targetPID,
                  CFHash(focused) == targetIdentity,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID else { return false }
            return true
        }

        private func captureCaret(generation: UInt64, delayDelivery: Bool) {
            guard let targetAXElement,
                  let focused = Self.ownFocusedElement(),
                  CFEqual(focused, targetAXElement),
                  let range = Self.selectedRange(of: targetAXElement),
                  let pid = Self.pid(of: targetAXElement),
                  let currentSourceID else { return }
            let sample = CaretSample(
                generation: generation,
                location: range.location,
                length: range.length,
                pid: pid,
                identity: CFHash(targetAXElement),
                sourceID: currentSourceID,
                sampledAt: ProcessInfo.processInfo.systemUptime
            )
            let delay = delayDelivery ? 0.18 : 0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                self.lock.lock()
                self.ledger.accept(sample)
                self.lock.unlock()
            }
        }

        private func recordMetadata(type: UInt32, keyCode rawKeyCode: Int64, marker: Int64, flags rawFlags: UInt64) {
            guard let eventType = CGEventType(rawValue: type) else { return }
            let keyCode = UInt16(rawKeyCode)
            guard marker == Self.eventMarker, eventType == .keyDown else { return }
            let isSpace = keyCode == UInt16(kVK_Space)
            let key = keyClasses[keyCode]
            lock.lock()
            let generation = ledger.record(key, isSpace: isSpace, sourceChanged: false)
            ledger.keyEvents += 1
            lock.unlock()
            DispatchQueue.main.async { [weak self] in
                self?.captureCaret(generation: generation, delayDelivery: keyCode == Self.sixKeyCodes.first)
            }
        }

        private func sourceChanged() {
            let resolved = Self.currentSource()?.id
            guard resolved != currentSourceID else { return }
            currentSourceID = resolved
            if manualPhysicalMode {
                if let source = Self.currentSource() {
                    keyClasses = Self.buildLetterClassifier(source: source.source)
                    manualGate.configure(layoutWidths: Dictionary(uniqueKeysWithValues: keyClasses.compactMap { code, key in
                        key.isLetter ? (code, key.utf16Units) : nil
                    }))
                }
                manualGate.sourceChanged(resolved)
                return
            }
            lock.lock()
            ledger.invalidate()
            lock.unlock()
        }

        private func startManualSampling() {
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now(), repeating: .milliseconds(100), leeway: .milliseconds(25))
            timer.setEventHandler { [weak self] in self?.manualSamplingTick() }
            manualPollTimer = timer
            timer.resume()
        }

        private func manualSamplingTick() {
            guard !finished else { return }
            manualGate.setForeground(NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid())
            let source = Self.currentSource()
            if source?.id != currentSourceID {
                currentSourceID = source?.id
                if let source {
                    keyClasses = Self.buildLetterClassifier(source: source.source)
                    manualGate.configure(layoutWidths: Dictionary(uniqueKeysWithValues: keyClasses.compactMap { code, key in
                        key.isLetter ? (code, key.utf16Units) : nil
                    }))
                }
                manualGate.sourceChanged(source?.id)
            }
            manualGate.requestSample()
            guard !manualSampleInFlight, manualGate.beginSample() else { return }
            manualSampleInFlight = true
            let sourceID = currentSourceID
            let revision = manualGate.sampleRevision
            manualAXQueue.async { [weak self] in
                let snapshot = S037ManualAXWorker.readFocusedTarget()
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.finished else { return }
                    self.manualSampleInFlight = false
                    let (shouldVerify, range) = self.manualGate.completeSample(
                        snapshot,
                        sourceID: sourceID,
                        revision: revision,
                        at: ProcessInfo.processInfo.systemUptime
                    )
                    if !self.manualArmedLabelShown, self.manualGate.admit(at: ProcessInfo.processInfo.systemUptime) {
                        self.manualArmedLabelShown = true
                        self.manualInstruction?.stringValue = "ARMED — 6 букв, 3 пробела, левый Option. RU/EN подходят."
                        self.append("freshWordManual=ARMED; ownFocusedSyntheticField=true; preInputAXBaseline=true; sourceNotification=observed-only; charactersOrKeyCodesStored=false")
                    }
                    let state = self.manualGate.status
                    if state.invalid, state.keyEvents > 0 {
                        if self.manualArmedLabelShown {
                            self.manualArmedLabelShown = false
                            self.manualInstruction?.stringValue = "Попытка отменена. Нажмите «Начать заново»."
                            self.append("freshWordManual=INVALIDATED; reason=\(state.reason); keyEventCount=\(state.keyEvents); wordUnits=\(state.letters); spaces=\(state.spaces); payloadRead=false")
                        }
                        return
                    }
                    guard shouldVerify, let range, let snapshot else { return }
                    self.append("freshWordManual=METADATA_PASS; preInputBaseline=true; wordUnits=6; spaces=3; standaloneLeftOptionRelease=true; payloadRead=false")
                    let triggerRevision = self.manualGate.sampleRevision
                    self.manualAXQueue.async {
                        let (accepted, errorCode) = S037ManualAXWorker.selectBoundedSixUnitRange(snapshot, range: range, sourceID: sourceID) {
                            self.manualGate.isCurrentTrigger(triggerRevision)
                        }
                        DispatchQueue.main.async { [weak self] in
                            guard let self, !self.finished else { return }
                            let passed = accepted && self.manualGate.isCurrentTrigger(triggerRevision)
                            let result = self.manualGate.status
                            self.append("freshWordManual=\(passed ? "PASS" : "FAIL_CLOSED"); observedLetterUnits=\(result.letters); trailingASCIIspaces=\(result.spaces); keyEventCount=\(result.keyEvents); selectedRangeLength=\(passed ? 6 : 0); axErrorCode=\(errorCode); payloadLogged=false; charactersStored=false; leftOptionStandaloneReleaseObserved=true")
                            self.finish("manualPhysicalProbe=finished")
                        }
                    }
                }
            }
        }

        func windowWillClose(_ notification: Notification) {
            guard manualPhysicalMode, !finished else { return }
            finish("freshWordManual=CANCELLED; reason=probe-window-closed; payloadRead=false")
        }

        @objc private func resetManualAttempt() {
            guard manualPhysicalMode, !finished, let editor, let window else { return }
            // This clears only the dedicated synthetic NSTextView owned by this
            // harness; no external AXValue or captured user content is written.
            editor.string = ""
            editor.setSelectedRange(NSRange(location: 0, length: 0))
            manualGate.resetAttempt()
            manualArmedLabelShown = false
            manualInstruction?.stringValue = "Подготовка пустого synthetic поля…"
            window.makeFirstResponder(editor)
        }

        private func snapshotLedger() -> Ledger {
            lock.lock()
            defer { lock.unlock() }
            return ledger
        }

        private func seedLedgerBaseline(sourceID: String) {
            ledger.accept(CaretSample(
                generation: 0,
                location: 99,
                length: 0,
                pid: targetPID,
                identity: targetIdentity ?? 0,
                sourceID: sourceID,
                sampledAt: ProcessInfo.processInfo.systemUptime
            ))
        }

        private func append(_ line: String) {
            lines.append(line)
            progress?(line)
            print("S037 fresh-word probe: \(line)")
        }

        private func finish(_ line: String) {
            guard !finished else { return }
            finished = true
            manualGate.resetAttempt()
            append(line)
            manualPollTimer?.setEventHandler {}
            manualPollTimer?.cancel()
            manualPollTimer = nil
            if let notificationToken {
                DistributedNotificationCenter.default().removeObserver(notificationToken)
            }
            if let runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
                CFRunLoopSourceInvalidate(runLoopSource)
            }
            if let tap { CFMachPortInvalidate(tap) }
            window?.orderOut(nil)
            window = nil
            editor = nil
            completion(lines)
            S037FreshWordProbe.activeRun = nil
        }

        private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let runner = Unmanaged<Runner>.fromOpaque(userInfo).takeUnretainedValue()
            let marker = event.getIntegerValueField(.eventSourceUserData)
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let rawType = type.rawValue
            let flags = event.flags.rawValue
            if runner.manualPhysicalMode {
                guard marker == 0,
                      runner.manualGate.admit(at: ProcessInfo.processInfo.systemUptime) else {
                    return Unmanaged.passUnretained(event)
                }
                runner.manualGate.consume(
                    type: type,
                    keyCode: UInt16(clamping: keyCode),
                    flags: CGEventFlags(rawValue: flags)
                )
                return Unmanaged.passUnretained(event)
            }
            DispatchQueue.main.async { @MainActor [weak runner] in
                runner?.recordMetadata(type: rawType, keyCode: keyCode, marker: marker, flags: flags)
            }
            return Unmanaged.passUnretained(event)
        }

        private static func currentSource() -> (source: TISInputSource, id: String)? {
            guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
                  let rawID = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
            let id = unsafeBitCast(rawID, to: CFString.self) as String
            return (source, id)
        }

        private static func buildLetterClassifier(source: TISInputSource) -> [UInt16: KeyClass] {
            guard let rawData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return [:] }
            let data = unsafeBitCast(rawData, to: CFData.self) as Data
            guard data.count >= MemoryLayout<UCKeyboardLayout>.size else { return [:] }
            var result: [UInt16: KeyClass] = [:]
            data.withUnsafeBytes { bytes in
                guard let layout = bytes.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
                for keyCode in UInt16(0)...UInt16(127) {
                    var deadState: UInt32 = 0
                    var length = 0
                    var units = [UniChar](repeating: 0, count: 8)
                    let status = UCKeyTranslate(
                        layout,
                        keyCode,
                        UInt16(kUCKeyActionDown),
                        0,
                        UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysMask),
                        &deadState,
                        units.count,
                        &length,
                        &units
                    )
                    guard status == noErr, length > 0 else { continue }
                    let output = String(decoding: units.prefix(length), as: UTF16.self)
                    let letter = output.unicodeScalars.allSatisfy { CharacterSet.letters.contains($0) }
                    if letter {
                        result[keyCode] = KeyClass(utf16Units: (output as NSString).length, isLetter: true)
                    }
                    // The output string is intentionally discarded here. Only class and
                    // UTF-16 width survive in the cached metadata classifier.
                }
            }
            return result
        }

        private static func ownFocusedElement() -> AXUIElement? {
            let app = AXUIElementCreateApplication(getpid())
            _ = AXUIElementSetMessagingTimeout(app, 0.15)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value) == .success,
                  let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            let element = unsafeBitCast(value, to: AXUIElement.self)
            guard pid(of: element) == getpid() else { return nil }
            _ = AXUIElementSetMessagingTimeout(element, 0.15)
            return element
        }

        private static func pid(of element: AXUIElement) -> pid_t? {
            var value: pid_t = 0
            guard AXUIElementGetPid(element, &value) == .success else { return nil }
            return value
        }

        private static func selectedRange(of element: AXUIElement) -> CFRange? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
                  let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
            var range = CFRange(location: 0, length: 0)
            guard AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cfRange, &range) else { return nil }
            return range
        }

        private static func rangeValue(_ range: CFRange) -> AXValue? {
            var mutableRange = range
            return AXValueCreate(.cfRange, &mutableRange)
        }

        private static func attribute(_ name: CFString, from element: AXUIElement) -> CFTypeRef? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
            return value
        }

        private static func boundedText(of element: AXUIElement?, range: CFRange) -> String? {
            lastBoundedRangeAXErrorCode = -1
            guard let element else { return nil }
            var mutableRange = range
            guard let parameter = AXValueCreate(.cfRange, &mutableRange) else { return nil }
            var value: CFTypeRef?
            let error = AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXStringForRangeParameterizedAttribute as CFString,
                parameter,
                &value
            )
            lastBoundedRangeAXErrorCode = error.rawValue
            guard error == .success else { return nil }
            return value as? String
        }
    }
}
#endif
