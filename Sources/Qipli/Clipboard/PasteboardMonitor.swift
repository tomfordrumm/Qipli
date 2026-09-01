import AppKit
import Foundation

struct PasteboardRepresentationInventory: Equatable, Sendable {
    let itemCount: Int
    let representationCounts: [String: Int]
}

/// A payload-free probe for deciding the future typed allowlist. It reads only
/// item/type shape; it never asks NSPasteboard for a value or emits one.
enum PasteboardPlatformProbe {
    static func inventory(for pasteboard: NSPasteboard) -> PasteboardRepresentationInventory {
        inventory(for: pasteboard.pasteboardItems ?? [])
    }

    static func inventory(for items: [NSPasteboardItem]) -> PasteboardRepresentationInventory {
        var counts: [String: Int] = [:]
        for item in items {
            for type in item.types {
                counts[type.rawValue, default: 0] += 1
            }
        }
        return PasteboardRepresentationInventory(
            itemCount: items.count,
            representationCounts: counts
        )
    }
}

protocol PasteboardReading: AnyObject {
    var changeCount: Int { get }
    func textValue() -> String?
}

struct PasteboardTextChange: Equatable {
    let changeCount: Int
    let text: String
}

final class SystemPasteboardReader: PasteboardReading {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int { pasteboard.changeCount }

    func textValue() -> String? {
        pasteboard.string(forType: .string)
    }

    /// Used by the controlled S023 probe; normal polling remains text-only
    /// until a later slice changes the capture allowlist.
    func representationInventory() -> PasteboardRepresentationInventory {
        PasteboardPlatformProbe.inventory(for: pasteboard)
    }
}

@MainActor
protocol PasteboardPollCancellation: AnyObject {
    func cancel()
}

@MainActor
protocol PasteboardPollScheduling: AnyObject {
    func schedule(
        interval: TimeInterval,
        tolerance: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> PasteboardPollCancellation
}

@MainActor
final class TimerPasteboardPollCancellation: PasteboardPollCancellation {
    private var timer: Timer?

    init(timer: Timer) {
        self.timer = timer
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }
}

@MainActor
final class RunLoopPasteboardPollScheduler: PasteboardPollScheduling {
    func schedule(
        interval: TimeInterval,
        tolerance: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> PasteboardPollCancellation {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated {
                action()
            }
        }
        timer.tolerance = tolerance
        RunLoop.main.add(timer, forMode: .common)
        return TimerPasteboardPollCancellation(timer: timer)
    }
}

/// Polls the system pasteboard. A suppression is tied to one exact change number, never its text.
@MainActor
final class PasteboardMonitor {
    nonisolated static let productionInterval: TimeInterval = 0.35
    nonisolated static let productionTolerance: TimeInterval = 0.05

    private let pasteboard: PasteboardReading
    private let scheduler: PasteboardPollScheduling
    private let onExternalText: (PasteboardTextChange) -> Void
    private var lastChangeCount: Int?
    private var ignoredChanges = Set<Int>()
    private var scheduledPoll: PasteboardPollCancellation?

    init(
        pasteboard: PasteboardReading = SystemPasteboardReader(),
        scheduler: PasteboardPollScheduling? = nil,
        onExternalText: @escaping (PasteboardTextChange) -> Void
    ) {
        self.pasteboard = pasteboard
        self.scheduler = scheduler ?? RunLoopPasteboardPollScheduler()
        self.onExternalText = onExternalText
    }

    var currentChangeCount: Int { pasteboard.changeCount }

    func start(
        interval: TimeInterval = productionInterval,
        tolerance: TimeInterval = productionTolerance
    ) {
        guard scheduledPoll == nil else { return }
        lastChangeCount = pasteboard.changeCount
        scheduledPoll = scheduler.schedule(interval: interval, tolerance: tolerance) { [weak self] in
            self?.poll()
        }
    }

    func stop() {
        scheduledPoll?.cancel()
        scheduledPoll = nil
    }

    /// Called by future Qipli writers immediately after their pasteboard write completes.
    func registerSelfWrite(changeCount: Int) {
        ignoredChanges.insert(changeCount)
    }

    func poll() {
        let currentChangeCount = pasteboard.changeCount
        guard let lastChangeCount else {
            self.lastChangeCount = currentChangeCount
            return
        }
        guard currentChangeCount != lastChangeCount else { return }
        self.lastChangeCount = currentChangeCount

        // A newer external change makes every older expected self-write irrelevant.
        ignoredChanges = ignoredChanges.filter { $0 >= currentChangeCount }
        guard ignoredChanges.remove(currentChangeCount) == nil else { return }
        guard let text = pasteboard.textValue() else { return }
        onExternalText(PasteboardTextChange(changeCount: currentChangeCount, text: text))
    }
}
