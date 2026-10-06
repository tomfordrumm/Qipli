import AppKit
import XCTest
@testable import Qipli

@MainActor
final class LayoutCorrectionClipboardTests: XCTestCase {
    private func board() -> NSPasteboard { NSPasteboard(name: .init("qipli-correction-test-" + UUID().uuidString)) }

    func testRestorePreservesMultipleItemsAndBinaryRepresentations() throws {
        let board = board()
        defer { board.releaseGlobally() }
        let binaryType = NSPasteboard.PasteboardType("com.qipli.test.synthetic")
        let first = NSPasteboardItem(), second = NSPasteboardItem()
        first.setString("synthetic original", forType: .string)
        first.setData(Data([0, 255, 3, 0]), forType: binaryType)
        second.setString("synthetic second", forType: .string)
        board.clearContents(); XCTAssertTrue(board.writeObjects([first, second]))
        var selfWrites: [Int] = []
        let lease = try CorrectionClipboardLease(text: "synthetic converted", pasteboard: board, registerSelfWrite: { selfWrites.append($0) })
        XCTAssertEqual(board.string(forType: .string), "synthetic converted")
        XCTAssertTrue(lease.isOwned())
        lease.restore()
        let restored = try XCTUnwrap(board.pasteboardItems)
        XCTAssertEqual(restored.count, 2)
        XCTAssertEqual(restored[0].string(forType: .string), "synthetic original")
        XCTAssertEqual(restored[0].data(forType: binaryType), Data([0, 255, 3, 0]))
        XCTAssertEqual(restored[1].string(forType: .string), "synthetic second")
        XCTAssertTrue(selfWrites.contains(board.changeCount))
        XCTAssertFalse(lease.isOwned())
        let count = board.changeCount
        lease.restore()
        XCTAssertEqual(board.changeCount, count)
    }

    func testNewerExternalCopyIsNotOverwrittenByRestore() throws {
        let board = board()
        defer { board.releaseGlobally() }
        board.clearContents(); board.setString("synthetic original", forType: .string)
        var writes: [Int] = []
        let lease = try CorrectionClipboardLease(text: "synthetic converted", pasteboard: board, registerSelfWrite: { writes.append($0) })
        board.clearContents(); board.setString("synthetic external copy", forType: .string)
        let externalCount = board.changeCount
        let registeredCount = writes.count
        XCTAssertFalse(lease.isOwned())
        lease.restore()
        XCTAssertEqual(board.changeCount, externalCount)
        XCTAssertEqual(board.string(forType: .string), "synthetic external copy")
        XCTAssertEqual(writes.count, registeredCount)
    }

    func testEmptyClipboardIsRestoredToEmpty() throws {
        let board = board()
        defer { board.releaseGlobally() }
        board.clearContents()
        let lease = try CorrectionClipboardLease(text: "synthetic", pasteboard: board, registerSelfWrite: { _ in })
        lease.restore()
        XCTAssertTrue((board.pasteboardItems ?? []).isEmpty)
    }

    func testOversizedSnapshotIsRejectedBeforeAnyClipboardMutation() throws {
        let board = board()
        defer { board.releaseGlobally() }
        let items = (0..<65).map { index in
            let item = NSPasteboardItem(); item.setString("synthetic \(index)", forType: .string); return item
        }
        board.clearContents(); XCTAssertTrue(board.writeObjects(items))
        let before = board.changeCount
        var writes = 0
        XCTAssertThrowsError(try CorrectionClipboardLease(text: "synthetic", pasteboard: board, registerSelfWrite: { _ in writes += 1 })) {
            XCTAssertEqual($0 as? CorrectionAXError, .limit)
        }
        XCTAssertEqual(board.changeCount, before)
        XCTAssertEqual(board.pasteboardItems?.count, 65)
        XCTAssertEqual(writes, 0)
    }

    func testUnreadableRepresentationIsRejectedWithoutChangingClipboard() throws {
        let board = board()
        defer { board.releaseGlobally() }
        let provider = UnavailableCorrectionDataProvider()
        let missing = NSPasteboard.PasteboardType("com.qipli.test.unavailable")
        let item = NSPasteboardItem()
        item.setString("synthetic original", forType: .string)
        item.setDataProvider(provider, forTypes: [missing])
        board.clearContents(); XCTAssertTrue(board.writeObjects([item]))
        let before = board.changeCount
        var writes = 0
        XCTAssertThrowsError(try CorrectionClipboardLease(text: "synthetic", pasteboard: board, registerSelfWrite: { _ in writes += 1 })) {
            XCTAssertEqual($0 as? CorrectionAXError, .unavailable)
        }
        XCTAssertEqual(board.changeCount, before)
        XCTAssertEqual(board.string(forType: .string), "synthetic original")
        XCTAssertTrue(board.pasteboardItems?.first?.types.contains(missing) == true)
        XCTAssertEqual(writes, 0)
        withExtendedLifetime(provider) {}
    }

    func testTemporaryAndRestoredClipboardChangesNeverBecomeHistoryCapture() throws {
        let board = board()
        defer { board.releaseGlobally() }
        board.clearContents(); board.setString("synthetic original", forType: .string)
        var captures = 0
        let monitor = PasteboardMonitor(pasteboard: SystemPasteboardReader(pasteboard: board), onExternalText: { _ in captures += 1 })
        monitor.start(); defer { monitor.stop() }
        let lease = try CorrectionClipboardLease(text: "synthetic correction", pasteboard: board,
            registerSelfWrite: { monitor.registerSelfWrite(changeCount: $0) })
        monitor.poll()
        lease.restore()
        monitor.poll()
        XCTAssertEqual(captures, 0)
        board.clearContents(); board.setString("synthetic next external", forType: .string)
        monitor.poll()
        XCTAssertEqual(captures, 1)
    }
}

private final class UnavailableCorrectionDataProvider: NSObject, NSPasteboardItemDataProvider {
    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {}
}
