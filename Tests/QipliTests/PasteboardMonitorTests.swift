import XCTest
@testable import Qipli

@MainActor
final class PasteboardMonitorTests: XCTestCase {
    func testInitializationDoesNotReadPasteboardBeforeStartupGateOpens() {
        let pasteboard = FakePasteboard(changeCount: 1)

        _ = PasteboardMonitor(pasteboard: pasteboard) { _ in }

        XCTAssertEqual(pasteboard.changeCountReadCount, 0)
    }

    func testDoesNotImportClipboardContentThatPredatesTheMonitor() {
        let pasteboard = FakePasteboard(changeCount: 1)
        pasteboard.setText("already on clipboard")
        var captured: [String] = []
        let monitor = PasteboardMonitor(pasteboard: pasteboard) { captured.append($0.text) }
        monitor.start(interval: 3_600)
        defer { monitor.stop() }

        monitor.poll()
        XCTAssertTrue(captured.isEmpty)

        pasteboard.setText("copied while running")
        monitor.poll()
        XCTAssertEqual(captured, ["copied while running"])
    }

    func testCapturesExactTextAndPreservesDuplicateEvents() {
        let pasteboard = FakePasteboard(changeCount: 1)
        var captured: [String] = []
        let monitor = PasteboardMonitor(pasteboard: pasteboard) { captured.append($0.text) }
        monitor.start(interval: 3_600)
        defer { monitor.stop() }
        let multiline = ["line one", "🦊  https://example.test"].joined(separator: "\n")

        pasteboard.setText(multiline)
        monitor.poll()
        pasteboard.setText(multiline)
        monitor.poll()

        XCTAssertEqual(captured, [multiline, multiline])
    }

    func testIgnoresUnsupportedAndOnlyTheRegisteredSelfWriteChange() {
        let pasteboard = FakePasteboard(changeCount: 3)
        var captured: [String] = []
        let monitor = PasteboardMonitor(pasteboard: pasteboard) { captured.append($0.text) }
        monitor.start(interval: 3_600)
        defer { monitor.stop() }

        pasteboard.setUnsupportedValue()
        monitor.poll()

        pasteboard.setText("internal content")
        monitor.registerSelfWrite(changeCount: pasteboard.changeCount)
        monitor.poll()

        pasteboard.setText("internal content")
        monitor.poll()

        XCTAssertEqual(captured, ["internal content"])
    }

    func testDiscardsStaleSuppressionWhenExternalChangeOvertakesIt() {
        let pasteboard = FakePasteboard(changeCount: 8)
        var captured: [String] = []
        let monitor = PasteboardMonitor(pasteboard: pasteboard) { captured.append($0.text) }
        monitor.start(interval: 3_600)
        defer { monitor.stop() }

        monitor.registerSelfWrite(changeCount: 9)
        pasteboard.setText("external value")
        pasteboard.setText("newer external value")
        monitor.poll()

        XCTAssertEqual(captured, ["newer external value"])
    }

    func testExplicitPollCompletesCaptureBeforePresentationContinues() {
        let pasteboard = FakePasteboard(changeCount: 20)
        var events: [String] = []
        let monitor = PasteboardMonitor(pasteboard: pasteboard) { change in
            events.append("capture:\(change.text)")
        }
        monitor.start(interval: 3_600)
        defer { monitor.stop() }
        pasteboard.setText("fresh value")

        monitor.poll()
        events.append("present")

        XCTAssertEqual(events, ["capture:fresh value", "present"])
    }
}

private final class FakePasteboard: PasteboardReading {
    private var storedChangeCount: Int
    private(set) var changeCountReadCount = 0
    private var text: String?

    init(changeCount: Int) {
        storedChangeCount = changeCount
    }

    var changeCount: Int {
        changeCountReadCount += 1
        return storedChangeCount
    }

    func textValue() -> String? { text }

    func setText(_ text: String) {
        self.text = text
        storedChangeCount += 1
    }

    func setUnsupportedValue() {
        text = nil
        storedChangeCount += 1
    }
}
