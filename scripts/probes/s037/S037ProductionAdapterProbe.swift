import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Explicit test mode, confined to the same already-owned TextEdit synthetic document.
/// It verifies the production adapter, not the gesture/tracker or source switch.
@MainActor
enum S037ProductionAdapterProbe {
    private nonisolated static let seed = "fixture-before ghbdtn fixture-after"
    private nonisolated static let corrected = "fixture-before привет fixture-after"
    private static let expectedTitle = "Без названия 2"

    static func run(completion: @escaping (String) -> Void) {
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.TextEdit" }),
              let focused = applicationFocusedElement(app.processIdentifier),
              title(of: focused) == expectedTitle else {
            completion("productionAXAdapter=SKIPPED; exactOwnedWindow=false; payloadRead=false"); return
        }
        guard app.isActive || app.activate(from: .current, options: []) else {
            completion("productionAXAdapter=SKIPPED; activation=false; payloadRead=false"); return
        }
        let pid = app.processIdentifier
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                  title(of: focused) == expectedTitle else {
                completion("productionAXAdapter=SKIPPED; focusChanged=true; payloadRead=false"); return
            }
            DispatchQueue(label: "app.qipli.s037.production-adapter-probe").async {
                let adapter = LayoutCorrectionAXAdapter()
                let deadline = CorrectionAXDeadline()
                var passed = false
                do {
                    let original = try adapter.capture(pid: pid, deadline: deadline)
                    guard CFEqual(original.element, focused), original.characterCount == 35,
                          try adapter.read(original, range: CFRange(location: 0, length: 35), deadline: deadline) == seed,
                          try adapter.matches(original, deadline: deadline) else { throw CorrectionAXError.stale }
                    // Prepare the same synthetic selection; no real document content is changed here.
                    var range = CFRange(location: 15, length: 6)
                    guard let value = AXValueCreate(.cfRange, &range),
                          AXUIElementSetAttributeValue(original.element,
                            kAXSelectedTextRangeAttribute as CFString, value) == .success else {
                        throw CorrectionAXError.unavailable
                    }
                    let selected = try adapter.capture(pid: pid, deadline: deadline)
                    let result = try adapter.replace(selected, range: range, expectedText: "ghbdtn",
                        replacement: "привет", keepSelected: true, deadline: deadline, isFresh: { true })
                    let actual = try adapter.read(result.target, range: CFRange(location: 0, length: 35), deadline: deadline)
                    passed = result.target.selection.location == 15 && result.target.selection.length == 6 && actual == corrected
                } catch {
                    DispatchQueue.main.async {
                        completion("productionAXAdapter=FAIL; boundedSyntheticOnly=true; noRetry=true")
                    }
                    return
                }
                let replacementVerified = passed
                DispatchQueue.main.async {
                    guard replacementVerified, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                          title(of: focused) == expectedTitle else {
                        completion("productionAXAdapter=FAIL; postcondition=false; noRetry=true"); return
                    }
                    guard postUndo(pid) else {
                        completion("productionAXAdapter=PASS; reselection=true; nativeUndo=NOT-DISPATCHED"); return
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        DispatchQueue(label: "app.qipli.s037.production-adapter-undo").async {
                            let restored: Bool
                            do {
                                let deadline = CorrectionAXDeadline()
                                let target = try adapter.capture(pid: pid, deadline: deadline)
                                let actual = try adapter.read(target, range: CFRange(location: 0, length: 35), deadline: deadline)
                                restored = CFEqual(target.element, focused) && target.characterCount == 35 && actual == seed
                            } catch { restored = false }
                            DispatchQueue.main.async {
                                completion("productionAXAdapter=PASS; reselection=true; nativeSingleUndo=\(restored); noRetry=true")
                            }
                        }
                    }
                }
            }
        }
    }

    private static func applicationFocusedElement(_ pid: pid_t) -> AXUIElement? {
        let application = AXUIElementCreateApplication(pid)
        _ = AXUIElementSetMessagingTimeout(application, 0.15)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private static func title(of element: AXUIElement) -> String? {
        _ = AXUIElementSetMessagingTimeout(element, 0.15)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let window = unsafeBitCast(value, to: AXUIElement.self)
        _ = AXUIElementSetMessagingTimeout(window, 0.15)
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title) == .success else { return nil }
        return title as? String
    }

    private static func postUndo(_ pid: pid_t) -> Bool {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_Z), keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_Z), keyDown: false) else { return false }
        for event in [down, up] {
            event.flags = [.maskCommand]
            event.setIntegerValueField(.eventSourceUserData, value: SyntheticEventMarker.sourceUserData)
            event.postToPid(pid)
        }
        return true
    }
}
