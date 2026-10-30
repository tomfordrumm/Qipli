import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Explicit local compatibility runner. Only edits an exact synthetic fixture
/// already placed in a field by the operator. It never sends Return/messages.
@main @MainActor
final class S037CompatibilityProbe: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var result: NSTextField!
    private var running = false
    private var suiteRunning = false
    private var lastSelectedSource: String?
    private let catalog = LayoutCorrectionSourceCatalog()
    private let report = URL(fileURLWithPath: "/private/tmp/qipli-s037-compatibility-report.txt")
    private var lines: [String] = []
    private var originalSource: String?
    private var targetName = "chrome"
    private var method: NativeLayoutCorrectionTransport.ReplayMethod = .paste
    private var selection = false
    static func main() {
        let app = NSApplication.shared, delegate = S037CompatibilityProbe()
        app.setActivationPolicy(.regular); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        catalog.refresh(); originalSource = catalog.currentSourceID
        window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 240),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Qipli synthetic input comparison"
        let stack = NSStackView(); stack.orientation = .vertical; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        let trust = AXIsProcessTrusted() ? "Accessibility granted" : "Accessibility required; no input will be sent"
        stack.addArrangedSubview(NSTextField(labelWithString: trust))
        stack.addArrangedSubview(NSTextField(labelWithString: "Seed an empty test field with ghbdtn. Select it for Copy/Paste."))
        for (index, name) in ["Arm Chrome suite", "Arm Telegram suite"].enumerated() {
            let button = NSButton(title: name, target: self, action: #selector(armSuite(_:)))
            button.tag = index; stack.addArrangedSubview(button)
        }
        result = NSTextField(wrappingLabelWithString: "Ready. Synthetic text only; no messages are sent.")
        stack.addArrangedSubview(result)
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20)])
        let menu = NSMenu(), item = NSMenuItem(), appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu; menu.addItem(item); NSApp.mainMenu = menu
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func armSuite(_ sender: NSButton) {
        guard !running else { return }
        running = true
        targetName = sender.tag == 0 ? "chrome" : "telegram"
        let bundle = sender.tag == 0 ? "com.google.Chrome" : "com.tdesktop.Telegram"
        result.stringValue = "Armed for 60 seconds. Focus the seeded field, caret at end."
        Task {
            defer { running = false; suiteRunning = false }
            suiteRunning = true
            for _ in 0..<300 {
                if let target = NSWorkspace.shared.frontmostApplication, target.bundleIdentifier == bundle {
                    await self.suite(target.processIdentifier)
                    return
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            complete("SKIPPED targetNeverActive=true mutation=false")
        }
    }
    private func suite(_ pid: pid_t) async {
        for candidate: NativeLayoutCorrectionTransport.ReplayMethod in [.unicode, .paste] {
            method = candidate; selection = false
            catalog.refresh()
            guard let latin = catalog.sources.compactMap(\.source).first(where: { $0.keyMap.values.contains("g") }), catalog.select(latin.id) else {
                complete("SKIPPED latinLayoutMissing=true mutation=false"); return
            }
            lastSelectedSource = latin.id
            await execute(pid)
            guard lines.last?.contains("PASS") == true else { return }
            let reset = NativeLayoutCorrectionTransport(replayMethod: .paste)
            reset.configurePasteboard(registerSelfWrite: { _ in }, beginCopy: {}, endCopy: {})
            do {
                let element = try focused(pid)
                guard equalsFixture(element, "привет") else { throw CorrectionAXError.verification }
                _ = try await reset.prepare(pid: pid)
                try await reset.replay(deleteCount: 6, text: "ghbdtn", pid: pid, isFresh: { true })
                await reset.finish()
                guard equalsFixture(element, "ghbdtn") else { throw CorrectionAXError.verification }
            } catch { await reset.finish(); complete("FAIL resetSyntheticField=true"); return }
        }
        do {
            let element = try focused(pid)
            guard equalsFixture(element, "ghbdtn") else { throw CorrectionAXError.verification }
            // The word reset restores text, not the source. Start selection in Latin
            // too, so this case exercises an actual switch to the destination.
            catalog.refresh()
            guard let latin = catalog.sources.compactMap(\.source).first(where: { $0.keyMap.values.contains("g") }),
                  catalog.select(latin.id) else { throw CorrectionAXError.unsupported }
            lastSelectedSource = latin.id
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_A), keyDown: down) else { throw CorrectionAXError.unavailable }
                event.flags = .maskCommand
                event.setIntegerValueField(.eventSourceUserData, value: SyntheticEventMarker.sourceUserData)
                event.postToPid(pid)
            }
            try await Task.sleep(nanoseconds: 100_000_000)
            selection = true
            await execute(pid)
        } catch { complete("FAIL selectSyntheticField=true") }
    }
    private func focused(_ pid: pid_t) throws -> AXUIElement {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { throw CorrectionAXError.stale }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { throw CorrectionAXError.unavailable }
        return unsafeBitCast(raw, to: AXUIElement.self)
    }
    private func equalsFixture(_ element: AXUIElement, _ expected: String) -> Bool {
        AXUIElementSetMessagingTimeout(element, 0.15)
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &raw) == .success,
              let value = raw as? String else { return false }
        return value == expected // Never log field contents, including mismatches.
    }
    private func execute(_ pid: pid_t) async {
        let transport = NativeLayoutCorrectionTransport(replayMethod: method)
        transport.configurePasteboard(registerSelfWrite: { _ in }, beginCopy: {}, endCopy: {})
        var stage = "seedAdmission"
        do {
            let element = try focused(pid)
            guard equalsFixture(element, "ghbdtn") else { throw CorrectionAXError.verification }
            stage = "sourceAdmission"
            catalog.refresh()
            guard let ru = catalog.sources.compactMap(\.source).first(where: { $0.keyMap.values.contains("п") }) else {
                throw CorrectionAXError.unsupported
            }
            stage = "prepare"
            let empty = try await transport.prepare(pid: pid)
            stage = "input"
            if selection {
                guard empty != true, try await transport.copySelection(pid: pid, isFresh: { true }) == "ghbdtn" else { throw CorrectionAXError.verification }
                try await transport.pasteSelection("привет", pid: pid, isFresh: { true })
            } else {
                guard empty == true else { throw CorrectionAXError.verification }
                try await transport.replay(deleteCount: 6, text: "привет", pid: pid, isFresh: { true })
            }
            // Match production: no sleep or AX text read between dispatch and source switch.
            stage = "sourceSwitch"
            guard catalog.select(ru.id) else { throw CorrectionAXError.verification }
            lastSelectedSource = ru.id
            stage = "clipboardGrace"
            await transport.finish()
            stage = "actualText"
            // Unicode comparison has no pasteboard grace; let that editor process replay
            // only after switching. Paste paths already waited in the real finish().
            if !selection && method == .unicode { try await Task.sleep(nanoseconds: 200_000_000) }
            guard CFEqual(element, try focused(pid)), equalsFixture(element, "привет") else { throw CorrectionAXError.verification }
            catalog.refreshCurrentSelection()
            guard catalog.currentSourceID == ru.id else { throw CorrectionAXError.verification }
            complete("PASS actualText=true sourceSwitch=true switchBeforeGrace=true trigger=notExercised")
        } catch {
            let reason = (error as? CorrectionAXError).map { DiagnosticReason(ax: $0).rawValue } ?? "unexpected"
            let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            let kind = front == "com.google.Chrome" ? "chrome" : front == "com.tdesktop.Telegram" ? "telegram" : front == "com.qipli.app.dev" ? "probe" : "other"
            await transport.finish()
            complete("FAIL stage=\(stage) reason=\(reason) mutation=\(transport.mutationBegan) frontmost=\(kind)")
        }
    }
    private func complete(_ status: String) {
        let kind = selection ? "selection" : method == .paste ? "paste" : "unicode"
        let line = "target=\(targetName) method=\(kind) \(status)"
        lines.append(line)
        try? (lines.joined(separator: "\n") + "\n").write(to: report, atomically: true, encoding: .utf8)
        result.stringValue = line; running = suiteRunning
    }
    func applicationWillTerminate(_ notification: Notification) {
        catalog.refreshCurrentSelection()
        if let originalSource, let lastSelectedSource, catalog.currentSourceID == lastSelectedSource {
            _ = catalog.select(originalSource)
        }
    }
}
