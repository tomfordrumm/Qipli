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

    func testSchedulerUsesProductionCadenceAndOneFireRunsOneImmediatePoll() {
        let pasteboard = FakePasteboard(changeCount: 30)
        let scheduler = FakePasteboardPollScheduler()
        var captured: [PasteboardTextChange] = []
        let monitor = PasteboardMonitor(pasteboard: pasteboard, scheduler: scheduler) {
            captured.append($0)
        }

        monitor.start()

        XCTAssertEqual(scheduler.scheduleCount, 1)
        XCTAssertEqual(scheduler.lastInterval, PasteboardMonitor.productionInterval)
        XCTAssertEqual(scheduler.lastTolerance, PasteboardMonitor.productionTolerance)
        XCTAssertEqual(pasteboard.changeCountReadCount, 1)

        scheduler.fire()
        XCTAssertEqual(pasteboard.changeCountReadCount, 2)
        XCTAssertEqual(pasteboard.textValueReadCount, 0)

        pasteboard.setText("timer capture")
        scheduler.fire()
        XCTAssertEqual(pasteboard.changeCountReadCount, 3)
        XCTAssertEqual(pasteboard.textValueReadCount, 1)
        XCTAssertEqual(captured.map(\.text), ["timer capture"])
    }

    func testRepeatedStartDoesNotCreateAnotherTimerAndStopCancelsFutureTicks() {
        let pasteboard = FakePasteboard(changeCount: 40)
        let scheduler = FakePasteboardPollScheduler()
        let monitor = PasteboardMonitor(pasteboard: pasteboard, scheduler: scheduler) { _ in }

        monitor.start(interval: 1, tolerance: 0.1)
        monitor.start(interval: 2, tolerance: 0.2)

        XCTAssertEqual(scheduler.scheduleCount, 1)
        XCTAssertEqual(pasteboard.changeCountReadCount, 1)

        monitor.stop()
        let readsBeforeCanceledFire = pasteboard.changeCountReadCount
        scheduler.fire()
        XCTAssertEqual(scheduler.cancellationCount, 1)
        XCTAssertEqual(pasteboard.changeCountReadCount, readsBeforeCanceledFire)

        monitor.start(interval: 2, tolerance: 0.2)
        XCTAssertEqual(scheduler.scheduleCount, 2)
        XCTAssertEqual(scheduler.lastInterval, 2)
        XCTAssertEqual(scheduler.lastTolerance, 0.2)
    }

    func testTimerCancellationInvalidatesItsTimerWhenReleasedWithoutExplicitCancel() {
        let timer = Timer(timeInterval: 3_600, repeats: true) { _ in }
        RunLoop.main.add(timer, forMode: .common)
        weak var releasedCancellation: TimerPasteboardPollCancellation?

        do {
            let cancellation = TimerPasteboardPollCancellation(timer: timer)
            releasedCancellation = cancellation
            XCTAssertTrue(timer.isValid)
        }

        XCTAssertNil(releasedCancellation)
        XCTAssertFalse(timer.isValid)
    }

    func testScheduledRapidDuplicatesAndSelfWriteKeepExactSuppressionBehavior() {
        let pasteboard = FakePasteboard(changeCount: 50)
        let scheduler = FakePasteboardPollScheduler()
        var captured: [String] = []
        let monitor = PasteboardMonitor(pasteboard: pasteboard, scheduler: scheduler) {
            captured.append($0.text)
        }
        monitor.start()

        pasteboard.setText("duplicate")
        scheduler.fire()
        pasteboard.setText("duplicate")
        scheduler.fire()
        pasteboard.setText("self write")
        monitor.registerSelfWrite(changeCount: pasteboard.changeCount)
        scheduler.fire()

        XCTAssertEqual(captured, ["duplicate", "duplicate"])
    }
}

private final class FakePasteboard: PasteboardReading {
    private var storedChangeCount: Int
    private(set) var changeCountReadCount = 0
    private(set) var textValueReadCount = 0
    private var text: String?

    init(changeCount: Int) {
        storedChangeCount = changeCount
    }

    var changeCount: Int {
        changeCountReadCount += 1
        return storedChangeCount
    }

    func textValue() -> String? {
        textValueReadCount += 1
        return text
    }

    func setText(_ text: String) {
        self.text = text
        storedChangeCount += 1
    }

    func setUnsupportedValue() {
        text = nil
        storedChangeCount += 1
    }
}

@MainActor
private final class FakePasteboardPollScheduler: PasteboardPollScheduling {
    private var activeAction: (@MainActor () -> Void)?
    private var generation = 0
    private(set) var scheduleCount = 0
    private(set) var cancellationCount = 0
    private(set) var lastInterval: TimeInterval?
    private(set) var lastTolerance: TimeInterval?

    func schedule(
        interval: TimeInterval,
        tolerance: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> PasteboardPollCancellation {
        scheduleCount += 1
        generation += 1
        let scheduledGeneration = generation
        lastInterval = interval
        lastTolerance = tolerance
        activeAction = action
        return FakePasteboardPollCancellation { [weak self] in
            guard let self, self.generation == scheduledGeneration else { return }
            self.cancellationCount += 1
            self.activeAction = nil
        }
    }

    func fire() {
        activeAction?()
    }
}

@MainActor
private final class FakePasteboardPollCancellation: PasteboardPollCancellation {
    private var cancelAction: (@MainActor () -> Void)?

    init(cancelAction: @escaping @MainActor () -> Void) {
        self.cancelAction = cancelAction
    }

    func cancel() {
        cancelAction?()
        cancelAction = nil
    }
}
