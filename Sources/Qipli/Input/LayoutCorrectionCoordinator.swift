import Foundation

enum LayoutCorrectionOutcome: Equatable, Sendable {
    /// Native dispatch completed and the input source was confirmed. No AX text postcondition.
    case completed(sourceID: String)
    case denied(String)
    case failed(String)
}

@MainActor
final class LayoutCorrectionCoordinator {
    private struct Cycle {
        let pid: pid_t
        let seed: String
        let keys: [CorrectionPhysicalKey]?
        let origin: String
        let sourceIDs: [String]
        let began: UInt64
        var current: String
        var inserted: String
        var lastUsed: UInt64
    }
    private let transport: LayoutCorrectionTransport
    private let ledger: CorrectionInputLedger
    private let diagnostics: LocalDiagnostics?
    private let selectSource: ((String) -> Bool)?
    private var cycle: Cycle?
    private var generation: UInt64 = 0
    private var operationID: UUID?
    private var observedIDs: [String] = []
    private var observedSource: String?
    weak var sourceCatalog: LayoutCorrectionSourceCatalog?

    init(transport: LayoutCorrectionTransport, ledger: CorrectionInputLedger,
         selectSource: ((String) -> Bool)? = nil, diagnostics: LocalDiagnostics? = nil) {
        self.transport = transport; self.ledger = ledger; self.selectSource = selectSource; self.diagnostics = diagnostics
    }
    var hasCycle: Bool { cycle != nil }
    var isOperationActive: Bool { operationID != nil }
    func invalidate() { generation &+= 1; cycle = nil; ledger.reset() }
    func invalidateCyclePreservingWordBaseline() { generation &+= 1; cycle = nil }
    func sourceContextDidChange(sources: [CorrectionSource], currentSourceID: String?) {
        let ids = sources.filter(\.isEligible).map(\.id).sorted()
        guard ids != observedIDs || currentSourceID != observedSource else { return }
        observedIDs = ids; observedSource = currentSourceID
        if let cycle, cycle.sourceIDs == ids, cycle.current == currentSourceID { return }
        invalidate()
    }

    func handleTrigger(targetPID: pid_t, sources: [CorrectionSource], currentSourceID: String?, mayRun: Bool,
                       trigger: CorrectionTrigger? = nil, context: DiagnosticDetails? = nil,
                       completion: @escaping (LayoutCorrectionOutcome) -> Void) {
        let id = UUID(), began = DispatchTime.now().uptimeNanoseconds
        let logger = diagnostics
        let trace = CorrectionDiagnosticTrace { stage, reason, details in
            logger?.record(operation: id, stage: stage, reason: reason,
                elapsedMilliseconds: (DispatchTime.now().uptimeNanoseconds &- began) / 1_000_000, details: details)
        }
        trace(.trigger, trigger == .leftOption ? .leftOptionTrigger : .shortcutTrigger, context)
        guard mayRun, operationID == nil else {
            trace(.finished, .inputBusy); completion(.denied("Another Qipli input action is active.")); return
        }
        let eligible = sources.filter(\.isEligible).sorted { $0.id < $1.id }
        guard eligible.count >= 2, let current = currentSourceID, eligible.contains(where: { $0.id == current }) else {
            trace(.finished, .unsupportedSources); completion(.denied("Use at least two supported static keyboard layouts.")); return
        }
        operationID = id
        let epoch = ledger.snapshot().generation, revision = generation
        let fresh = { [weak self] in
            guard let self else { return false }
            return self.generation == revision && self.ledger.snapshot().generation == epoch
        }
        Task { [self] in
            transport.setTrace(trace)
            defer { transport.finish(); operationID = nil }
            do {
                trace(.admission, .started)
                let selectionEmpty = try await transport.prepare(pid: targetPID)
                guard fresh() else { throw CorrectionAXError.stale }
                trace(.admission, .passed)
                let now = DispatchTime.now().uptimeNanoseconds
                var next: Cycle
                let continuing: Bool
                if let prior = cycle, prior.pid == targetPID, prior.current == current,
                   prior.sourceIDs == eligible.map(\.id), now &- prior.lastUsed < 5_000_000_000,
                   now &- prior.began < 30_000_000_000 {
                    next = prior
                    continuing = true
                    trace(.cycle, .started)
                } else {
                    continuing = false
                    let copied: String?
                    if selectionEmpty == true { copied = nil }
                    else { copied = try await transport.copySelection(pid: targetPID, isFresh: fresh) }
                    guard fresh() else { throw CorrectionAXError.stale }
                    if let copied {
                        trace(.selection, .passed)
                        let origin = try LayoutCorrectionMapper.origin(for: copied, from: eligible, activeSourceID: current)
                        next = Cycle(pid: targetPID, seed: copied, keys: nil, origin: origin.id,
                            sourceIDs: eligible.map(\.id), began: now, current: origin.id, inserted: copied, lastUsed: now)
                    } else {
                        trace(.wordProof, .started)
                        let metadata = ledger.snapshot(), keys = ledger.recentKeys()
                        guard !keys.isEmpty, metadata.targetPID == targetPID, metadata.sourceID == current,
                              let source = eligible.first(where: { $0.id == current }) else {
                            trace(.wordProof, .wordMissing); throw CorrectionAXError.unavailable
                        }
                        let seed = try Self.render(keys, source: source) + String(repeating: " ", count: Int(metadata.trailingSpaces))
                        next = Cycle(pid: targetPID, seed: seed, keys: keys, origin: current,
                            sourceIDs: eligible.map(\.id), began: now, current: current, inserted: seed, lastUsed: now)
                    }
                    cycle = nil
                }
                guard fresh(), let index = next.sourceIDs.firstIndex(of: next.current) else { throw CorrectionAXError.stale }
                let destination = eligible[(index + 1) % eligible.count]
                let mapped: String
                if let keys = next.keys {
                    let spaces = String(next.seed.reversed().prefix(while: { $0 == " " }).reversed())
                    mapped = try Self.render(keys, source: destination) + spaces
                } else if destination.id == next.origin { mapped = next.seed }
                else { mapped = try LayoutCorrectionMapper.map(next.seed, from: eligible,
                    activeSourceID: next.origin, to: destination.id).text }
                guard mapped != next.inserted else { throw CorrectionMappingError.unchanged }
                trace(.mapping, .passed)
                trace(.replacement, .started)
                // A fresh selection is already selected. A cycle/word replaces the immediately preceding insertion.
                if next.keys == nil, !continuing {
                    try await transport.pasteSelection(mapped, pid: targetPID, isFresh: fresh)
                } else {
                    try await transport.replay(deleteCount: next.inserted.count, text: mapped, pid: targetPID, isFresh: fresh)
                }
                guard fresh() else { throw CorrectionAXError.stale }
                next.current = destination.id; next.inserted = mapped; next.lastUsed = DispatchTime.now().uptimeNanoseconds
                cycle = next // recognize our own synchronous source-change callback
                trace(.layoutSwitch, .started)
                let switched = selectSource?(destination.id) ?? sourceCatalog?.select(destination.id, trace: trace) ?? false
                guard switched else {
                    invalidate(); trace(.finished, .switchFailed)
                    completion(.failed("Text input was sent, but the keyboard layout could not be switched.")); return
                }
                let expiryID = next.lastUsed
                let expiryDelay = min(5_000_000_000, 30_000_000_000 - min(30_000_000_000, expiryID &- next.began))
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: expiryDelay)
                    if self?.cycle?.lastUsed == expiryID { self?.cycle = nil }
                }
                trace(.finished, .completed, DiagnosticDetails(dispatched: true, confirmed: false))
                completion(.completed(sourceID: destination.id))
            } catch {
                let mutated = transport.mutationBegan
                invalidate()
                let reason: DiagnosticReason
                if let ax = error as? CorrectionAXError { reason = DiagnosticReason(ax: ax) }
                else if let mapping = error as? CorrectionMappingError { reason = DiagnosticReason(mapping: mapping) }
                else { reason = .unexpected }
                trace(.finished, reason, DiagnosticDetails(dispatched: mutated, confirmed: false))
                completion(.failed(mutated ? "Correction stopped after sending input; check the text before trying again." : Self.message(error)))
            }
        }
    }

    private static func render(_ keys: [CorrectionPhysicalKey], source: CorrectionSource) throws -> String {
        try keys.map { key in
            guard let value = source.keyMap[key], value.count == 1 else { throw CorrectionMappingError.unsupportedCharacter }
            return value
        }.joined()
    }
    private static func message(_ error: Error) -> String {
        switch error {
        case CorrectionAXError.unsupported: "Focus an editable text field outside Secure Input."
        case CorrectionAXError.stale: "The input context changed; correction stopped."
        case CorrectionAXError.limit: "Select up to 12,288 characters for layout correction."
        case CorrectionMappingError.unchanged: "The text already matches that keyboard layout."
        case is CorrectionMappingError: "This text cannot be mapped to the next keyboard layout."
        default: "No selection or recent typed word is available for correction."
        }
    }
}
