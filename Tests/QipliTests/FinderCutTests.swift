import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Qipli

@MainActor
final class FinderCutTests: XCTestCase {
    func testCompactPresentationReopensWithoutAcceptingOldDismissal() {
        let model = FinderCutPresentationModel()
        let geometry = PasteStackCompactGeometry.make(
            screenFrame: NSRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 875),
            safeAreaInsets: NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        ).addingFinderCutFilenameRow()
        var dismissals: [Int] = []
        model.onDismiss = { dismissals.append($0) }
        model.beginSession(geometry: geometry)
        XCTAssertEqual(model.state, .compact)
        XCTAssertEqual(model.compactGeometry, geometry)
        model.requestDismissal()
        model.requestDismissal()
        XCTAssertEqual(dismissals.count, 1)
        model.beginSession(geometry: geometry)
        model.finishDismissal(token: dismissals[0])
        XCTAssertEqual(model.state, .compact)
        model.requestDismissal()
        model.finishDismissal(token: dismissals[1])
        XCTAssertEqual(model.state, .hidden)
        XCTAssertNil(model.compactGeometry)
    }

    func testCompactScreenChangeDoesNotInvalidatePendingDismissal() {
        let model = FinderCutPresentationModel()
        func geometry(_ width: CGFloat) -> PasteStackCompactGeometry {
            PasteStackCompactGeometry.make(
                screenFrame: NSRect(x: 0, y: 0, width: width, height: 900),
                visibleFrame: NSRect(x: 0, y: 0, width: width, height: 875),
                safeAreaInsets: NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
            ).addingFinderCutFilenameRow()
        }
        model.beginSession(geometry: geometry(1440))
        model.updateGeometry(geometry(1920))
        XCTAssertEqual(model.state, .compact)
        XCTAssertEqual(model.compactGeometry, geometry(1920))
        model.requestDismissal()
        let token = model.generation
        model.updateGeometry(geometry(1440))
        model.finishDismissal(token: token)
        XCTAssertEqual(model.state, .hidden)
    }

    func testCompactStatusReplacesFilenameForFailureAndDispatchWithoutClaimingMoveSuccess() {
        let selection = FinderCutSelection(urls: [URL(fileURLWithPath: "/tmp/synthetic-cut-example.txt")])
        XCTAssertNil(FinderCutSessionState.preparing(selection).compactStatusMessage)
        XCTAssertNil(FinderCutSessionState.ready(selection).compactStatusMessage)
        XCTAssertEqual(FinderCutSessionState.failed(selection, "Synthetic failure").compactStatusMessage,
                       "Move unavailable. Cut again.")
        XCTAssertEqual(FinderCutSessionState.blockedByPasteStack.compactStatusMessage, "Finish Paste Stack first.")
        XCTAssertEqual(FinderCutSessionState.handedOff(selection).compactStatusMessage, "Command sent to Finder")
        XCTAssertTrue(FinderCutSessionState.handedOff(selection).isHandedOff)
        XCTAssertFalse(FinderCutSessionState.ready(selection).isHandedOff)
    }

    func testCommandXPreparesOnlyAConfirmedFinderSelectionAndSuppressesExactSelfWrite() {
        let source = temporaryFixture()
        defer { try? FileManager.default.removeItem(at: source) }
        let context = FakeFinderContextProvider(context: FinderCutContext(
            applicationBundleIdentifier: SystemFinderContextProvider.finderBundleIdentifier,
            focusedRole: kAXListRole,
            isTextField: false,
            selectedFileURLs: [source],
            isInsertionContext: true
        ))
        let pasteboard = FakeFinderCutPasteboard(changeCount: 10, fileURLs: [source])
        let copy = FakeCopyDispatcher()
        let move = FakeMoveDispatcher()
        var selfWrites: [Int] = []
        let controller = FinderCutSessionController(
            contextProvider: context,
            pasteboard: pasteboard,
            copyCommandDispatcher: copy,
            moveCommandDispatcher: move,
            registerSelfWrite: { selfWrites.append($0) },
            stackIsActive: { false }
        )

        controller.handleCommandX(isRepeat: false)

        XCTAssertEqual(copy.count, 1)
        XCTAssertEqual(controller.state, .preparing(FinderCutSelection(urls: [source])))
        XCTAssertTrue(controller.handleExternalPasteboardChange(changeCount: 11))
        XCTAssertEqual(controller.state, .ready(FinderCutSelection(urls: [source])))
        XCTAssertEqual(selfWrites, [11])
    }

    func testTextFieldAndMismatchedClipboardNeverCreateCutSession() {
        let source = temporaryFixture()
        defer { try? FileManager.default.removeItem(at: source) }
        let textContext = FakeFinderContextProvider(context: FinderCutContext(
            applicationBundleIdentifier: SystemFinderContextProvider.finderBundleIdentifier,
            focusedRole: kAXTextFieldRole,
            isTextField: true,
            selectedFileURLs: [source],
            isInsertionContext: false
        ))
        let textCopy = FakeCopyDispatcher()
        let textController = FinderCutSessionController(
            contextProvider: textContext,
            pasteboard: FakeFinderCutPasteboard(changeCount: 1, fileURLs: [source]),
            copyCommandDispatcher: textCopy,
            moveCommandDispatcher: FakeMoveDispatcher(),
            stackIsActive: { false }
        )
        textController.handleCommandX(isRepeat: false)
        XCTAssertEqual(textCopy.count, 0)
        XCTAssertEqual(textController.state, .idle)

        let sourceContext = FakeFinderContextProvider(context: FinderCutContext(
            applicationBundleIdentifier: SystemFinderContextProvider.finderBundleIdentifier,
            focusedRole: kAXListRole,
            isTextField: false,
            selectedFileURLs: [source],
            isInsertionContext: true
        ))
        let mismatchPasteboard = FakeFinderCutPasteboard(
            changeCount: 20,
            fileURLs: [temporaryURL(name: "different-fixture.txt")]
        )
        let mismatchCopy = FakeCopyDispatcher()
        let mismatchController = FinderCutSessionController(
            contextProvider: sourceContext,
            pasteboard: mismatchPasteboard,
            copyCommandDispatcher: mismatchCopy,
            moveCommandDispatcher: FakeMoveDispatcher(),
            stackIsActive: { false }
        )
        mismatchController.handleCommandX(isRepeat: false)
        XCTAssertFalse(mismatchController.handleExternalPasteboardChange(changeCount: 21))
        XCTAssertEqual(mismatchController.state, .idle)
    }

    func testMoveIsAdmittedOnlyForFinderDestinationAndRepeatCannotDispatchTwice() async throws {
        let source = temporaryFixture()
        defer { try? FileManager.default.removeItem(at: source) }
        let context = FakeFinderContextProvider(context: FinderCutContext(
            applicationBundleIdentifier: SystemFinderContextProvider.finderBundleIdentifier,
            focusedRole: kAXListRole,
            isTextField: false,
            selectedFileURLs: [source],
            isInsertionContext: true
        ))
        let move = FakeMoveDispatcher()
        let controller = makeController(
            context: context,
            selection: FinderCutSelection(urls: [source]),
            move: move
        )
        context.context = FinderCutContext(
            applicationBundleIdentifier: SystemFinderContextProvider.finderBundleIdentifier,
            focusedRole: kAXListRole,
            isTextField: false,
            selectedFileURLs: [],
            isInsertionContext: true
        )
        controller.refreshDestinationAdmission()
        controller.inputGate.update(isReady: true, destinationIsValid: true)
        XCTAssertEqual(controller.inputGate.admitPaste(isRepeat: false), .consumeAndDispatch)
        let hidden = expectation(description: "Handoff acknowledgement closes")
        controller.hidePanel = { hidden.fulfill() }

        controller.dispatchMove()

        XCTAssertEqual(move.count, 1)
        XCTAssertEqual(controller.state, .handedOff(FinderCutSelection(urls: [source])))
        XCTAssertEqual(controller.inputGate.admitPaste(isRepeat: true), .consume)
        XCTAssertEqual(controller.inputGate.admitPaste(isRepeat: false), .consume)
        await fulfillment(of: [hidden], timeout: 2)
        XCTAssertEqual(controller.inputGate.admitPaste(isRepeat: true), .consume)
    }

    func testHandoffDismissalDoesNotHideNewCutSession() async throws {
        let source = temporaryFixture()
        defer { try? FileManager.default.removeItem(at: source) }
        let context = FakeFinderContextProvider(context: FinderCutContext(
            applicationBundleIdentifier: SystemFinderContextProvider.finderBundleIdentifier,
            focusedRole: kAXListRole,
            isTextField: false,
            selectedFileURLs: [source],
            isInsertionContext: true
        ))
        let selection = FinderCutSelection(urls: [source])
        let controller = makeController(context: context, selection: selection)
        context.context = FinderCutContext(
            applicationBundleIdentifier: SystemFinderContextProvider.finderBundleIdentifier,
            focusedRole: kAXListRole,
            isTextField: false,
            selectedFileURLs: [],
            isInsertionContext: true
        )
        controller.refreshDestinationAdmission()
        controller.dispatchMove()
        XCTAssertEqual(controller.state, .handedOff(selection))
        let hidden = expectation(description: "New cut remains visible")
        hidden.isInverted = true
        controller.hidePanel = { hidden.fulfill() }
        controller.prepare(selection: selection)
        await fulfillment(of: [hidden], timeout: 0.9)
        XCTAssertEqual(controller.state, .preparing(selection))
        controller.hidePanel = {}
        controller.cancel()
    }

    func testStackConflictBlocksCutAndCancelClearsTheGate() {
        let context = FakeFinderContextProvider(context: FinderCutContext(
            applicationBundleIdentifier: SystemFinderContextProvider.finderBundleIdentifier,
            focusedRole: kAXListRole,
            isTextField: false,
            selectedFileURLs: [temporaryURL(name: "source-fixture.txt")],
            isInsertionContext: true
        ))
        let copy = FakeCopyDispatcher()
        let controller = FinderCutSessionController(
            contextProvider: context,
            pasteboard: FakeFinderCutPasteboard(changeCount: 1, fileURLs: []),
            copyCommandDispatcher: copy,
            moveCommandDispatcher: FakeMoveDispatcher(),
            stackIsActive: { true }
        )

        controller.handleCommandX(isRepeat: false)

        XCTAssertEqual(copy.count, 0)
        XCTAssertEqual(controller.state, .blockedByPasteStack)
        controller.cancel()
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(controller.inputGate.admitPaste(isRepeat: false), .passThrough)
    }

    func testEventTapObservesCommandXButConsumesOnlyAdmittedFinderMove() throws {
        let commandX = try makeKeyEvent(keyCode: CGKeyCode(kVK_ANSI_X), flags: .maskCommand)
        XCTAssertEqual(
            CGEventTapAdapter.consumedAction(
                type: .keyDown,
                event: commandX,
                stackSessionIsActive: false
            ),
            .observeFinderCutCommand
        )

        let commandV = try makeKeyEvent(keyCode: CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
        XCTAssertEqual(
            CGEventTapAdapter.consumedAction(
                type: .keyDown,
                event: commandV,
                stackSessionIsActive: false,
                finderCutPasteInterception: { _ in .consumeAndDispatch }
            ),
            .dispatchFinderCutMove
        )
        XCTAssertNil(CGEventTapAdapter.consumedAction(
            type: .keyDown,
            event: commandV,
            stackSessionIsActive: false,
            finderCutPasteInterception: { _ in .passThrough }
        ))
    }

    func testDestinationRefreshCannotReopenSynchronouslyReservedMove() {
        let gate = FinderCutInputGate()
        gate.update(isReady: true, destinationIsValid: true)

        XCTAssertEqual(gate.admitPaste(isRepeat: false), .consumeAndDispatch)
        gate.update(isReady: true, destinationIsValid: true)
        XCTAssertEqual(gate.admitPaste(isRepeat: false), .consume)

        gate.releaseDispatchReservation(destinationIsValid: false)
        XCTAssertEqual(gate.admitPaste(isRepeat: false), .passThrough)
    }

    func testExternalChangeBeforeDispatchInvalidatesCutWithoutMovingFiles() {
        let source = temporaryFixture()
        defer { try? FileManager.default.removeItem(at: source) }
        let sourceContext = FakeFinderContextProvider(context: FinderCutContext(
            applicationBundleIdentifier: SystemFinderContextProvider.finderBundleIdentifier,
            focusedRole: kAXListRole,
            isTextField: false,
            selectedFileURLs: [source],
            isInsertionContext: true
        ))
        let destinationContext = FinderCutContext(
            applicationBundleIdentifier: SystemFinderContextProvider.finderBundleIdentifier,
            focusedRole: kAXListRole,
            isTextField: false,
            selectedFileURLs: [],
            isInsertionContext: true
        )
        let pasteboard = FakeFinderCutPasteboard(changeCount: 1, fileURLs: [source])
        let move = FakeMoveDispatcher()
        let paste = FakePasteDispatcher()
        let controller = FinderCutSessionController(
            contextProvider: sourceContext,
            pasteboard: pasteboard,
            copyCommandDispatcher: FakeCopyDispatcher(),
            moveCommandDispatcher: move,
            pasteCommandDispatcher: paste,
            stackIsActive: { false }
        )
        controller.prepare(selection: FinderCutSelection(urls: [source]))
        XCTAssertTrue(controller.handleExternalPasteboardChange(changeCount: 2))
        sourceContext.context = destinationContext
        controller.refreshDestinationAdmission()
        pasteboard.changeCount = 3
        _ = controller.inputGate.admitPaste(isRepeat: false)

        controller.dispatchMove()

        XCTAssertEqual(move.count, 0)
        XCTAssertEqual(paste.count, 1)
        XCTAssertEqual(controller.state, .idle)
    }

    func testStalePasteDoesNotReplayIntoAChangedFocusTarget() {
        let source = temporaryFixture()
        defer { try? FileManager.default.removeItem(at: source) }
        let context = FakeFinderContextProvider(context: FinderCutContext(
            applicationBundleIdentifier: SystemFinderContextProvider.finderBundleIdentifier,
            focusedRole: kAXListRole,
            isTextField: false,
            selectedFileURLs: [source],
            isInsertionContext: true
        ))
        let pasteboard = FakeFinderCutPasteboard(changeCount: 1, fileURLs: [source])
        let paste = FakePasteDispatcher()
        let controller = FinderCutSessionController(
            contextProvider: context,
            pasteboard: pasteboard,
            copyCommandDispatcher: FakeCopyDispatcher(),
            moveCommandDispatcher: FakeMoveDispatcher(),
            pasteCommandDispatcher: paste,
            stackIsActive: { false }
        )
        controller.prepare(selection: FinderCutSelection(urls: [source]))
        XCTAssertTrue(controller.handleExternalPasteboardChange(changeCount: 2))
        context.context = FinderCutContext(
            applicationBundleIdentifier: "com.apple.TextEdit",
            focusedRole: kAXTextFieldRole,
            isTextField: true,
            selectedFileURLs: [],
            isInsertionContext: false
        )
        pasteboard.changeCount = 3
        _ = controller.inputGate.admitPaste(isRepeat: false)

        controller.dispatchMove()

        XCTAssertEqual(paste.count, 0)
        XCTAssertEqual(controller.state, .idle)
    }

    func testLateTaggedCopyAfterCancelIsSuppressedOnlyForCurrentFinderSelection() {
        let source = temporaryFixture()
        defer { try? FileManager.default.removeItem(at: source) }
        let context = FakeFinderContextProvider(context: FinderCutContext(
            applicationBundleIdentifier: SystemFinderContextProvider.finderBundleIdentifier,
            focusedRole: kAXListRole,
            isTextField: false,
            selectedFileURLs: [source],
            isInsertionContext: true
        ))
        let pasteboard = FakeFinderCutPasteboard(changeCount: 10, fileURLs: [])
        var selfWrites: [Int] = []
        let controller = FinderCutSessionController(
            contextProvider: context,
            pasteboard: pasteboard,
            copyCommandDispatcher: FakeCopyDispatcher(),
            moveCommandDispatcher: FakeMoveDispatcher(),
            registerSelfWrite: { selfWrites.append($0) },
            stackIsActive: { false }
        )

        controller.handleCommandX(isRepeat: false)
        controller.cancel()
        pasteboard.changeCount = 11
        pasteboard.urls = [source]

        XCTAssertTrue(controller.handleExternalPasteboardChange(changeCount: 11))
        XCTAssertEqual(selfWrites, [11])
        XCTAssertEqual(controller.state, .idle)
    }

    func testCopyCorrelationFailsClosedOutsideFinderEvenForTheSameURLs() {
        let source = temporaryFixture()
        defer { try? FileManager.default.removeItem(at: source) }
        let context = FakeFinderContextProvider(context: FinderCutContext(
            applicationBundleIdentifier: "com.apple.TextEdit",
            focusedRole: kAXListRole,
            isTextField: false,
            selectedFileURLs: [source],
            isInsertionContext: true
        ))
        let pasteboard = FakeFinderCutPasteboard(changeCount: 20, fileURLs: [source])
        let controller = FinderCutSessionController(
            contextProvider: context,
            pasteboard: pasteboard,
            copyCommandDispatcher: FakeCopyDispatcher(),
            moveCommandDispatcher: FakeMoveDispatcher(),
            stackIsActive: { false }
        )

        controller.prepare(selection: FinderCutSelection(urls: [source]))
        pasteboard.changeCount = 21

        XCTAssertFalse(controller.handleExternalPasteboardChange(changeCount: 21))
        XCTAssertEqual(controller.state, .idle)
    }

    private func makeController(
        context: FakeFinderContextProvider,
        selection: FinderCutSelection? = nil,
        copy: FakeCopyDispatcher = FakeCopyDispatcher(),
        move: FakeMoveDispatcher = FakeMoveDispatcher()
    ) -> FinderCutSessionController {
        let selected = selection ?? FinderCutSelection(urls: [temporaryURL(name: "source-fixture.txt")])
        let pasteboard = FakeFinderCutPasteboard(changeCount: 1, fileURLs: selected.urls)
        let controller = FinderCutSessionController(
            contextProvider: context,
            pasteboard: pasteboard,
            copyCommandDispatcher: copy,
            moveCommandDispatcher: move,
            stackIsActive: { false }
        )
        controller.prepare(selection: selected)
        pasteboard.changeCount = 2
        _ = controller.handleExternalPasteboardChange(changeCount: 2)
        return controller
    }

    private func temporaryFixture() -> URL {
        let url = temporaryURL(name: "qipli-s035-fixture.txt")
        try? Data().write(to: url)
        return url
    }

    private func temporaryURL(name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }

    private func makeKeyEvent(keyCode: CGKeyCode, flags: CGEventFlags) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(
            keyboardEventSource: CGEventSource(stateID: .combinedSessionState),
            virtualKey: keyCode,
            keyDown: true
        ))
        event.flags = flags
        return event
    }
}

private final class FakeFinderContextProvider: FinderContextProviding {
    var context: FinderCutContext?

    init(context: FinderCutContext?) {
        self.context = context
    }

    func currentContext() -> FinderCutContext? { context }
}

private final class FakeFinderCutPasteboard: FinderCutPasteboardReading {
    var changeCount: Int
    var urls: [URL]

    init(changeCount: Int, fileURLs: [URL]) {
        self.changeCount = changeCount
        self.urls = fileURLs
    }

    func fileURLs() -> [URL] { urls }
}

private final class FakeCopyDispatcher: TaggedCopyCommandDispatching {
    private(set) var count = 0

    func postTaggedCommandC() -> Bool {
        count += 1
        return true
    }
}

private final class FakeMoveDispatcher: TaggedMoveCommandDispatching {
    private(set) var count = 0

    func postTaggedCommandMove() -> Bool {
        count += 1
        return true
    }
}

private final class FakePasteDispatcher: TaggedPasteCommandDispatching {
    private(set) var count = 0

    func postTaggedCommandV() -> Bool {
        count += 1
        return true
    }
}
