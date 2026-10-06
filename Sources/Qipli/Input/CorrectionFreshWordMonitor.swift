import ApplicationServices
import Foundation

/// In-memory monitor status codes used by proof checks and tests.
enum CorrectionDiagnosticCode: String, Sendable {
    case ready, notStarted, unstableSample, notificationsUnavailable
    case noSample, selectedRange, sampleTooOld, inputEpochMismatch, observerEpochMismatch, sourceMissing
    case baselineContextMismatch, baselineInvalidated, caretChanged, inputReset
    case noBaseline, contextMismatch, noInputAfterBaseline, sourceMismatch, sampleBeforeInput, targetChanged
    case trigger, arbitration, sourcesOrComposition, capture, cycle, selection, wordMetadata
    case wordProof, wordDelta, wordRange, trailingSpaces, leftBoundary, rightBoundary, wordRead
    case mapping, replacement, completed, contextChanged, sourceSwitch
    case wordBlocked, wordEmptyOrOversized, wordSpaceLimit, wordTargetMismatch, wordExpired, wordSourceMissing
    case axUnavailable, axUnsupported, axStale, axLimit, axDeadline, axVerification, unknownError
    case ambiguousSource, ambiguousDestination, unsupportedCharacter, unchanged
    case observerCreationFailed, selectionNotificationUnavailable, valueNotificationUnavailable

    static func error(_ error: Error) -> Self {
        switch error {
        case CorrectionAXError.unavailable: .axUnavailable
        case CorrectionAXError.unsupported: .axUnsupported
        case CorrectionAXError.stale: .axStale
        case CorrectionAXError.limit: .axLimit
        case CorrectionAXError.deadline: .axDeadline
        case CorrectionAXError.verification: .axVerification
        case CorrectionMappingError.ambiguousSource: .ambiguousSource
        case CorrectionMappingError.ambiguousDestination: .ambiguousDestination
        case CorrectionMappingError.unsupportedCharacter: .unsupportedCharacter
        case CorrectionMappingError.unchanged: .unchanged
        default: .unknownError
        }
    }
}

struct CorrectionMonitorDiagnostics: Sendable {
    let sample: CorrectionDiagnosticCode
    let baseline: CorrectionDiagnosticCode
    let proof: CorrectionDiagnosticCode
    let hasBaseline: Bool
    let hasSample: Bool
    let notifications: Bool
    let baselineInputUnits: UInt32
    let firstInput: CorrectionDiagnosticCode
    let baselineLoss: CorrectionDiagnosticCode
    let baselineLossUnits: UInt32
    static let unavailable = Self(sample: .notStarted, baseline: .notStarted, proof: .notStarted,
                                  hasBaseline: false, hasSample: false, notifications: false, baselineInputUnits: 0, firstInput: .notStarted, baselineLoss: .notStarted, baselineLossUnits: 0)
}

enum CorrectionAXWorker {
    static let queue = DispatchQueue(label: "app.qipli.layout-correction.ax-worker", qos: .userInitiated)
}

struct FreshWordBaseline: @unchecked Sendable {
    let target: CorrectionAXTarget
    let sampledAt: UInt64
    let inputGeneration: UInt64
    let observerGeneration: UInt64
    let sourceID: String
}

struct FreshWordSample: @unchecked Sendable {
    let target: CorrectionAXTarget
    let sampledAt: UInt64
    let observerGeneration: UInt64
    let inputGeneration: UInt64
    let sourceID: String
}

/// Native editors may apply a key after the tap has already advanced its epoch.
/// A later caret update is still typed input only if count and caret advance
/// together within the exact aggregate input budget from the preinput baseline.
enum CorrectionWordProgress {
    static func preservesBaseline(_ baseline: FreshWordBaseline?, previous: CorrectionAXTarget,
                                  current: CorrectionAXTarget, metadata: CorrectionInputMetadata) -> Bool {
        guard let baseline, metadata.sourceID == baseline.sourceID,
              metadata.targetPID == current.pid, baseline.target.pid == current.pid,
              previous.pid == current.pid,
              CFEqual(baseline.target.element, current.element), CFEqual(previous.element, current.element)
        else { return false }
        let initial = baseline.target
        let previousIsInitial = previous.characterCount == initial.characterCount &&
            previous.selection.location == initial.selection.location && previous.selection.length == initial.selection.length
        // The editor may still expose the original selection before applying the first key.
        if previousIsInitial, current.characterCount == initial.characterCount,
           current.selection.location == initial.selection.location,
           current.selection.length == initial.selection.length { return true }
        guard current.selection.length == 0,
              previous.selection.length == 0 || previousIsInitial,
              previousIsInitial || current.characterCount >= previous.characterCount,
              initial.selection.length <= initial.characterCount else { return false }
        let remainingCount = initial.characterCount - initial.selection.length
        guard current.characterCount >= remainingCount else { return false }
        let delta = current.characterCount - remainingCount
        guard delta <= Int(metadata.totalUTF16Units), initial.selection.location <= Int.max - delta else { return false }
        return current.selection.location == initial.selection.location + delta
    }
}

/// Keeps only focus/selection metadata. Payload reads happen once, after an admitted trigger.
final class CorrectionFreshWordMonitor: @unchecked Sendable {
    private let queue = CorrectionAXWorker.queue
    private let adapter: LayoutCorrectionAXAdapting
    private let metadataProvider: () -> CorrectionInputMetadata
    private let lock = NSLock()
    private var baseline: FreshWordBaseline?
    private var latest: FreshWordSample?
    private var observedGeneration: UInt64 = 0
    private var observer: AXObserver?
    private var observerSource: CFRunLoopSource?
    private var callbackBox: CallbackBox?
    private var observedElement: AXUIElement?
    private var timer: DispatchSourceTimer?
    private var pid: pid_t = 0
    private var notificationsSupported = false
    private var sampleStatus: CorrectionDiagnosticCode = .notStarted
    private var baselineStatus: CorrectionDiagnosticCode = .notStarted
    private var proofStatus: CorrectionDiagnosticCode = .notStarted
    private var baselineInputUnits: UInt32 = 0
    private var firstInputStatus: CorrectionDiagnosticCode = .notStarted
    private var baselineLoss: CorrectionDiagnosticCode = .notStarted
    private var baselineLossUnits: UInt32 = 0

    func diagnostics() -> CorrectionMonitorDiagnostics {
        lock.lock(); defer { lock.unlock() }
        return CorrectionMonitorDiagnostics(sample: sampleStatus, baseline: baselineStatus, proof: proofStatus,
            hasBaseline: baseline != nil, hasSample: latest != nil, notifications: notificationsSupported,
            baselineInputUnits: baselineInputUnits, firstInput: firstInputStatus,
            baselineLoss: baselineLoss, baselineLossUnits: baselineLossUnits)
    }

    init(adapter: LayoutCorrectionAXAdapting, metadataProvider: @escaping () -> CorrectionInputMetadata) {
        self.adapter = adapter
        self.metadataProvider = metadataProvider
    }

    func start(pid: pid_t) {
        queue.async { [weak self] in
            guard let self else { return }
            if self.pid == pid, self.timer != nil { return }
            self.stopLocked()
            self.pid = pid
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(45), leeway: .milliseconds(12))
            timer.setEventHandler { [weak self] in self?.sampleMetadata(deadline: CorrectionAXDeadline(milliseconds: 150)) }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() { queue.async { [weak self] in self?.stopLocked() } }

    /// Called from the O(1) event-tap path. It copies metadata only and never runs AX.
    func beginInput(generation: UInt64, timestamp: UInt64, pid: pid_t, inputUnits: UInt32 = 0) -> FreshWordBaseline? {
        lock.lock(); defer { lock.unlock() }
        func refuse(_ reason: CorrectionDiagnosticCode) -> FreshWordBaseline? {
            if inputUnits == 0 { firstInputStatus = reason }
            baselineStatus = reason; return nil
        }
        guard notificationsSupported else { return refuse(.notificationsUnavailable) }
        guard let sample = latest, sample.target.pid == pid else { return refuse(.noSample) }
        // Ordinary typing may replace an existing selection. It is a valid
        // preinput baseline only at the start of the tracked run, never mid-run.
        guard sample.target.selection.length == 0 || inputUnits == 0 else { return refuse(.selectedRange) }
        guard sample.sampledAt <= timestamp, timestamp - sample.sampledAt <= 120_000_000
            else { return refuse(.sampleTooOld) }
        guard sample.inputGeneration == generation else { return refuse(.inputEpochMismatch) }
        guard sample.observerGeneration == observedGeneration else { return refuse(.observerEpochMismatch) }
        guard !sample.sourceID.isEmpty else { return refuse(.sourceMissing) }
        if let baseline {
            guard baseline.target.pid == pid,
                  CFEqual(baseline.target.element, sample.target.element),
                  baseline.sourceID == sample.sourceID else { return refuse(.baselineContextMismatch) }
            baselineStatus = .ready
            return baseline
        }
        let result = FreshWordBaseline(target: sample.target, sampledAt: sample.sampledAt,
            inputGeneration: generation, observerGeneration: sample.observerGeneration,
            sourceID: sample.sourceID)
        baseline = result
        baselineInputUnits = inputUnits
        if inputUnits == 0 { firstInputStatus = .ready }
        baselineStatus = .ready
        return result
    }

    func proof(generation: UInt64, sourceID: String, pid: pid_t,
               lastInputTimestamp: UInt64) -> (FreshWordBaseline, FreshWordSample)? {
        lock.lock(); defer { lock.unlock() }
        func refuse(_ reason: CorrectionDiagnosticCode) -> (FreshWordBaseline, FreshWordSample)? {
            proofStatus = reason; return nil
        }
        guard notificationsSupported else { return refuse(.notificationsUnavailable) }
        guard let baseline else { return refuse(.noBaseline) }
        guard let latest else { return refuse(.noSample) }
        guard baseline.target.pid == pid, latest.target.pid == pid else { return refuse(.contextMismatch) }
        guard baseline.inputGeneration < generation else { return refuse(.noInputAfterBaseline) }
        guard baseline.sourceID == sourceID, latest.sourceID == sourceID else { return refuse(.sourceMismatch) }
        guard latest.inputGeneration == generation else { return refuse(.inputEpochMismatch) }
        guard baseline.sampledAt < lastInputTimestamp, latest.sampledAt >= lastInputTimestamp
            else { return refuse(.sampleBeforeInput) }
        guard latest.observerGeneration == observedGeneration else { return refuse(.observerEpochMismatch) }
        guard CFEqual(baseline.target.element, latest.target.element) else { return refuse(.targetChanged) }
        guard latest.target.selection.length == 0
            else { return refuse(.selectedRange) }
        proofStatus = .ready
        return (baseline, latest)
    }

    /// Refreshes only focus/selection/count metadata on the shared serial AX worker.
    /// It can advance a proof to the trigger's modifier epoch, but cannot establish
    /// or backdate the required preinput baseline.
    func refreshForTrigger(deadline: CorrectionAXDeadline) {
        dispatchPrecondition(condition: .onQueue(queue))
        sampleMetadata(deadline: deadline)
    }

    func invalidate() { invalidate(reason: .baselineInvalidated) }

    func invalidateForInputReset() { invalidate(reason: .inputReset) }

    private func invalidate(reason: CorrectionDiagnosticCode) {
        let units = metadataProvider().totalUTF16Units
        lock.lock(); defer { lock.unlock() }
        loseBaselineLocked(reason: reason, inputUnits: units)
    }

    private func loseBaselineLocked(reason: CorrectionDiagnosticCode, inputUnits: UInt32) {
        if baseline != nil {
            baselineLoss = reason
            baselineLossUnits = inputUnits
        }
        baseline = nil
        baselineStatus = reason
    }

    private func sampleMetadata(deadline: CorrectionAXDeadline) {
        guard pid > 0 else { return }
        let requestStartedAt = DispatchTime.now().uptimeNanoseconds
        let before = metadataProvider()
        lock.lock(); let notificationStart = observedGeneration; lock.unlock()
        let target: CorrectionAXTarget
        do { target = try adapter.capture(pid: pid, deadline: deadline) }
        catch {
            let units = metadataProvider().totalUTF16Units
            lock.lock(); latest = nil; loseBaselineLocked(reason: .error(error), inputUnits: units)
            sampleStatus = .error(error); lock.unlock()
            return
        }
        let after = metadataProvider()
        lock.lock(); let notificationEnd = observedGeneration; lock.unlock()
        guard before.inputGeneration == after.inputGeneration,
              before.sourceID == after.sourceID,
              before.targetPID == after.targetPID,
              notificationStart == notificationEnd else {
            lock.lock(); sampleStatus = .unstableSample; lock.unlock(); return
        }
        lock.lock()
        let observedTargetChanged = latest.map { !CFEqual($0.target.element, target.element) } ?? false
        lock.unlock()
        if observer == nil || observedTargetChanged {
            removeObserver()
            installObserver(for: target.element, pid: pid)
        }
        lock.lock(); defer { lock.unlock() }
        guard notificationsSupported else { latest = nil; loseBaselineLocked(reason: .notificationsUnavailable, inputUnits: after.totalUTF16Units); return }
        if let previous = latest, previous.inputGeneration == after.inputGeneration,
           (!CFEqual(previous.target.element, target.element) || previous.target.pid != target.pid ||
            previous.target.selection.length != 0 || target.selection.length != 0 ||
            previous.target.selection.location != target.selection.location),
           !CorrectionWordProgress.preservesBaseline(baseline, previous: previous.target,
                                                      current: target, metadata: after) {
            loseBaselineLocked(reason: .caretChanged, inputUnits: after.totalUTF16Units)
        }
        sampleStatus = .ready
        latest = FreshWordSample(target: target, sampledAt: requestStartedAt,
            observerGeneration: observedGeneration, inputGeneration: after.inputGeneration,
            sourceID: after.sourceID)
    }

    private func installObserver(for element: AXUIElement, pid: pid_t) {
        var created: AXObserver?
        guard AXObserverCreate(pid, Self.notificationCallback, &created) == .success,
              let created else {
            lock.lock(); notificationsSupported = false; sampleStatus = .observerCreationFailed; lock.unlock()
            return
        }
        let box = CallbackBox(self)
        let context = Unmanaged.passRetained(box).toOpaque()
        let notifications = [kAXSelectedTextChangedNotification, kAXValueChangedNotification]
        var allRegistered = true
        for name in notifications {
            if AXObserverAddNotification(created, element, name as CFString, context) == .success {
                continue
            }
            lock.lock()
            sampleStatus = name == kAXSelectedTextChangedNotification
                ? .selectionNotificationUnavailable : .valueNotificationUnavailable
            lock.unlock()
            allRegistered = false
        }
        guard allRegistered else {
            for name in notifications { AXObserverRemoveNotification(created, element, name as CFString) }
            Unmanaged<CallbackBox>.fromOpaque(context).release()
            lock.lock(); notificationsSupported = false; lock.unlock()
            return
        }
        let source = AXObserverGetRunLoopSource(created)
        // AX callbacks only increment a scalar generation. Admit word mode only after arming.
        DispatchQueue.main.sync { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        observer = created
        observerSource = source
        callbackBox = box
        observedElement = element
        lock.lock(); notificationsSupported = true; lock.unlock()
    }

    private func removeObserver() {
        guard let observer else { return }
        if let observerSource {
            DispatchQueue.main.sync { CFRunLoopRemoveSource(CFRunLoopGetMain(), observerSource, .commonModes) }
        }
        if let observedElement {
            AXObserverRemoveNotification(observer, observedElement, kAXSelectedTextChangedNotification as CFString)
            AXObserverRemoveNotification(observer, observedElement, kAXValueChangedNotification as CFString)
        }
        self.observer = nil
        observerSource = nil
        observedElement = nil
        if let callbackBox {
            Unmanaged.passUnretained(callbackBox).release()
            self.callbackBox = nil
        }
        lock.lock(); notificationsSupported = false; lock.unlock()
    }

    private func stopLocked() {
        timer?.cancel(); timer = nil
        removeObserver()
        pid = 0
        lock.lock(); baseline = nil; latest = nil; observedGeneration = 0; notificationsSupported = false;
        sampleStatus = .notStarted; baselineStatus = .notStarted; proofStatus = .notStarted;
        baselineInputUnits = 0; firstInputStatus = .notStarted;
        baselineLoss = .notStarted; baselineLossUnits = 0; lock.unlock()
    }

    deinit {
        timer?.cancel()
        if let observer, let observedElement {
            for name in [kAXSelectedTextChangedNotification, kAXValueChangedNotification] {
                AXObserverRemoveNotification(observer, observedElement, name as CFString)
            }
        }
        if let observerSource {
            if Thread.isMainThread {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), observerSource, .commonModes)
            } else {
                DispatchQueue.main.sync { CFRunLoopRemoveSource(CFRunLoopGetMain(), observerSource, .commonModes) }
            }
        }
        if let callbackBox { Unmanaged.passUnretained(callbackBox).release() }
    }

    private final class CallbackBox {
        weak var owner: CorrectionFreshWordMonitor?
        init(_ owner: CorrectionFreshWordMonitor) { self.owner = owner }
    }

    private static let notificationCallback: AXObserverCallback = { _, _, _, context in
        guard let context else { return }
        let box = Unmanaged<CallbackBox>.fromOpaque(context).takeUnretainedValue()
        guard let tracker = box.owner else { return }
        tracker.lock.lock(); tracker.observedGeneration &+= 1; tracker.lock.unlock()
    }
}
