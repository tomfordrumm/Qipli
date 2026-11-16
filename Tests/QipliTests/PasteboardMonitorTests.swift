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

    func testImageCaptureStopsReadingFurtherRepresentationsAfterSizeRejection() throws {
        let item = NSPasteboardItem()
        item.setData(Data([1]), forType: .png)
        item.setData(Data([1]), forType: .tiff)
        let policy = HistoryImageStoragePolicy(maxImageItemBytes: 4, maxOccurrenceBytes: 8,
            maxTotalOriginalBytes: 16, thumbnailCacheBytes: 8, thumbnailLongEdge: 4)
        var reads = 0
        let result = SystemPasteboardReader.imageCapture(from: [item], policy: policy) { _, _ in
            reads += 1
            return Data(repeating: 1, count: 5)
        }
        XCTAssertEqual(reads, 1)
        XCTAssertThrowsError(try result.get()) { XCTAssertEqual($0 as? ManagedImageStoreError, .imageItemTooLarge) }
        let rejected = PasteboardTypedChange(changeCount: 9, captureFailure: .imageItemTooLarge)
        XCTAssertNil(ApplicationShellPasteboardRouting.capture(from: rejected))
    }

    func testImageCaptureAppliesCumulativeOccurrenceLimitAcrossItems() {
        let item = NSPasteboardItem()
        item.setData(Data([1]), forType: .png)
        let policy = HistoryImageStoragePolicy(maxImageItemBytes: 4, maxOccurrenceBytes: 6,
            maxTotalOriginalBytes: 12, thumbnailCacheBytes: 8, thumbnailLongEdge: 4)
        var reads = 0
        let result = SystemPasteboardReader.imageCapture(from: [item, item, item], policy: policy) { _, _ in
            reads += 1
            return Data(repeating: 1, count: 4)
        }
        XCTAssertEqual(reads, 2)
        XCTAssertThrowsError(try result.get()) { XCTAssertEqual($0 as? ManagedImageStoreError, .occurrenceTooLarge) }
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

    func testTypedReadDiscardsLivePasteboardContentsWhenASecondChangeOvertakesIt() async {
        let pasteboard = BlockingTypedPasteboard(changeCount: 80)
        let firstReadStarted = expectation(description: "first typed read started")
        let latestChangeCaptured = expectation(description: "latest typed change captured")
        pasteboard.onFirstReadStarted = { firstReadStarted.fulfill() }
        var captured: [PasteboardTypedChange] = []
        let monitor = PasteboardMonitor(
            pasteboard: pasteboard,
            onExternalText: { _ in XCTFail("typed changes must not fall back to text") },
            onExternalChange: {
                captured.append($0)
                latestChangeCaptured.fulfill()
            }
        )
        monitor.start(interval: 3_600)
        defer { monitor.stop() }

        pasteboard.publishImageChange(marker: 1)
        monitor.poll()
        await fulfillment(of: [firstReadStarted], timeout: 1)

        pasteboard.publishImageChange(marker: 2)
        monitor.poll()
        pasteboard.releaseFirstRead()

        await fulfillment(of: [latestChangeCaptured], timeout: 1)
        XCTAssertEqual(captured.map(\.changeCount), [82])
        XCTAssertEqual(captured.first?.imageItems.first?.representations.first?.data, Data([2]))
    }

    func testMarkedDictationRestoresAreSkippedAndAnExplicitRecopyIsCaptured() async throws {
        let pasteboard = try requireNamedPasteboard()
        defer { pasteboard.releaseGlobally() }
        let firstImage = expectation(description: "original image captured")
        let firstTranscript = expectation(description: "first temporary text observed")
        let secondTranscript = expectation(description: "second temporary text observed")
        let restoredImages = expectation(description: "restored image must not be captured")
        restoredImages.isInverted = true
        let explicitRecopy = expectation(description: "explicit recopy captured")
        let differentImage = expectation(description: "different image captured after marked text")
        var imageExpectation = firstImage
        var textExpectation = firstTranscript
        let monitor = PasteboardMonitor(
            pasteboard: SystemPasteboardReader(pasteboard: pasteboard),
            scheduler: FakePasteboardPollScheduler(),
            onExternalText: { _ in textExpectation.fulfill() },
            onExternalChange: { _ in imageExpectation.fulfill() }
        )
        monitor.start()
        defer { monitor.stop() }

        func pollImage(_ byte: UInt8) throws {
            let item = NSPasteboardItem()
            XCTAssertTrue(item.setData(Data([byte]), forType: .png))
            pasteboard.clearContents()
            try requirePasteboardWrite([item], to: pasteboard)
            monitor.poll()
        }
        func pollTranscript() throws {
            pasteboard.clearContents()
            try requirePasteboardWrite([makeMarkedTranscript()], to: pasteboard)
            monitor.poll()
        }

        try pollImage(1)
        await fulfillment(of: [firstImage], timeout: 1)
        try pollTranscript()
        await fulfillment(of: [firstTranscript], timeout: 1)
        imageExpectation = restoredImages
        try pollImage(1)
        await fulfillment(of: [restoredImages], timeout: 0.15)

        textExpectation = secondTranscript
        try pollTranscript()
        await fulfillment(of: [secondTranscript], timeout: 1)
        let secondRestore = expectation(description: "second restored image must not be captured")
        secondRestore.isInverted = true
        imageExpectation = secondRestore
        try pollImage(1)
        await fulfillment(of: [secondRestore], timeout: 0.15)

        imageExpectation = explicitRecopy
        try pollImage(1)
        await fulfillment(of: [explicitRecopy], timeout: 1)

        let thirdTranscript = expectation(description: "third temporary text observed")
        textExpectation = thirdTranscript
        try pollTranscript()
        await fulfillment(of: [thirdTranscript], timeout: 1)
        imageExpectation = differentImage
        try pollImage(2)
        await fulfillment(of: [differentImage], timeout: 1)
    }

    func testSameImageAfterMissedRestoreIsCaptured() async throws {
        let pasteboard = try requireNamedPasteboard()
        defer { pasteboard.releaseGlobally() }
        let firstImage = expectation(description: "original image captured")
        let transcript = expectation(description: "temporary text observed")
        let explicitRecopy = expectation(description: "new copy after unobserved restore captured")
        var imageExpectation = firstImage
        let monitor = PasteboardMonitor(
            pasteboard: SystemPasteboardReader(pasteboard: pasteboard),
            scheduler: FakePasteboardPollScheduler(),
            onExternalText: { _ in transcript.fulfill() },
            onExternalChange: { _ in imageExpectation.fulfill() }
        )
        monitor.start()
        defer { monitor.stop() }

        func writeImage() throws {
            let item = NSPasteboardItem()
            XCTAssertTrue(item.setData(Data([1]), forType: .png))
            pasteboard.clearContents()
            try requirePasteboardWrite([item], to: pasteboard)
        }

        try writeImage()
        monitor.poll()
        await fulfillment(of: [firstImage], timeout: 1)
        pasteboard.clearContents()
        try requirePasteboardWrite([makeMarkedTranscript()], to: pasteboard)
        monitor.poll()
        await fulfillment(of: [transcript], timeout: 1)

        imageExpectation = explicitRecopy
        try writeImage() // Hex restore happens between polls.
        try writeImage() // The user copies the same image before the next poll.
        monitor.poll()
        await fulfillment(of: [explicitRecopy], timeout: 1)
    }

    func testMarkedDictationRestoresOfPlainTextAreSkippedAndAnExplicitRecopyIsCaptured() async throws {
        let pasteboard = try requireNamedPasteboard()
        defer { pasteboard.releaseGlobally() }
        let firstCopy = expectation(description: "original text captured")
        let firstTranscript = expectation(description: "first temporary text observed")
        let secondTranscript = expectation(description: "second temporary text observed")
        let thirdTranscript = expectation(description: "third temporary text observed")
        let restoredText = expectation(description: "restored text must not be captured")
        restoredText.isInverted = true
        let secondRestore = expectation(description: "second restored text must not be captured")
        secondRestore.isInverted = true
        let explicitRecopy = expectation(description: "explicit recopy captured")
        let differentText = expectation(description: "different text captured after marked text")
        var captured: [String] = []
        var textExpectation = firstCopy
        let monitor = PasteboardMonitor(
            pasteboard: SystemPasteboardReader(pasteboard: pasteboard),
            scheduler: FakePasteboardPollScheduler(),
            onExternalText: {
                captured.append($0.text)
                textExpectation.fulfill()
            },
            onExternalChange: { _ in XCTFail("plain text must not be routed as a typed change") }
        )
        monitor.start()
        defer { monitor.stop() }

        func pollText(_ text: String) throws {
            let item = NSPasteboardItem()
            XCTAssertTrue(item.setString(text, forType: .string))
            pasteboard.clearContents()
            try requirePasteboardWrite([item], to: pasteboard)
            monitor.poll()
        }
        func pollTranscript() throws {
            pasteboard.clearContents()
            try requirePasteboardWrite([makeMarkedTranscript()], to: pasteboard)
            monitor.poll()
        }

        try pollText("previous fixture")
        await fulfillment(of: [firstCopy], timeout: 1)
        textExpectation = firstTranscript
        try pollTranscript()
        await fulfillment(of: [firstTranscript], timeout: 1)
        textExpectation = restoredText
        try pollText("previous fixture")
        await fulfillment(of: [restoredText], timeout: 0.15)

        textExpectation = secondTranscript
        try pollTranscript()
        await fulfillment(of: [secondTranscript], timeout: 1)
        textExpectation = secondRestore
        try pollText("previous fixture")
        await fulfillment(of: [secondRestore], timeout: 0.15)

        textExpectation = explicitRecopy
        try pollText("previous fixture")
        await fulfillment(of: [explicitRecopy], timeout: 1)

        textExpectation = thirdTranscript
        try pollTranscript()
        await fulfillment(of: [thirdTranscript], timeout: 1)
        textExpectation = differentText
        try pollText("different fixture")
        await fulfillment(of: [differentText], timeout: 1)

        XCTAssertEqual(captured, [
            "previous fixture", "dictation fixture", "dictation fixture",
            "previous fixture", "dictation fixture", "different fixture"
        ])
    }

    func testMarkedDictationRestoresOfRichTextAreSkippedAndAnExplicitRecopyIsCaptured() async throws {
        let pasteboard = try requireNamedPasteboard()
        defer { pasteboard.releaseGlobally() }
        let firstCopy = expectation(description: "original rich text captured")
        let transcript = expectation(description: "temporary text observed")
        let restoredRichText = expectation(description: "restored rich text must not be captured")
        restoredRichText.isInverted = true
        let explicitRecopy = expectation(description: "explicit rich recopy captured")
        var typedExpectation = firstCopy
        var capturedCounts: [Int] = []
        let monitor = PasteboardMonitor(
            pasteboard: SystemPasteboardReader(pasteboard: pasteboard),
            scheduler: FakePasteboardPollScheduler(),
            onExternalText: { _ in transcript.fulfill() },
            onExternalChange: {
                capturedCounts.append($0.changeCount)
                typedExpectation.fulfill()
            }
        )
        monitor.start()
        defer { monitor.stop() }

        func pollRichText() throws {
            let item = NSPasteboardItem()
            XCTAssertTrue(item.setString("formatted fixture", forType: .string))
            XCTAssertTrue(item.setData(Data("{\\rtf1 formatted fixture}".utf8), forType: .rtf))
            pasteboard.clearContents()
            try requirePasteboardWrite([item], to: pasteboard)
            monitor.poll()
        }

        try pollRichText()
        await fulfillment(of: [firstCopy], timeout: 1)
        pasteboard.clearContents()
        try requirePasteboardWrite([makeMarkedTranscript()], to: pasteboard)
        monitor.poll()
        await fulfillment(of: [transcript], timeout: 1)

        typedExpectation = restoredRichText
        try pollRichText()
        await fulfillment(of: [restoredRichText], timeout: 0.15)

        typedExpectation = explicitRecopy
        try pollRichText()
        await fulfillment(of: [explicitRecopy], timeout: 1)
        XCTAssertEqual(capturedCounts.count, 2)
    }

    func testSameTextAfterMissedRestoreIsCaptured() async throws {
        let pasteboard = try requireNamedPasteboard()
        defer { pasteboard.releaseGlobally() }
        let firstCopy = expectation(description: "original text captured")
        let transcript = expectation(description: "temporary text observed")
        let explicitRecopy = expectation(description: "new copy after unobserved restore captured")
        var captured: [String] = []
        var textExpectation = firstCopy
        let monitor = PasteboardMonitor(
            pasteboard: SystemPasteboardReader(pasteboard: pasteboard),
            scheduler: FakePasteboardPollScheduler(),
            onExternalText: {
                captured.append($0.text)
                textExpectation.fulfill()
            },
            onExternalChange: { _ in XCTFail("plain text must not be routed as a typed change") }
        )
        monitor.start()
        defer { monitor.stop() }

        func writeText(_ text: String) throws {
            let item = NSPasteboardItem()
            XCTAssertTrue(item.setString(text, forType: .string))
            pasteboard.clearContents()
            try requirePasteboardWrite([item], to: pasteboard)
        }

        try writeText("previous fixture")
        monitor.poll()
        await fulfillment(of: [firstCopy], timeout: 1)
        textExpectation = transcript
        pasteboard.clearContents()
        try requirePasteboardWrite([makeMarkedTranscript()], to: pasteboard)
        monitor.poll()
        await fulfillment(of: [transcript], timeout: 1)

        textExpectation = explicitRecopy
        try writeText("previous fixture") // Hex restore happens between polls.
        try writeText("previous fixture") // The user copies the same text before the next poll.
        monitor.poll()
        await fulfillment(of: [explicitRecopy], timeout: 1)
        XCTAssertEqual(captured, ["previous fixture", "dictation fixture", "previous fixture"])
    }

    func testDifferentSecondRichTextItemAfterTranscriptIsCaptured() async throws {
        let pasteboard = try requireNamedPasteboard()
        defer { pasteboard.releaseGlobally() }
        let firstCopy = expectation(description: "original multi-item rich text captured")
        let transcript = expectation(description: "temporary text observed")
        let changedCopy = expectation(description: "copy with a different second item captured")
        var typedExpectation = firstCopy
        var captured: [[String?]] = []
        let monitor = PasteboardMonitor(
            pasteboard: SystemPasteboardReader(pasteboard: pasteboard),
            scheduler: FakePasteboardPollScheduler(),
            onExternalText: { _ in transcript.fulfill() },
            onExternalChange: {
                captured.append($0.richTextItems.map(\.canonicalText))
                typedExpectation.fulfill()
            }
        )
        monitor.start()
        defer { monitor.stop() }

        func pollRichItems(tail: String) throws {
            let items = ["shared first fixture", tail].map { text -> NSPasteboardItem in
                let item = NSPasteboardItem()
                XCTAssertTrue(item.setString(text, forType: .string))
                XCTAssertTrue(item.setData(Data("{\\rtf1 \(text)}".utf8), forType: .rtf))
                return item
            }
            pasteboard.clearContents()
            try requirePasteboardWrite(items, to: pasteboard)
            monitor.poll()
        }

        try pollRichItems(tail: "original second fixture")
        await fulfillment(of: [firstCopy], timeout: 1)
        pasteboard.clearContents()
        try requirePasteboardWrite([makeMarkedTranscript()], to: pasteboard)
        monitor.poll()
        await fulfillment(of: [transcript], timeout: 1)

        typedExpectation = changedCopy
        try pollRichItems(tail: "different second fixture")
        await fulfillment(of: [changedCopy], timeout: 1)
        XCTAssertEqual(captured, [
            ["shared first fixture", "original second fixture"],
            ["shared first fixture", "different second fixture"]
        ])
    }

    func testIdenticalMultiItemRichTextRestoreIsSkippedAndRecopyIsCaptured() async throws {
        let pasteboard = try requireNamedPasteboard()
        defer { pasteboard.releaseGlobally() }
        let firstCopy = expectation(description: "original multi-item rich text captured")
        let transcript = expectation(description: "temporary text observed")
        let restored = expectation(description: "identical multi-item restore must not be captured")
        restored.isInverted = true
        let recopy = expectation(description: "explicit multi-item recopy captured")
        var typedExpectation = firstCopy
        var capturedCounts: [Int] = []
        let monitor = PasteboardMonitor(
            pasteboard: SystemPasteboardReader(pasteboard: pasteboard),
            scheduler: FakePasteboardPollScheduler(),
            onExternalText: { _ in transcript.fulfill() },
            onExternalChange: {
                capturedCounts.append($0.changeCount)
                typedExpectation.fulfill()
            }
        )
        monitor.start()
        defer { monitor.stop() }

        func pollRichItems() throws {
            let items = ["first fixture", "second fixture"].map { text -> NSPasteboardItem in
                let item = NSPasteboardItem()
                XCTAssertTrue(item.setString(text, forType: .string))
                XCTAssertTrue(item.setData(Data("{\\rtf1 \(text)}".utf8), forType: .rtf))
                return item
            }
            pasteboard.clearContents()
            try requirePasteboardWrite(items, to: pasteboard)
            monitor.poll()
        }

        try pollRichItems()
        await fulfillment(of: [firstCopy], timeout: 1)
        pasteboard.clearContents()
        try requirePasteboardWrite([makeMarkedTranscript()], to: pasteboard)
        monitor.poll()
        await fulfillment(of: [transcript], timeout: 1)

        typedExpectation = restored
        try pollRichItems()
        await fulfillment(of: [restored], timeout: 0.15)

        typedExpectation = recopy
        try pollRichItems()
        await fulfillment(of: [recopy], timeout: 1)
        XCTAssertEqual(capturedCounts.count, 2)
    }

    func testDifferentSecondPlainTextItemAfterTranscriptIsCaptured() async throws {
        let pasteboard = try requireNamedPasteboard()
        defer { pasteboard.releaseGlobally() }
        let firstCopy = expectation(description: "original multi-item plain text captured")
        let transcript = expectation(description: "temporary text observed")
        let changedCopy = expectation(description: "copy with a different second item captured")
        var capturedCounts: [Int] = []
        var textExpectation = firstCopy
        let monitor = PasteboardMonitor(
            pasteboard: SystemPasteboardReader(pasteboard: pasteboard),
            scheduler: FakePasteboardPollScheduler(),
            onExternalText: {
                capturedCounts.append($0.changeCount)
                textExpectation.fulfill()
            },
            onExternalChange: { _ in XCTFail("plain text must not be routed as a typed change") }
        )
        monitor.start()
        defer { monitor.stop() }

        func pollPlainItems(tail: String) throws {
            let items = ["shared first fixture", tail].map { text -> NSPasteboardItem in
                let item = NSPasteboardItem()
                XCTAssertTrue(item.setString(text, forType: .string))
                return item
            }
            pasteboard.clearContents()
            try requirePasteboardWrite(items, to: pasteboard)
            monitor.poll()
        }

        try pollPlainItems(tail: "original second fixture")
        await fulfillment(of: [firstCopy], timeout: 1)
        textExpectation = transcript
        pasteboard.clearContents()
        try requirePasteboardWrite([makeMarkedTranscript()], to: pasteboard)
        monitor.poll()
        await fulfillment(of: [transcript], timeout: 1)

        textExpectation = changedCopy
        try pollPlainItems(tail: "different second fixture")
        await fulfillment(of: [changedCopy], timeout: 1)
        XCTAssertEqual(capturedCounts.count, 3)
        XCTAssertEqual(Set(capturedCounts).count, 3)
    }

    func testIdenticalMultiItemPlainTextRestoreIsSkippedAndRecopyIsCaptured() async throws {
        let pasteboard = try requireNamedPasteboard()
        defer { pasteboard.releaseGlobally() }
        let firstCopy = expectation(description: "original multi-item plain text captured")
        let transcript = expectation(description: "temporary text observed")
        let restored = expectation(description: "identical multi-item restore must not be captured")
        restored.isInverted = true
        let recopy = expectation(description: "explicit multi-item recopy captured")
        var capturedCounts: [Int] = []
        var textExpectation = firstCopy
        let monitor = PasteboardMonitor(
            pasteboard: SystemPasteboardReader(pasteboard: pasteboard),
            scheduler: FakePasteboardPollScheduler(),
            onExternalText: {
                capturedCounts.append($0.changeCount)
                textExpectation.fulfill()
            },
            onExternalChange: { _ in XCTFail("plain text must not be routed as a typed change") }
        )
        monitor.start()
        defer { monitor.stop() }

        func pollPlainItems() throws {
            let items = ["first fixture", "second fixture"].map { text -> NSPasteboardItem in
                let item = NSPasteboardItem()
                XCTAssertTrue(item.setString(text, forType: .string))
                return item
            }
            pasteboard.clearContents()
            try requirePasteboardWrite(items, to: pasteboard)
            monitor.poll()
        }

        try pollPlainItems()
        await fulfillment(of: [firstCopy], timeout: 1)
        textExpectation = transcript
        pasteboard.clearContents()
        try requirePasteboardWrite([makeMarkedTranscript()], to: pasteboard)
        monitor.poll()
        await fulfillment(of: [transcript], timeout: 1)

        textExpectation = restored
        try pollPlainItems()
        await fulfillment(of: [restored], timeout: 0.15)

        textExpectation = recopy
        try pollPlainItems()
        await fulfillment(of: [recopy], timeout: 1)
        XCTAssertEqual(capturedCounts.count, 3)
        XCTAssertEqual(Set(capturedCounts).count, 3)
    }

    func testTypedChangeClassifiesWebURLAndFinderFileWithoutReadingFileBytes() throws {
        let pasteboard = try requireNamedPasteboard()
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("fixture.txt")
        let sourceBytes = Data("source remains outside Qipli".utf8)
        try sourceBytes.write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let urlItem = NSPasteboardItem()
        XCTAssertTrue(urlItem.setString("https://example.com/docs?q=1", forType: .URL))
        let fileItem = NSPasteboardItem()
        XCTAssertTrue(fileItem.setString(sourceURL.absoluteString, forType: .fileURL))
        try requirePasteboardWrite([urlItem, fileItem], to: pasteboard)

        let change = try XCTUnwrap(SystemPasteboardReader(pasteboard: pasteboard).typedChange(changeCount: 44))
        XCTAssertTrue(change.imageItems.isEmpty)
        XCTAssertEqual(change.referenceItems.map(\.order), [0, 1])
        XCTAssertEqual(change.referenceItems.map(\.kind), [.url, .fileReference])
        XCTAssertEqual(change.referenceItems.first?.metadata.domain, "example.com")
        XCTAssertEqual(change.referenceItems.last?.metadata.displayName, "fixture.txt")
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBytes)
    }

    func testTypedChangeKeepsImageAndURLRepresentationsFromOnePasteboardItem() throws {
        let pasteboard = try requireNamedPasteboard()
        let item = NSPasteboardItem()
        XCTAssertTrue(item.setData(Data([0x01, 0x02]), forType: .tiff))
        XCTAssertTrue(item.setString("https://example.com/image", forType: .URL))
        try requirePasteboardWrite([item], to: pasteboard)

        let change = try XCTUnwrap(SystemPasteboardReader(pasteboard: pasteboard).typedChange(changeCount: 46))
        XCTAssertEqual(change.imageItems.map(\.order), [0])
        XCTAssertEqual(change.referenceItems.map(\.order), [0])
        XCTAssertEqual(change.referenceItems.first?.urlString, "https://example.com/image")
    }

    func testTypedChangeCapturesCanonicalTextAndOnlyAllowlistedRichRepresentations() throws {
        let pasteboard = try requireNamedPasteboard()
        let item = NSPasteboardItem()
        XCTAssertTrue(item.setString("formatted fixture", forType: .string))
        XCTAssertTrue(item.setData(Data("{\\rtf1 formatted fixture}".utf8), forType: .rtf))
        XCTAssertTrue(item.setData(Data("<p>formatted fixture</p>".utf8), forType: .html))
        XCTAssertTrue(item.setData(
            Data("ignored".utf8),
            forType: NSPasteboard.PasteboardType(rawValue: "com.apple.webarchive")
        ))
        try requirePasteboardWrite([item], to: pasteboard)

        let change = try XCTUnwrap(SystemPasteboardReader(pasteboard: pasteboard).typedChange(changeCount: 47))

        XCTAssertEqual(change.canonicalText, "formatted fixture")
        XCTAssertEqual(change.richTextItems.count, 1)
        XCTAssertEqual(change.richTextItems[0].representations.map(\.typeIdentifier), ["public.rtf", "public.html"])
        XCTAssertTrue(change.imageItems.isEmpty)
        XCTAssertTrue(change.referenceItems.isEmpty)
    }

    func testRichTextCaptureRejectsOversizedCandidateWithoutKeepingPartialPayload() {
        let item = NSPasteboardItem()
        XCTAssertTrue(item.setString("formatted fixture", forType: .string))
        XCTAssertTrue(item.setData(Data("small".utf8), forType: .rtf))
        XCTAssertTrue(item.setData(
            Data(repeating: 1, count: HistoryRichTextStoragePolicy.production.maxRepresentationBytes + 1),
            forType: .html
        ))

        let result = SystemPasteboardReader.richTextCapture(from: [item])

        XCTAssertEqual(result.canonicalText, "formatted fixture")
        XCTAssertTrue(result.rejected)
        XCTAssertTrue(result.items.isEmpty)
    }

    func testRichTextCapturePreservesPerItemCanonicalTextAndSourceOrder() {
        let first = NSPasteboardItem()
        XCTAssertTrue(first.setString("first", forType: .string))
        XCTAssertTrue(first.setData(Data("rtf-first".utf8), forType: .rtf))
        let second = NSPasteboardItem()
        XCTAssertTrue(second.setString("second", forType: .string))
        XCTAssertTrue(second.setData(Data("html-second".utf8), forType: .html))

        let result = SystemPasteboardReader.richTextCapture(from: [first, second])

        XCTAssertFalse(result.rejected)
        XCTAssertEqual(result.items.map(\.order), [0, 1])
        XCTAssertEqual(result.items.map(\.canonicalText), ["first", "second"])
        XCTAssertEqual(result.items.flatMap { $0.representations }.map(\.typeIdentifier), [
            "public.rtf", "public.html"
        ])
    }

    func testRichTextRoutingDoesNotHideMixedImageCapture() {
        let change = PasteboardTypedChange(
            changeCount: 1,
            canonicalText: "formatted",
            imageItems: [ManagedImageCaptureItem(order: 0, representations: [
                ManagedImageCaptureRepresentation(typeIdentifier: "public.png", data: Data([1]))
            ])],
            richTextItems: [HistoryRichTextCaptureItem(
                order: 0,
                canonicalText: "formatted",
                representations: [HistoryRichTextCaptureRepresentation(
                    typeIdentifier: "public.rtf",
                    data: Data("rtf".utf8)
                )]
            )]
        )

        XCTAssertFalse(ApplicationShellPasteboardRouting.shouldCaptureRichText(change))
    }

    func testPlainTextThatLooksLikeURLDoesNotBecomeURLReference() throws {
        let pasteboard = try requireNamedPasteboard()
        let item = NSPasteboardItem()
        XCTAssertTrue(item.setString("https://example.com/plain-text", forType: .string))
        try requirePasteboardWrite([item], to: pasteboard)

        XCTAssertNil(SystemPasteboardReader(pasteboard: pasteboard).typedChange(changeCount: 45))
    }

    func testTypedWriterPublishesURLAndFileURLRepresentations() throws {
        let pasteboard = try requireNamedPasteboard()
        let probe = NSPasteboardItem()
        XCTAssertTrue(probe.setString("pasteboard probe", forType: .string))
        try requirePasteboardWrite([probe], to: pasteboard)
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

    private func requireNamedPasteboard() throws -> NSPasteboard {
        try unwrapNamedPasteboard(NSPasteboard(name: NSPasteboard.Name("QipliTests.\(UUID().uuidString)")))
    }

    private func makeMarkedTranscript() -> NSPasteboardItem {
        let item = NSPasteboardItem()
        XCTAssertTrue(item.setString("dictation fixture", forType: .string))
        for marker in ["org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType"] {
            XCTAssertTrue(item.setData(Data(), forType: NSPasteboard.PasteboardType(marker)))
        }
        return item
    }

    private func requirePasteboardWrite(
        _ objects: [NSPasteboardWriting],
        to pasteboard: NSPasteboard
    ) throws {
        guard pasteboard.writeObjects(objects) else {
            throw XCTSkip("Pasteboard writes are unavailable in this test environment")
        }
    }

    private func unwrapNamedPasteboard(_ pasteboard: NSPasteboard) throws -> NSPasteboard {
        pasteboard
    }

    private func unwrapNamedPasteboard(_ pasteboard: NSPasteboard?) throws -> NSPasteboard {
        guard let pasteboard else {
            throw XCTSkip("Named pasteboards are unavailable in this test environment")
        }
        return pasteboard
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

    func itemTexts() -> [String]? { nil }

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

    func typedChange(changeCount: Int) -> PasteboardTypedChange? {
        guard let pendingChange else { return nil }
        self.pendingChange = nil
        return PasteboardTypedChange(changeCount: changeCount, imageItems: pendingChange.imageItems)
    }
}

private final class BlockingTypedPasteboard: PasteboardReading, TypedPasteboardReading, @unchecked Sendable {
    private let lock = NSLock()
    private let firstReadGate = DispatchSemaphore(value: 0)
    private var storedChangeCount: Int
    private var marker: UInt8 = 0
    private var readCount = 0
    var onFirstReadStarted: (() -> Void)?

    init(changeCount: Int) {
        storedChangeCount = changeCount
    }

    var changeCount: Int {
        lock.withLock { storedChangeCount }
    }

    func textValue() -> String? { nil }

    func itemTexts() -> [String]? { nil }

    func publishImageChange(marker: UInt8) {
        lock.withLock {
            storedChangeCount += 1
            self.marker = marker
        }
    }

    func releaseFirstRead() {
        firstReadGate.signal()
    }

    func typedChange(changeCount: Int) -> PasteboardTypedChange? {
        let shouldBlock = lock.withLock { () -> Bool in
            readCount += 1
            return readCount == 1
        }
        if shouldBlock {
            onFirstReadStarted?()
            firstReadGate.wait()
        }
        let capturedMarker = lock.withLock { marker }
        return PasteboardTypedChange(
            changeCount: changeCount,
            imageItems: [ManagedImageCaptureItem(
                order: 0,
                representations: [ManagedImageCaptureRepresentation(
                    typeIdentifier: "public.png",
                    data: Data([capturedMarker])
                )]
            )]
        )
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
