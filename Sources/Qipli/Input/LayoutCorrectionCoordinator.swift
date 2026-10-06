import ApplicationServices
import Foundation

enum LayoutCorrectionOutcome: Equatable, Sendable {
    case completed(sourceID: String)
    case denied(String)
    case failed(String)
}

protocol CorrectionFreshWordProofProviding: AnyObject, Sendable {
    func diagnostics() -> CorrectionMonitorDiagnostics
    func invalidate()
    func refreshForTrigger(deadline: CorrectionAXDeadline)
    func proof(generation: UInt64, sourceID: String, pid: pid_t,
               lastInputTimestamp: UInt64) -> (FreshWordBaseline, FreshWordSample)?
}
extension CorrectionFreshWordProofProviding {
    func diagnostics() -> CorrectionMonitorDiagnostics { .unavailable }
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
         freshWordMonitor: CorrectionFreshWordProofProviding? = nil, selectSource: ((String) -> Bool)? = nil) {
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
                       mayRun: Bool, completion: @escaping (LayoutCorrectionOutcome) -> Void) {
        LayoutCorrectionDiagnostics.record(.trigger, ledger: ledger, monitor: freshWordMonitor?.diagnostics() ?? .unavailable)
        guard mayRun else { LayoutCorrectionDiagnostics.record(.arbitration, ledger: ledger, monitor: freshWordMonitor?.diagnostics() ?? .unavailable); invalidate(); completion(.denied("Another Qipli input action is active.")); return }
        guard operationID == nil else { LayoutCorrectionDiagnostics.record(.arbitration, ledger: ledger, monitor: freshWordMonitor?.diagnostics() ?? .unavailable); completion(.denied("A correction is already in progress.")); return }
        let eligible = sources.filter(\.isEligible).sorted { $0.id < $1.id }
        guard eligible.count >= 2, eligible.contains(where: { $0.id == currentSourceID }),
              !ledger.isCompositionUncertain() else {
            LayoutCorrectionDiagnostics.record(.sourcesOrComposition, ledger: ledger, monitor: freshWordMonitor?.diagnostics() ?? .unavailable)
            invalidate(); completion(.denied("Use at least two supported static keyboard layouts.")); return
        }
        let id = UUID(); operationID = id
        let deadline = CorrectionAXDeadline()
        let inputEpoch = ledger.snapshot().generation
        let gateEpoch = gate.snapshot()
        let prior = unexpiredCapsule()
        let adapter = self.adapter, ledger = self.ledger, monitor = freshWordMonitor, gate = self.gate
        Self.worker.async { [weak self] in
            let result = Self.perform(adapter: adapter, ledger: ledger, monitor: monitor, gate: gate,
                gateEpoch: gateEpoch, inputEpoch: inputEpoch, deadline: deadline, prior: prior,
                pid: targetPID, sources: eligible, currentSourceID: currentSourceID)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.operationID == id else { return }
                self.operationID = nil
                guard self.gate.snapshot() == gateEpoch, self.ledger.snapshot().generation == inputEpoch else {
                    LayoutCorrectionDiagnostics.record(.contextChanged, ledger: self.ledger, monitor: self.freshWordMonitor?.diagnostics() ?? .unavailable)
                    self.invalidate(); completion(.failed("The input context changed; correction stopped.")); return
                }
                switch result {
                case let .failure(outcome): self.invalidate(); completion(outcome)
                case let .success(next):
                    self.freshWordMonitor?.invalidate()
                    self.sourceCatalog?.refresh()
                    guard self.gate.snapshot() == gateEpoch,
                          self.sourceCatalog == nil || self.sourceCatalog?.currentSourceID == currentSourceID,
                          (try? deadline.check()) != nil else {
                        LayoutCorrectionDiagnostics.record(.contextChanged, ledger: self.ledger, monitor: self.freshWordMonitor?.diagnostics() ?? .unavailable)
                        self.invalidate()
                        completion(.failed("Text corrected, but the input context changed before layout switching.")); return
                    }
                    // Publish before select: its synchronous catalog refresh can recognize this own switch.
                    self.install(next)
                    let switched = self.selectSource?(next.currentSourceID) ?? self.sourceCatalog?.select(next.currentSourceID) ?? false
                    guard switched else {
                        LayoutCorrectionDiagnostics.record(.sourceSwitch, ledger: self.ledger, monitor: self.freshWordMonitor?.diagnostics() ?? .unavailable)
                        self.invalidate()
                        completion(.failed("Text corrected, but the keyboard layout could not be switched.")); return
                    }
                    guard self.gate.snapshot() == gateEpoch else {
                        LayoutCorrectionDiagnostics.record(.contextChanged, ledger: self.ledger, monitor: self.freshWordMonitor?.diagnostics() ?? .unavailable)
                        self.invalidate(); completion(.failed("The input context changed after correction.")); return
                    }
                    LayoutCorrectionDiagnostics.record(.completed, ledger: self.ledger, monitor: self.freshWordMonitor?.diagnostics() ?? .unavailable)
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
        sources: [CorrectionSource], currentSourceID: String?) -> WorkerResult {
        let isFresh: () -> Bool = {
            let now = DispatchTime.now().uptimeNanoseconds
            if let prior, now &- prior.lastUsedAt >= 5_000_000_000 || now &- prior.beganAt >= 30_000_000_000 {
                return false
            }
            return gate.snapshot() == gateEpoch && ledger.snapshot().generation == inputEpoch
                && !ledger.isCompositionUncertain()
        }
        var stage: CorrectionDiagnosticCode = .capture
        do {
            try deadline.check()
            guard isFresh() else { throw CorrectionAXError.stale }
            var target = try adapter.capture(pid: pid, deadline: deadline)
            let metadata = ledger.snapshot()
            guard isFresh() else { throw CorrectionAXError.stale }
            let range: CFRange, seed: String, expected: String, originID: String
            let keepSelected: Bool
            let beganAt: UInt64
            let ids = sources.map(\.id)
            let now = DispatchTime.now().uptimeNanoseconds
            if let prior {
                stage = .cycle
                // A changed cycle target is refused, never reinterpreted as a new operation.
                guard prior.sourceIDs == ids, prior.currentSourceID == currentSourceID,
                      prior.target.pid == pid, CFEqual(prior.target.element, target.element),
                      equal(prior.target.selection, target.selection),
                      prior.target.characterCount == target.characterCount,
                      now &- prior.lastUsedAt < 5_000_000_000,
                      now &- prior.beganAt < 30_000_000_000,
                      try adapter.read(target, range: prior.range, deadline: deadline) == prior.expectedText,
                      isFresh() else { throw CorrectionAXError.stale }
                range = prior.range; seed = prior.seedText; expected = prior.expectedText
                originID = prior.originSourceID; keepSelected = prior.keepSelected; beganAt = prior.beganAt
            } else if target.selection.length > 0 {
                stage = .selection
                guard target.selection.length <= 4096 else { throw CorrectionAXError.limit }
                range = target.selection
                seed = try adapter.read(target, range: range, deadline: deadline)
                expected = seed
                originID = try LayoutCorrectionMapper.origin(for: seed, from: sources, activeSourceID: currentSourceID).id
                keepSelected = true; beganAt = now
            } else {
                stage = .wordMetadata
                target = try adapter.capture(pid: pid, deadline: deadline)
                guard target.selection.length == 0, isFresh() else { throw CorrectionAXError.stale }
                stage = .wordBlocked
                guard !ledger.isBlocked() else { throw CorrectionAXError.stale }
                stage = .wordEmptyOrOversized
                guard metadata.wordUTF16Units > 0, metadata.wordUTF16Units <= 4096 else { throw CorrectionAXError.stale }
                stage = .wordSpaceLimit
                guard metadata.trailingSpaces <= 8 else { throw CorrectionAXError.stale }
                stage = .wordTargetMismatch
                guard metadata.targetPID == pid else { throw CorrectionAXError.stale }
                stage = .wordExpired
                guard metadata.timestamp <= now, now - metadata.timestamp < 5_000_000_000 else { throw CorrectionAXError.stale }
                stage = .wordSourceMissing
                guard sources.contains(where: { $0.id == metadata.sourceID }) else { throw CorrectionAXError.stale }
                // D-052: determine and verify the current bounded word at the
                // explicit trigger. Never depend on a pretyping AX snapshot.
                stage = .wordRange
                let spaces = Int(metadata.trailingSpaces), length = Int(metadata.wordUTF16Units)
                guard target.selection.location >= length + spaces else { throw CorrectionAXError.stale }
                range = CFRange(location: target.selection.location - length - spaces, length: length)
                let spaceRange = CFRange(location: range.location + length, length: spaces)
                stage = .trailingSpaces
                guard try adapter.read(target, range: spaceRange, deadline: deadline) == String(repeating: " ", count: spaces)
                else { throw CorrectionAXError.stale }
                // Old token prefixes and insertion in the middle of a token are excluded.
                stage = .leftBoundary
                if range.location > 0 {
                    let left = try adapter.read(target, range: CFRange(location: range.location - 1, length: 1), deadline: deadline)
                    guard left.allSatisfy(\.isWhitespace) else { throw CorrectionAXError.stale }
                }
                stage = .rightBoundary
                if target.selection.location < target.characterCount {
                    let right = try adapter.read(target, range: CFRange(location: target.selection.location, length: 1), deadline: deadline)
                    guard right.allSatisfy(\.isWhitespace) else { throw CorrectionAXError.stale }
                }
                stage = .wordRead
                seed = try adapter.read(target, range: range, deadline: deadline)
                guard !seed.contains(where: \.isWhitespace), isFresh() else { throw CorrectionAXError.stale }
                expected = seed; originID = metadata.sourceID; keepSelected = false; beganAt = now
            }
            stage = .mapping
            guard let currentIndex = sources.firstIndex(where: { $0.id == (prior?.currentSourceID ?? originID) }) else {
                throw CorrectionAXError.unsupported
            }
            let destination = sources[(currentIndex + 1) % sources.count].id
            let mapped: CorrectionMapping
            do {
                mapped = try LayoutCorrectionMapper.map(seed, from: sources, activeSourceID: originID, to: destination)
            } catch CorrectionMappingError.unchanged where prior != nil && destination == originID {
                // A complete cycle restores the original seed, which naturally maps to itself.
                mapped = CorrectionMapping(sourceID: originID, text: seed)
            }
            guard mapped.sourceID == originID, isFresh() else { throw CorrectionAXError.stale }
            stage = .replacement
            let replacement = try adapter.replace(target, range: range, expectedText: expected,
                replacement: mapped.text, keepSelected: keepSelected, deadline: deadline, isFresh: isFresh)
            guard isFresh() else { throw CorrectionAXError.stale }
            return .success(CycleCapsule(id: UUID(), target: replacement.target, range: replacement.range,
                seedText: seed, expectedText: mapped.text, originSourceID: originID,
                currentSourceID: destination, sourceIDs: ids, keepSelected: keepSelected,
                beganAt: beganAt, lastUsedAt: DispatchTime.now().uptimeNanoseconds))
        } catch let error as CorrectionMappingError {
            LayoutCorrectionDiagnostics.record(stage, ledger: ledger, monitor: monitor?.diagnostics() ?? .unavailable, error: .error(error))
            return .failure(.denied(message(error)))
        } catch let error as CorrectionAXError {
            LayoutCorrectionDiagnostics.record(stage, ledger: ledger, monitor: monitor?.diagnostics() ?? .unavailable, error: .error(error))
            return .failure(.failed(message(error)))
        } catch {
            LayoutCorrectionDiagnostics.record(stage, ledger: ledger, monitor: monitor?.diagnostics() ?? .unavailable, error: .unknownError)
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
        case CorrectionAXError.limit: "The text exceeds the supported size limit."
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
