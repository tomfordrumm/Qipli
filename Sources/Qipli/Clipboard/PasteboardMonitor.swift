import AppKit
import Foundation

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
}

/// Polls the system pasteboard. A suppression is tied to one exact change number, never its text.
final class PasteboardMonitor {
    private let pasteboard: PasteboardReading
    private let onExternalText: (PasteboardTextChange) -> Void
    private var lastChangeCount: Int?
    private var ignoredChanges = Set<Int>()
    private var timer: Timer?

    init(pasteboard: PasteboardReading = SystemPasteboardReader(), onExternalText: @escaping (PasteboardTextChange) -> Void) {
        self.pasteboard = pasteboard
        self.onExternalText = onExternalText
    }

    var currentChangeCount: Int { pasteboard.changeCount }

    func start(interval: TimeInterval = 0.35) {
        stop()
        lastChangeCount = pasteboard.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
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
