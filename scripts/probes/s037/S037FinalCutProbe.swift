import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Explicit synthetic search-field integration test. Never touches timeline/document text.
@main @MainActor
final class S037FinalCutProbe: NSObject, NSApplicationDelegate {
    private let transport = NativeLayoutCorrectionTransport()
    private var target: NSRunningApplication?
    private var started: UInt64 = 0
    private var stage = "focus"
    private let report = URL(fileURLWithPath: "/private/tmp/qipli-s037-final-cut-report.txt")
    static func main() {
        let app = NSApplication.shared, delegate = S037FinalCutProbe()
        app.setActivationPolicy(.accessory); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard AXIsProcessTrusted(), let target = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.FinalCut").first else {
            finish("SKIPPED accessibilityOrTarget=false"); return
        }
        self.target = target; started = DispatchTime.now().uptimeNanoseconds
        target.activate(options: [.activateIgnoringOtherApps])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { Task { await self.run() } }
    }
    private func element(_ pid: pid_t) throws -> AXUIElement {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { throw CorrectionAXError.stale }
        let app = AXUIElementCreateApplication(pid)
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { throw CorrectionAXError.unavailable }
        let focused = unsafeBitCast(raw, to: AXUIElement.self)
        var identifier: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXIdentifierAttribute as CFString, &identifier) == .success,
              identifier as? String == "editor/browserContent/search/textField" else { throw CorrectionAXError.unsupported }
        return focused
    }
    private func run() async {
        guard let target else { return }
        let pid = target.processIdentifier
        transport.configurePasteboard(registerSelfWrite: { _ in }, beginCopy: {}, endCopy: {})
        do {
            _ = try element(pid)
            stage = "preflight"
            _ = try await transport.prepare(pid: pid)
            // Verify the synthetic seed through Copy, independent of AXValue/range APIs.
            stage = "seedCopy"
            try command(CGKeyCode(kVK_ANSI_A), pid: pid)
            let seed = try await transport.copySelection(pid: pid, isFresh: { true })
            guard seed == "ghbdtn" else {
                stage = seed == nil ? "seedMissing" : "seedMismatch"
                throw CorrectionAXError.verification
            }
#if S037_WORD_PROBE
            stage = "replay"
            // Collapse only the known six-character synthetic search selection.
            try plain(CGKeyCode(kVK_RightArrow), pid: pid)
            try await transport.replay(deleteCount: 6, text: "привет", pid: pid, isFresh: { true })
#else
            stage = "paste"
            try await transport.pasteSelection("привет", pid: pid, isFresh: { true })
#endif
            try await Task.sleep(nanoseconds: 150_000_000)
            _ = try element(pid)
            transport.finish()
            stage = "verificationCopy"
            // Re-copy the known synthetic field solely to verify the actual editor result.
            try command(CGKeyCode(kVK_ANSI_A), pid: pid)
            guard try await transport.copySelection(pid: pid, isFresh: { true }) == "привет" else {
                throw CorrectionAXError.verification
            }
            transport.finish()
#if S037_WORD_PROBE
            finish("PASS transport=key-replay actualText=true searchField=true sourceSwitch=notExercised trigger=notExercised")
#else
            finish("PASS transport=copy-paste actualText=true searchField=true sourceSwitch=notExercised trigger=notExercised")
#endif
        } catch {
            transport.finish()
            let reason = (error as? CorrectionAXError).map { DiagnosticReason(ax: $0).rawValue } ?? "unexpected"
            finish("FAIL stage=\(stage) reason=\(reason) inputMayHaveBeenSent=\(transport.mutationBegan)")
        }
    }
    private func command(_ key: CGKeyCode, pid: pid_t) throws { try send(key, flags: .maskCommand, pid: pid) }
    private func plain(_ key: CGKeyCode, pid: pid_t) throws { try send(key, flags: [], pid: pid) }
    private func send(_ key: CGKeyCode, flags: CGEventFlags, pid: pid_t) throws {
        _ = try element(pid)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down) else { throw CorrectionAXError.unavailable }
            event.flags = flags; event.setIntegerValueField(.eventSourceUserData, value: SyntheticEventMarker.sourceUserData)
            event.postToPid(pid)
        }
    }
    private func finish(_ result: String) {
        let elapsed = (DispatchTime.now().uptimeNanoseconds &- started) / 1_000_000
        try? "\(result) elapsedMs=\(elapsed)\n".write(to: report, atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }
}
