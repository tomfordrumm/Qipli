import ApplicationServices
import Foundation

enum LayoutCorrectionOutcome: Equatable, Sendable {
    case completed(sourceID: String)
    case denied(String)
    case failed(String)
}

protocol CorrectionFreshWordProofProviding: AnyObject, Sendable {
    func invalidate()
    func refreshForTrigger(deadline: CorrectionAXDeadline)
    func proof(generation: UInt64, sourceID: String, pid: pid_t,
               lastInputTimestamp: UInt64) -> (FreshWordBaseline, FreshWordSample)?
}
extension CorrectionFreshWordProofProviding {
    func refreshForTrigger(deadline: CorrectionAXDeadline) {}
}
extension CorrectionFreshWordMonitor: CorrectionFreshWordProofProviding {}

private final class CorrectionOperationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var revision: UInt64 = 0
    func snapshot() -> UInt64 { lock.lock(); defer { lock.unlock() }; return revision }
    func invalidate() { lock.lock(); revision &+= 1; lock.unlock() }
}

/// Main owns UI/cycle state; the serial worker receives immutable operation inputs.
@MainActor
final class LayoutCorrectionCoordinator {
    private struct CycleCapsule: Sendable {
        let id: UUID
        let target: CorrectionAXTarget
        let range: CFRange
        let seedText: String
        let expectedText: String
        let originSourceID: String
        let currentSourceID: String
        let sourceIDs: [String]
        let keepSelected: Bool
        let beganAt: UInt64
        let lastUsedAt: UInt64
    }
    private enum WorkerResult: Sendable {
        case success(CycleCapsule)
        case failure(LayoutCorrectionOutcome)
    }
    private static let worker = CorrectionAXWorker.queue
    private let diagnostics: LocalDiagnostics?
    private let adapter: LayoutCorrectionAXAdapting
    private let ledger: CorrectionInputLedger
    private let freshWordMonitor: CorrectionFreshWordProofProviding?
    private let gate = CorrectionOperationGate()
    private let selectSource: ((String) -> Bool)?
    private var capsule: CycleCapsule?
    private var operationID: UUID?
    private var observedSourceIDs: [String] = []
    private var observedSourceID: String?
    weak var sourceCatalog: LayoutCorrectionSourceCatalog?

    init(adapter: LayoutCorrectionAXAdapting, ledger: CorrectionInputLedger,
         freshWordMonitor: CorrectionFreshWordProofProviding? = nil, selectSource: ((String) -> Bool)? = nil,
         diagnostics: LocalDiagnostics? = nil) {
        self.diagnostics = diagnostics
        self.adapter = adapter; self.ledger = ledger; self.freshWordMonitor = freshWordMonitor
        self.selectSource = selectSource
    }

    var hasCycle: Bool { capsule != nil }
    var isOperationActive: Bool { operationID != nil }

    func invalidate() {
        gate.invalidate()
        capsule = nil
        freshWordMonitor?.invalidate()
    }

    func invalidateCyclePreservingWordBaseline() {
        gate.invalidate()
        capsule = nil
    }

    func sourceContextDidChange(sources: [CorrectionSource], currentSourceID: String?) {
        let ids = sources.filter(\.isEligible).map(\.id).sorted()
        guard ids != observedSourceIDs || currentSourceID != observedSourceID else { return }
        observedSourceIDs = ids
        observedSourceID = currentSourceID
        if let capsule, capsule.sourceIDs == ids, capsule.currentSourceID == currentSourceID { return }
        invalidate()
    }

    func handleTrigger(targetPID: pid_t, sources: [CorrectionSource], currentSourceID: String?,
                       mayRun: Bool, trigger: CorrectionTrigger? = nil, context: DiagnosticDetails? = nil, completion: @escaping (LayoutCorrectionOutcome) -> Void) {
        let diagnosticID = UUID()
        let started = DispatchTime.now().uptimeNanoseconds
        let diagnostics = self.diagnostics
        let trace = CorrectionDiagnosticTrace { stage, reason, details in
            diagnostics?.record(operation: diagnosticID, stage: stage, reason: reason,
                elapsedMilliseconds: (DispatchTime.now().uptimeNanoseconds &- started) / 1_000_000, details: details)
        }
        let triggerReason: DiagnosticReason
        switch trigger {
        case .leftOption: triggerReason = .leftOptionTrigger
        case .shortcut: triggerReason = .shortcutTrigger
        case nil: triggerReason = .started
        }
        trace(.trigger, triggerReason, context)
        guard mayRun else { trace(.admission, .inputBusy); trace(.finished, .denied); invalidate(); completion(.denied("Another Qipli input action is active.")); return }
        guard operationID == nil else { trace(.admission, .operationBusy); trace(.finished, .denied); completion(.denied("A correction is already in progress.")); return }
        let eligible = sources.filter(\.isEligible).sorted { $0.id < $1.id }
        guard eligible.count >= 2, eligible.contains(where: { $0.id == currentSourceID }),
              !ledger.isCompositionUncertain() else {
            trace(.admission, .unsupportedSources, DiagnosticDetails(sourceCount: eligible.count,
                sourceIndex: eligible.firstIndex { $0.id == currentSourceID }, compositionUncertain: ledger.isCompositionUncertain()))
            trace(.finished, .denied)
            invalidate(); completion(.denied("Use at least two supported static keyboard layouts.")); return
        }
        let id = UUID(); operationID = id
        let deadline = CorrectionAXDeadline()
        let inputEpoch = ledger.snapshot().generation
        let gateEpoch = gate.snapshot()
        let prior = unexpiredCapsule()
        let metadata = ledger.snapshot()
        let now = DispatchTime.now().uptimeNanoseconds
        trace(.admission, .passed, DiagnosticDetails(remainingMilliseconds: deadline.remainingMilliseconds,
            sourceCount: eligible.count, sourceIndex: eligible.firstIndex { $0.id == currentSourceID },
            wordUnits: metadata.wordUTF16Units, trailingSpaces: metadata.trailingSpaces,
            wordAgeMilliseconds: metadata.timestamp <= now ? (now - metadata.timestamp) / 1_000_000 : nil,
            inputGeneration: inputEpoch, gateGeneration: gateEpoch,
            blocked: ledger.isBlocked(), compositionUncertain: ledger.isCompositionUncertain()))
        let adapter = self.adapter, ledger = self.ledger, monitor = freshWordMonitor, gate = self.gate
        Self.worker.async { [weak self] in
            let result = Self.perform(adapter: adapter, ledger: ledger, monitor: monitor, gate: gate,
                gateEpoch: gateEpoch, inputEpoch: inputEpoch, deadline: deadline, prior: prior,
                pid: targetPID, sources: eligible, currentSourceID: currentSourceID, trace: trace)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.operationID == id else { trace(.finished, .cancelled); return }
                self.operationID = nil
                guard self.gate.snapshot() == gateEpoch, self.ledger.snapshot().generation == inputEpoch else {
                    trace(.finished, .contextChanged, DiagnosticDetails(
                        inputGeneration: self.ledger.snapshot().generation, gateGeneration: self.gate.snapshot()))
                    self.invalidate(); completion(.failed("The input context changed; correction stopped.")); return
                }
                switch result {
                case let .failure(outcome):
                    if case .denied = outcome { trace(.finished, .denied) }
                    else { trace(.finished, .failed) }
                    self.invalidate(); completion(outcome)
                case let .success(next):
                    self.freshWordMonitor?.invalidate()
                    self.sourceCatalog?.refresh()
                    guard self.gate.snapshot() == gateEpoch,
                          self.sourceCatalog == nil || self.sourceCatalog?.currentSourceID == currentSourceID,
                          (try? deadline.check()) != nil else {
                        trace(.layoutSwitch, .switchContextChanged, DiagnosticDetails(
                            check: .currentSource, remainingMilliseconds: deadline.remainingMilliseconds, matches: self.sourceCatalog == nil || self.sourceCatalog?.currentSourceID == currentSourceID,
                            gateGeneration: self.gate.snapshot()))
                        trace(.finished, .failed)
                        self.invalidate()
                        completion(.failed("Text corrected, but the input context changed before layout switching.")); return
                    }
                    // Publish before select: its synchronous catalog refresh can recognize this own switch.
                    self.install(next)
                    trace(.layoutSwitch, .started)
                    let switched = self.selectSource?(next.currentSourceID) ?? self.sourceCatalog?.select(next.currentSourceID, trace: trace) ?? false
                    guard switched else {
                        trace(.layoutSwitch, .switchFailed)
                        trace(.finished, .failed)
                        self.invalidate()
                        completion(.failed("Text corrected, but the keyboard layout could not be switched.")); return
                    }
                    guard self.gate.snapshot() == gateEpoch else {
                        trace(.finished, .postSwitchContextChanged)
                        self.invalidate(); completion(.failed("The input context changed after correction.")); return
                    }
                    trace(.finished, .completed)
                    completion(.completed(sourceID: next.currentSourceID))
                }
            }
        }
    }

    private func install(_ next: CycleCapsule) {
        capsule = next
        let id = next.id
        let now = DispatchTime.now().uptimeNanoseconds
        let hardRemaining = max(0, Double(30_000_000_000 - min(30_000_000_000, now &- next.beganAt)) / 1_000_000_000)
        DispatchQueue.main.asyncAfter(deadline: .now() + min(5, hardRemaining)) { [weak self] in
            guard let self, self.capsule?.id == id else { return }
            self.capsule = nil
        }
    }

    private func unexpiredCapsule() -> CycleCapsule? {
        guard let capsule else { return nil }
        let now = DispatchTime.now().uptimeNanoseconds
        guard now &- capsule.lastUsedAt < 5_000_000_000, now &- capsule.beganAt < 30_000_000_000 else {
            self.capsule = nil; return nil
        }
        return capsule
    }

    private nonisolated static func perform(adapter: LayoutCorrectionAXAdapting, ledger: CorrectionInputLedger,
        monitor: CorrectionFreshWordProofProviding?, gate: CorrectionOperationGate, gateEpoch: UInt64,
        inputEpoch: UInt64, deadline: CorrectionAXDeadline, prior: CycleCapsule?, pid: pid_t,
        sources: [CorrectionSource], currentSourceID: String?,
        trace: CorrectionDiagnosticTrace) -> WorkerResult {
        let isFresh: () -> Bool = {
            let now = DispatchTime.now().uptimeNanoseconds
            if let prior, now &- prior.lastUsedAt >= 5_000_000_000 || now &- prior.beganAt >= 30_000_000_000 {
                trace(.validation, .mismatch, DiagnosticDetails(check: .cycleAge, matches: false))
                return false
            }
            let gateMatches = gate.snapshot() == gateEpoch
            let inputMatches = ledger.snapshot().generation == inputEpoch
            let certain = !ledger.isCompositionUncertain()
            if !gateMatches { trace(.validation, .mismatch, DiagnosticDetails(check: .gateEpoch, matches: false)) }
            if !inputMatches { trace(.validation, .mismatch, DiagnosticDetails(check: .inputEpoch, matches: false)) }
            if !certain { trace(.validation, .mismatch, DiagnosticDetails(check: .compositionCertain, matches: false)) }
            return gateMatches && inputMatches && certain
        }
        adapter.setDiagnosticTrace(trace)
        defer { adapter.setDiagnosticTrace(nil) }
        var stage = DiagnosticStage.capture
        func enter(_ next: DiagnosticStage) { stage = next; trace(next, .started) }
        func require(_ condition: Bool, _ reason: DiagnosticReason) throws {
            trace(stage, condition ? .passed : reason, DiagnosticDetails(check: DiagnosticCheck(rawValue: reason.rawValue), matches: condition))
            guard condition else { throw CorrectionAXError.stale }
        }
        do {
            enter(.capture)
            try deadline.check()
            guard isFresh() else { throw CorrectionAXError.stale }
            var target = try adapter.capture(pid: pid, deadline: deadline)
            trace(.capture, .passed, DiagnosticDetails(selectionLocation: target.selection.location,
                selectionLength: target.selection.length, characterCount: target.characterCount))
            let metadata = ledger.snapshot()
            guard isFresh() else { throw CorrectionAXError.stale }
            let range: CFRange, seed: String, expected: String, originID: String
            let keepSelected: Bool
            let beganAt: UInt64
            let ids = sources.map(\.id)
            let now = DispatchTime.now().uptimeNanoseconds
            if let prior {
                enter(.cycle)
                // A changed cycle target is refused, never reinterpreted as a new operation.
                func cycleCheck(_ condition: Bool, _ check: DiagnosticCheck) throws {
                    trace(.cycle, condition ? .passed : .mismatch, DiagnosticDetails(check: check, matches: condition))
                    guard condition else { throw CorrectionAXError.stale }
                }
                try cycleCheck(prior.sourceIDs == ids, .cycleSources)
                try cycleCheck(prior.currentSourceID == currentSourceID, .cycleSource)
                try cycleCheck(prior.target.pid == pid && CFEqual(prior.target.element, target.element), .cycleTarget)
                try cycleCheck(equal(prior.target.selection, target.selection), .cycleRange)
                try cycleCheck(prior.target.characterCount == target.characterCount, .countMatches)
                try cycleCheck(now &- prior.lastUsedAt < 5_000_000_000 && now &- prior.beganAt < 30_000_000_000, .cycleAge)
                trace(.checkpoint, .started, DiagnosticDetails(step: .cycleRead))
                try cycleCheck(try adapter.read(target, range: prior.range, deadline: deadline) == prior.expectedText, .cycleText)
                guard isFresh() else { throw CorrectionAXError.stale }
                range = prior.range; seed = prior.seedText; expected = prior.expectedText
                originID = prior.originSourceID; keepSelected = prior.keepSelected; beganAt = prior.beganAt
            } else if target.selection.length > 0 {
                enter(.selection)
                guard target.selection.length <= LayoutCorrectionLimits.maximumTextUTF16Units else {
                    trace(.selection, .limit, DiagnosticDetails(expected: LayoutCorrectionLimits.maximumTextUTF16Units,
                        observed: target.selection.length)); throw CorrectionAXError.limit
                }
                range = target.selection
                trace(.checkpoint, .started, DiagnosticDetails(step: .selectedRead))
                seed = try adapter.read(target, range: range, deadline: deadline)
                expected = seed
                originID = try LayoutCorrectionMapper.origin(for: seed, from: sources, activeSourceID: currentSourceID).id
                keepSelected = true; beganAt = now
            } else {
                enter(.wordProof)
                target = try adapter.capture(pid: pid, deadline: deadline)
                try require(target.selection.length == 0, .contextChanged)
                guard isFresh() else { throw CorrectionAXError.stale }
                try require(!ledger.isBlocked(), .wordBlocked)
                try require(metadata.wordUTF16Units > 0 && metadata.wordUTF16Units <= LayoutCorrectionLimits.maximumTextUTF16Units, .wordMissing)
                try require(metadata.trailingSpaces <= 8, .trailingSpaces)
                try require(metadata.targetPID == pid, .targetChanged)
                try require(metadata.timestamp <= now && now - metadata.timestamp < 5_000_000_000, .wordExpired)
                try require(sources.contains(where: { $0.id == metadata.sourceID }), .sourceChanged)
                // D-052: determine and verify the current bounded word at the
                // explicit trigger. Never depend on a pretyping AX snapshot.
                let spaces = Int(metadata.trailingSpaces), length = Int(metadata.wordUTF16Units)
                try require(target.selection.location >= length + spaces, .caretBoundary)
                range = CFRange(location: target.selection.location - length - spaces, length: length)
                let spaceRange = CFRange(location: range.location + length, length: spaces)
                trace(.checkpoint, .started, DiagnosticDetails(step: .wordSpaceRead))
                try require(try adapter.read(target, range: spaceRange, deadline: deadline) == String(repeating: " ", count: spaces), .spaceBoundary)
                // Old token prefixes and insertion in the middle of a token are excluded.
                if range.location > 0 {
                    trace(.checkpoint, .started, DiagnosticDetails(step: .wordLeftRead))
                    let left = try adapter.read(target, range: CFRange(location: range.location - 1, length: 1), deadline: deadline)
                    try require(left.allSatisfy(\.isWhitespace), .leftBoundary)
                }
                if target.selection.location < target.characterCount {
                    trace(.checkpoint, .started, DiagnosticDetails(step: .wordRightRead))
                    let right = try adapter.read(target, range: CFRange(location: target.selection.location, length: 1), deadline: deadline)
                    try require(right.allSatisfy(\.isWhitespace), .rightBoundary)
                }
                trace(.checkpoint, .started, DiagnosticDetails(step: .wordRead))
                seed = try adapter.read(target, range: range, deadline: deadline)
                try require(!seed.contains(where: \.isWhitespace) && isFresh(), .wordBoundary)
                expected = seed; originID = metadata.sourceID; keepSelected = false; beganAt = now
            }
            guard let currentIndex = sources.firstIndex(where: { $0.id == (prior?.currentSourceID ?? originID) }) else {
                trace(.validation, .mismatch, DiagnosticDetails(check: .currentSource, matches: false))
                throw CorrectionAXError.unsupported
            }
            enter(.mapping)
            let destination = sources[(currentIndex + 1) % sources.count].id
            trace(.mapping, .started, DiagnosticDetails(sourceCount: sources.count, sourceIndex: currentIndex,
                destinationIndex: (currentIndex + 1) % sources.count))
            let mapped: CorrectionMapping
            do {
                mapped = try LayoutCorrectionMapper.map(seed, from: sources, activeSourceID: originID, to: destination)
            } catch CorrectionMappingError.unchanged where prior != nil && destination == originID {
                // A complete cycle restores the original seed, which naturally maps to itself.
                mapped = CorrectionMapping(sourceID: originID, text: seed)
            }
            guard mapped.sourceID == originID, isFresh() else {
                trace(.validation, .mismatch, DiagnosticDetails(check: .mappingSource)); throw CorrectionAXError.stale
            }
            trace(.mapping, .passed, DiagnosticDetails(expected: seed.utf16.count, observed: mapped.text.utf16.count))
            enter(.replacement)
            let replacement = try adapter.replace(target, range: range, expectedText: expected,
                replacement: mapped.text, keepSelected: keepSelected, deadline: deadline, isFresh: isFresh)
            guard isFresh() else { throw CorrectionAXError.stale }
            return .success(CycleCapsule(id: UUID(), target: replacement.target, range: replacement.range,
                seedText: seed, expectedText: mapped.text, originSourceID: originID,
                currentSourceID: destination, sourceIDs: ids, keepSelected: keepSelected,
                beganAt: beganAt, lastUsedAt: DispatchTime.now().uptimeNanoseconds))
        } catch let error as CorrectionMappingError {
            trace(stage, DiagnosticReason(mapping: error))
            return .failure(.denied(message(error)))
        } catch let error as CorrectionAXError {
            trace(stage, DiagnosticReason(ax: error))
            return .failure(.failed(message(error)))
        } catch {
            trace(stage, .unexpected)
            return .failure(.failed("Qipli could not verify the text change."))
        }
    }

    private nonisolated static func equal(_ a: CFRange, _ b: CFRange) -> Bool {
        a.location == b.location && a.length == b.length
    }
    private nonisolated static func message(_ error: Error) -> String {
        switch error {
        case CorrectionAXError.unsupported: "This app or field is not supported for correction."
        case CorrectionAXError.stale: "The input context changed; correction stopped."
        case CorrectionAXError.limit: "Select up to 12,288 characters for layout correction."
        case CorrectionAXError.deadline: "The text field did not respond in time."
        case CorrectionAXError.unavailable: "The focused text field is unavailable."
        case CorrectionMappingError.ambiguousSource: "The original keyboard layout is ambiguous."
        case CorrectionMappingError.ambiguousDestination: "The destination layout maps this text ambiguously."
        case CorrectionMappingError.unsupportedCharacter: "This text cannot be mapped safely."
        case CorrectionMappingError.unchanged: "The text already matches that keyboard layout."
        default: "Qipli could not verify the replacement."
        }
    }
}
