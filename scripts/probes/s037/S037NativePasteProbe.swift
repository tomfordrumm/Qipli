import AppKit
@preconcurrency import ApplicationServices
import Carbon.HIToolbox

/// Two-process synthetic harness. No user document or user text is read or edited.
@main
@MainActor
final class S037NativePasteProbe: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var editor: NSTextView?
    private let fixtureTitle = "Qipli S037 Owned Native Paste Fixture"
    private static let reportURL = URL(fileURLWithPath: "/private/tmp/qipli-s037-native-paste-report.txt")
    private var fixture: NSRunningApplication?
    private var lines: [String] = []
    private var caseIndex = 0
    private var coordinator: LayoutCorrectionCoordinator?
    private let adapter = LayoutCorrectionAXAdapter()
    private var selfWrites = 0
    private var clipboardBefore: [[(String, Data?)]] = []

    static func main() {
        let app = NSApplication.shared
        let delegate = S037NativePasteProbe()
        app.delegate = delegate
        app.setActivationPolicy(CommandLine.arguments.contains("--fixture") ? .regular : .accessory)
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--fixture") { showFixture(); return }
        guard AXIsProcessTrusted() else { finish("nativePaste=SKIPPED accessibility=false"); return }
        adapter.configurePasteboard { [weak self] _ in self?.selfWrites += 1 }
        clipboardBefore = snapshot()
        launchFixture()
    }

    private func launchFixture() {
        let fixtureURL = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Qipli S037 Fixture.app")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["--fixture", "--case", String(caseIndex)]
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: fixtureURL, configuration: configuration) { [weak self] app, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard error == nil, let app else { self.finish("nativePaste=FAIL fixtureLaunch=false"); return }
                self.fixture = app
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.runCase() }
            }
        }
    }

    private func showFixture() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 220),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = fixtureTitle
        window.isReleasedWhenClosed = false
        let editor = NSTextView(frame: NSRect(x: 20, y: 20, width: 580, height: 180))
        editor.isRichText = false
        editor.allowsUndo = true
        editor.setAccessibilityIdentifier("qipli.s037.owned-native-paste")
        let fixtureCase = CommandLine.arguments.last.flatMap(Int.init) ?? 0
        let fixtureSpaces = fixtureCase == 1 ? 0 : 3
        editor.string = "fixture-before ghbdtn" + String(repeating: " ", count: fixtureSpaces) + " fixture-after"
        window.contentView?.addSubview(editor)
        let main = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; main.addItem(appItem)
        let editItem = NSMenuItem(); let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editItem.submenu = editMenu; main.addItem(editItem); NSApp.mainMenu = main
        self.window = window; self.editor = editor
        window.center(); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: 21 + fixtureSpaces, length: 0))
        NSApp.activate(ignoringOtherApps: true)
    }

    private func runCase() {
        guard let fixture, !fixture.isTerminated,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == fixture.processIdentifier else {
            finish("nativePaste=FAIL ownedFixtureFocus=false"); return
        }
        let spaces = caseIndex == 1 ? 0 : 3
        let selected = caseIndex == 2
        let seed = "fixture-before ghbdtn" + String(repeating: " ", count: spaces) + " fixture-after"
        let expected = "fixture-before привет" + String(repeating: " ", count: spaces) + " fixture-after"
        let pid = fixture.processIdentifier
        let application = AXUIElementCreateApplication(pid)
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { finish("nativePaste=FAIL fixtureElement=false"); return }
        let element = raw as! AXUIElement
        var identifier: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifier) == .success,
              identifier as? String == "qipli.s037.owned-native-paste" else { finish("nativePaste=FAIL fixtureIdentity=false"); return }
        var range = selected ? CFRange(location: 15, length: 6) : CFRange(location: 21 + spaces, length: 0)
        guard let value = AXValueCreate(.cfRange, &range),
              AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success else {
            finish("nativePaste=FAIL fixtureSelection=false"); return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [self] in
            let ledger = CorrectionInputLedger()
            let tick = DispatchTime.now().uptimeNanoseconds - 10_000
            for index in 0..<(6 + spaces) {
                ledger.noteKeyDown(timestamp: tick + UInt64(index), sourceID: "A", targetPID: pid,
                    expectedUTF16Units: 1, isSpace: index >= 6, isExternal: true)
            }
            let pairs = Array(zip(Array("ghbdtn"), Array("привет")))
            let a = Dictionary(uniqueKeysWithValues: pairs.enumerated().map { (CorrectionPhysicalKey(keyCode: UInt16($0.offset), level: 0), String($0.element.0)) })
            let b = Dictionary(uniqueKeysWithValues: pairs.enumerated().map { (CorrectionPhysicalKey(keyCode: UInt16($0.offset), level: 0), String($0.element.1)) })
            let sources = [CorrectionSource(id: "A", name: "Synthetic A", isCurrent: true, keyMap: a),
                           CorrectionSource(id: "B", name: "Synthetic B", isCurrent: false, keyMap: b)]
            let coordinator = LayoutCorrectionCoordinator(adapter: adapter, ledger: ledger, selectSource: { _ in true })
            self.coordinator = coordinator
            coordinator.handleTrigger(targetPID: pid, sources: sources, currentSourceID: "A", mayRun: true) { [self] outcome in
                guard outcome == .completed(sourceID: "B") else {
                    finish("nativePaste=FAIL case=\(caseIndex) correctionCompleted=false"); return
                }
                verifyAndUndo(pid: pid, element: element, seed: seed, expected: expected, spaces: spaces, selected: selected)
            }
        }
    }

    private func verifyAndUndo(pid: pid_t, element: AXUIElement, seed: String, expected: String, spaces: Int, selected: Bool) {
        let adapter = self.adapter
        let index = caseIndex
        DispatchQueue(label: "qipli.s037.native-paste-verification").async { [weak self] in
            var verificationStage = "afterCorrection"
            do {
                let target = try adapter.capture(pid: pid, deadline: CorrectionAXDeadline())
                guard CFEqual(element, target.element), target.characterCount == expected.utf16.count,
                      try adapter.read(target, range: CFRange(location: 0, length: expected.utf16.count), deadline: CorrectionAXDeadline()) == expected,
                      target.selection.location == (selected ? 15 : 21 + spaces), target.selection.length == (selected ? 6 : 0)
                else { throw CorrectionAXError.verification }
                verificationStage = "undo"
                guard let source = CGEventSource(stateID: .combinedSessionState) else { throw CorrectionAXError.unavailable }
                for down in [true, false] {
                    guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_Z), keyDown: down) else { throw CorrectionAXError.unavailable }
                    event.flags = .maskCommand
                    event.setIntegerValueField(.eventSourceUserData, value: SyntheticEventMarker.sourceUserData)
                    event.postToPid(pid)
                }
                let undoDeadline = CorrectionAXDeadline(milliseconds: 1000)
                var undoVerified = false
                while !undoVerified {
                    try undoDeadline.check()
                    let undone = try adapter.capture(pid: pid, deadline: undoDeadline)
                    guard CFEqual(element, undone.element) else { throw CorrectionAXError.verification }
                    undoVerified = try undone.characterCount == seed.utf16.count &&
                        (adapter.read(undone, range: CFRange(location: 0, length: seed.utf16.count), deadline: undoDeadline)) == seed
                    if !undoVerified { Thread.sleep(forTimeInterval: 0.01) }
                }
                DispatchQueue.main.async {
                    guard let self else { return }
                    let after = self.snapshot()
                    guard self.same(self.clipboardBefore, after) else { self.finish("nativePaste=FAIL clipboardRestore=false"); return }
                    self.lines.append("case=\(index) PASS spaces=\(spaces) selected=\(selected) transport=\(self.selfWrites == 0 ? "unicode" : "paste") nativeUndo=true caret=true clipboardRestore=true preinputMonitor=false")
                    self.caseIndex += 1
                    if self.caseIndex < 3 {
                        self.fixture?.terminate(); self.fixture = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.launchFixture() }
                    }
                    else { self.finish("nativePaste=PASS cases=3 selfWriteRegistrations=\(self.selfWrites) sourceSwitch=mock noPayloadLog=true") }
                }
            } catch {
                DispatchQueue.main.async { self?.finish("nativePaste=FAIL case=\(index) stage=\(verificationStage) verificationError=\(CorrectionDiagnosticCode.error(error).rawValue)") }
            }
        }
    }

    private func snapshot() -> [[(String, Data?)]] {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            item.types.map { type in
                let data = item.data(forType: type)
                return (type.rawValue, data)
            }.sorted { $0.0 < $1.0 }
        }
    }
    private func same(_ a: [[(String, Data?)]], _ b: [[(String, Data?)]]) -> Bool {
        guard a.count == b.count else { return false }
        return zip(a,b).allSatisfy { left,right in left.count == right.count && zip(left,right).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 } }
    }
    private func finish(_ result: String) {
        lines.append(result)
        try? (lines.joined(separator: "\n") + "\n").write(to: Self.reportURL, atomically: true, encoding: .utf8)
        fixture?.terminate()
        NSApp.terminate(nil)
    }
}
