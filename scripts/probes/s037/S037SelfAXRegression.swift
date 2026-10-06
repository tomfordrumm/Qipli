#if DEBUG
import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Exercises the self-process AX/AppKit queue regression without physical input.
@MainActor
enum S037SelfAXRegression {
    private static var window: NSWindow?

    static func run(completion: @escaping (String) -> Void) {
        NSApp.setActivationPolicy(.regular)
        let fixture = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 150), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        fixture.title = "S037 synthetic self-AX regression"
        fixture.isReleasedWhenClosed = false
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 150))
        editor.string = "ghbdtn   "
        editor.isRichText = false
        editor.identifier = NSUserInterfaceItemIdentifier("s037.freshword.synthetic.editor")
        editor.setSelectedRange(NSRange(location: 9, length: 0))
        fixture.contentView = editor
        window = fixture
        fixture.center()
        fixture.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        fixture.makeFirstResponder(editor)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
                  let rawID = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
                finish(false, completion: completion)
                return
            }
            let sourceID = unsafeBitCast(rawID, to: CFString.self) as String
            DispatchQueue(label: "com.qipli.s037.self-ax-regression").async {
                guard let snapshot = S037ManualAXWorker.readFocusedTarget(),
                      snapshot.range.location == 9, snapshot.range.length == 0 else {
                    DispatchQueue.main.async { finish(false, completion: completion) }
                    return
                }
                let (passed, _) = S037ManualAXWorker.selectBoundedSixUnitRange(snapshot, range: CFRange(location: 0, length: 6), sourceID: sourceID, isCurrent: { true })
                DispatchQueue.main.async { finish(passed, completion: completion) }
            }
        }
    }

    private static func finish(_ passed: Bool, completion: (String) -> Void) {
        window?.orderOut(nil)
        window = nil
        completion("selfAXMainOwnership=\(passed ? "PASS" : "FAIL"); boundedSixUnitReadAndSelection=\(passed); noKeyboardDispatch=true")
    }
}
#endif
