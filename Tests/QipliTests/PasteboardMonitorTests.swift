import AppKit
import XCTest
@testable import Qipli

@MainActor
final class PasteboardMonitorTests: XCTestCase {
    func testPayloadFreeProbeReportsOnlyItemAndRepresentationShape() throws {
        let textItem = NSPasteboardItem()
        XCTAssertTrue(textItem.setData(Data("safe fixture".utf8), forType: .string))
        XCTAssertTrue(textItem.setData(Data("<p>safe fixture</p>".utf8), forType: .html))
        let urlItem = NSPasteboardItem()
        XCTAssertTrue(urlItem.setData(Data(), forType: .URL))
        let imageItem = NSPasteboardItem()
        XCTAssertTrue(imageItem.setData(Data(), forType: .tiff))
        let finderItem = NSPasteboardItem()
        XCTAssertTrue(finderItem.setData(Data(), forType: .fileURL))

        let inventory = PasteboardPlatformProbe.inventory(for: [textItem, urlItem, imageItem, finderItem])

        XCTAssertEqual(inventory.itemCount, 4)
        XCTAssertEqual(inventory.representationCounts[NSPasteboard.PasteboardType.string.rawValue], 1)
        XCTAssertEqual(inventory.representationCounts[NSPasteboard.PasteboardType.html.rawValue], 1)
        XCTAssertEqual(inventory.representationCounts[NSPasteboard.PasteboardType.URL.rawValue], 1)
        XCTAssertEqual(inventory.representationCounts[NSPasteboard.PasteboardType.tiff.rawValue], 1)
        XCTAssertEqual(inventory.representationCounts[NSPasteboard.PasteboardType.fileURL.rawValue], 1)
        XCTAssertEqual(inventory.representationCounts.values.reduce(0, +), 5)
    }

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

    func testTypedImageChangeUsesTheObservedChangeCountAndSkipsTextFallback() async {
        let pasteboard = FakeTypedPasteboard(changeCount: 70)
        var typedChanges: [PasteboardTypedChange] = []
        var textChanges: [PasteboardTextChange] = []
        let typedExpectation = expectation(description: "typed image change")
        let monitor = PasteboardMonitor(
            pasteboard: pasteboard,
            onExternalText: { textChanges.append($0) },
            onExternalChange: {
                typedChanges.append($0)
                typedExpectation.fulfill()
            }
        )
        monitor.start(interval: 3_600)
        defer { monitor.stop() }

        pasteboard.publishImageChange()
        monitor.poll()
        await fulfillment(of: [typedExpectation], timeout: 1)

        XCTAssertEqual(typedChanges.map(\.changeCount), [71])
        XCTAssertEqual(typedChanges.first?.imageItems.count, 1)
        XCTAssertTrue(textChanges.isEmpty)
        XCTAssertEqual(pasteboard.textValueReadCount, 0)
    }

    func testTypedChangeClassifiesWebURLAndFinderFileWithoutReadingFileBytes() throws {
        let pasteboard = try XCTUnwrap(NSPasteboard(name: NSPasteboard.Name("QipliTests.\(UUID().uuidString)")))
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("fixture.txt")
        let sourceBytes = Data("source remains outside Qipli".utf8)
        try sourceBytes.write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let urlItem = NSPasteboardItem()
        XCTAssertTrue(urlItem.setString("https://example.com/docs?q=1", forType: .URL))
        let fileItem = NSPasteboardItem()
        XCTAssertTrue(fileItem.setString(sourceURL.absoluteString, forType: .fileURL))
        XCTAssertTrue(pasteboard.writeObjects([urlItem, fileItem]))

        let change = try XCTUnwrap(SystemPasteboardReader(pasteboard: pasteboard).typedImageChange(changeCount: 44))
        XCTAssertTrue(change.imageItems.isEmpty)
        XCTAssertEqual(change.referenceItems.map(\.order), [0, 1])
        XCTAssertEqual(change.referenceItems.map(\.kind), [.url, .fileReference])
        XCTAssertEqual(change.referenceItems.first?.metadata.domain, "example.com")
        XCTAssertEqual(change.referenceItems.last?.metadata.displayName, "fixture.txt")
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBytes)
    }

    func testTypedChangeKeepsImageAndURLRepresentationsFromOnePasteboardItem() throws {
        let pasteboard = try XCTUnwrap(NSPasteboard(name: NSPasteboard.Name("QipliTests.\(UUID().uuidString)")))
        let item = NSPasteboardItem()
        XCTAssertTrue(item.setData(Data([0x01, 0x02]), forType: .tiff))
        XCTAssertTrue(item.setString("https://example.com/image", forType: .URL))
        XCTAssertTrue(pasteboard.writeObjects([item]))

        let change = try XCTUnwrap(SystemPasteboardReader(pasteboard: pasteboard).typedImageChange(changeCount: 46))
        XCTAssertEqual(change.imageItems.map(\.order), [0])
        XCTAssertEqual(change.referenceItems.map(\.order), [0])
        XCTAssertEqual(change.referenceItems.first?.urlString, "https://example.com/image")
    }

    func testPlainTextThatLooksLikeURLDoesNotBecomeURLReference() throws {
        let pasteboard = try XCTUnwrap(NSPasteboard(name: NSPasteboard.Name("QipliTests.\(UUID().uuidString)")))
        let item = NSPasteboardItem()
        XCTAssertTrue(item.setString("https://example.com/plain-text", forType: .string))
        XCTAssertTrue(pasteboard.writeObjects([item]))

        XCTAssertNil(SystemPasteboardReader(pasteboard: pasteboard).typedImageChange(changeCount: 45))
    }

    func testTypedWriterPublishesURLAndFileURLRepresentations() throws {
        let pasteboard = try XCTUnwrap(NSPasteboard(name: NSPasteboard.Name("QipliTests.\(UUID().uuidString)")))
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("writer.txt")
        let payload = HistoryPastePayload(items: [
            HistoryPasteboardItemPayload(representations: [
                HistoryPasteboardRepresentationPayload(typeIdentifier: "public.url", data: Data("https://example.com".utf8))
            ]),
            HistoryPasteboardItemPayload(representations: [
                HistoryPasteboardRepresentationPayload(typeIdentifier: "public.file-url", data: Data(fileURL.absoluteString.utf8))
            ])
        ])

        _ = try SystemHistoryPasteboardWriter(pasteboard: pasteboard).write(payload: payload)
        let items = try XCTUnwrap(pasteboard.pasteboardItems)
        XCTAssertEqual(items[0].string(forType: .URL), "https://example.com")
        XCTAssertEqual(items[1].string(forType: .fileURL), fileURL.absoluteString)
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

private final class FakeTypedPasteboard: PasteboardReading, TypedPasteboardReading {
    private var storedChangeCount: Int
    private(set) var textValueReadCount = 0
    private var pendingChange: PasteboardTypedChange?

    init(changeCount: Int) {
        storedChangeCount = changeCount
    }

    var changeCount: Int { storedChangeCount }

    func textValue() -> String? {
        textValueReadCount += 1
        return "text fallback"
    }

    func publishImageChange() {
        storedChangeCount += 1
        pendingChange = PasteboardTypedChange(
            changeCount: -1,
            imageItems: [ManagedImageCaptureItem(
                order: 0,
                representations: [ManagedImageCaptureRepresentation(
                    typeIdentifier: "public.png",
                    data: Data([1, 2, 3])
                )]
            )]
        )
    }

    func typedImageChange(changeCount: Int) -> PasteboardTypedChange? {
        guard let pendingChange else { return nil }
        self.pendingChange = nil
        return PasteboardTypedChange(changeCount: changeCount, imageItems: pendingChange.imageItems)
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
