import Foundation

/// Stable, payload-free performance boundaries. Operation names must never be
/// derived from clipboard text, search queries, previews, or entry identifiers.
enum PerformanceOperation: String, CaseIterable, Sendable {
    case historyFetch
    case historySearch
    case previewConstruction
    case stackTraversal
    case pasteboardPoll
}

/// A safe aggregate observation suitable for local tests and Debug tooling.
/// It deliberately has no free-form metadata field where product payload could leak.
struct PerformanceObservation: Equatable, Sendable {
    let operation: PerformanceOperation
    let itemCount: Int
    let elapsedNanoseconds: UInt64
}

struct PerformanceProbe {
    typealias Clock = () -> UInt64
    typealias Recorder = (PerformanceObservation) -> Void

    private let clock: Clock
    private let recorder: Recorder

    init(
        clock: @escaping Clock = { DispatchTime.now().uptimeNanoseconds },
        recorder: @escaping Recorder = { _ in }
    ) {
        self.clock = clock
        self.recorder = recorder
    }

    @discardableResult
    func measure<Result>(
        _ operation: PerformanceOperation,
        itemCount: Int,
        _ work: () throws -> Result
    ) rethrows -> Result {
        let startedAt = clock()
        defer {
            let finishedAt = clock()
            recorder(PerformanceObservation(
                operation: operation,
                itemCount: max(0, itemCount),
                elapsedNanoseconds: finishedAt >= startedAt ? finishedAt - startedAt : 0
            ))
        }
        return try work()
    }
}
