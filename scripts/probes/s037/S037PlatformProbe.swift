#if DEBUG
import AppKit
import ApplicationServices
import Carbon
import CoreGraphics

/// Development-only, opt-in harness for probing public macOS text and input-source APIs.
/// It only targets a synthetic NSTextView in its own window and never reads the pasteboard.
@MainActor
enum S037PlatformProbe {
    private static var window: NSWindow?
    private static var editor: NSTextView?
    private static var reportView: NSTextView?
    private static var reportLines: [String] = []
    private static var automaticRun = false
    private static var systemFocusDiagnostic = "notQueried"
    private static var optionGestureObserver: S037OptionGestureObserver?
    private static var optionGestureAutoRun = false
    private static var ownMatrixAutoRun = false
    private static var freshWordManualAutoRun = false
    private static var boundedAXStringForRangeRequests = 0
    private static var overBudgetAXStringForRangeRejections = 0
    private static let reportURL = URL(fileURLWithPath: "/private/tmp/qipli-s037-probe-result.txt")
    private static let mdnNativeWindowTitle = "\"<input type=\"text\"> HTML attribute value - HTML | MDN\" – элемент группы \"⌨️ S037 web probe\" - Google Chrome"
    private static let replacementBudgetUTF16 = 4096
    private static let contextBudgetUTF16 = 256

    static func launchIfRequested(arguments: [String]) -> Bool {
        if arguments.contains("--s037-production-textedit-adapter-probe") {
            S037ProductionAdapterProbe.run { result in
                append(result)
                NSApp.terminate(nil)
            }
            return true
        }
        if arguments.contains("--s037-self-ax-regression") {
            S037SelfAXRegression.run { result in
                append(result)
                NSApp.terminate(nil)
            }
            return true
        }
        guard arguments.contains("--s037-platform-probe") ||
                arguments.contains("--s037-platform-probe-preflight") ||
                arguments.contains("--s037-platform-probe-automatic") ||
                arguments.contains("--s037-textedit-probe") ||
                arguments.contains("--s037-mdn-chrome-probe") ||
                arguments.contains("--s037-option-gesture-probe") ||
                arguments.contains("--s037-own-matrix-probe") ||
                arguments.contains("--s037-fresh-word-manual-probe") ||
                arguments.contains("--s037-chrome-fixture-probe") else {
            return false
        }

        if arguments.contains("--s037-platform-probe-automatic") || arguments.contains("--s037-textedit-probe") || arguments.contains("--s037-mdn-chrome-probe") || arguments.contains("--s037-chrome-fixture-probe") {
            automaticRun = true
        }
        if arguments.contains("--s037-option-gesture-probe") {
            automaticRun = true
            optionGestureAutoRun = true
        }
        if arguments.contains("--s037-own-matrix-probe") {
            automaticRun = true
            ownMatrixAutoRun = true
        }
        if arguments.contains("--s037-fresh-word-manual-probe") {
            freshWordManualAutoRun = true
        }
        if arguments.contains("--s037-platform-probe-preflight") {
            append("preflight accessibilityTrusted=\(AXIsProcessTrusted()) secureInput=\(IsSecureEventInputEnabled())")
            printLayoutSummary(appendToWindow: true)
            DispatchQueue.main.async { NSApp.terminate(nil) }
        } else if arguments.contains("--s037-textedit-probe") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { runTextEditFixtureProbe() }
        } else if arguments.contains("--s037-mdn-chrome-probe") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { runMDNChromeFixtureProbe() }
        } else if arguments.contains("--s037-chrome-fixture-probe") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { runChromeFixtureProbe() }
        } else {
            showWindow()
        }
        return true
    }

    private static func showWindow() {
        if ownMatrixAutoRun || optionGestureAutoRun { installSyntheticUndoMenu() }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Qipli Dev — S037 Synthetic Platform Probe"
        window.center()
        window.isReleasedWhenClosed = false
        self.window = window

        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 680, height: 120))
        editor.string = "fixture-before ghbdtn fixture-after"
        editor.isRichText = false
        editor.allowsUndo = true
        editor.identifier = NSUserInterfaceItemIdentifier("s037.synthetic.editor")
        self.editor = editor

        let secure = NSSecureTextField(string: "synthetic-secure-fixture")
        secure.identifier = NSUserInterfaceItemIdentifier("s037.synthetic.secure")
        secure.isEditable = true
        secure.isSelectable = true

        let readOnly = NSTextField(labelWithString: "synthetic-read-only-fixture")
        readOnly.identifier = NSUserInterfaceItemIdentifier("s037.synthetic.readonly")

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 700, height: 140))
        scroll.hasVerticalScroller = true
        scroll.documentView = editor

        let report = NSTextView(frame: NSRect(x: 0, y: 0, width: 700, height: 150))
        report.isEditable = false
        report.isRichText = false
        report.string = "Results contain capability names and booleans only. No external app, clipboard, or user text is inspected."
        reportView = report
        let reportScroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 700, height: 160))
        reportScroll.hasVerticalScroller = true
        reportScroll.documentView = report

        let runButton = NSButton(title: "Check AX range and synthetic replacement", target: S037ProbeActions.shared, action: #selector(S037ProbeActions.runSyntheticChecks))
        let staleButton = NSButton(title: "Check delayed focus/range guard", target: S037ProbeActions.shared, action: #selector(S037ProbeActions.runDelayedGuard))
        let layoutButton = NSButton(title: "Summarize enabled static layouts", target: S037ProbeActions.shared, action: #selector(S037ProbeActions.summarizeLayouts))
        let utf16Button = NSButton(title: "Check UTF-16 range, replacement, caret, Undo", target: S037ProbeActions.shared, action: #selector(S037ProbeActions.runUTF16Checks))
        let sourceButton = NSButton(title: "Check enabled input-source switch and restore", target: S037ProbeActions.shared, action: #selector(S037ProbeActions.runSourceSwitchRoundTrip))
        let optionButton = NSButton(title: "Observe left/right Option gesture (15 seconds)", target: S037ProbeActions.shared, action: #selector(S037ProbeActions.observeOptionGesture))
        let secureLabel = NSTextField(labelWithString: "Secure-field fixture: present (never read)   Read-only-field fixture: present (never read)")

        let stack = NSStackView(views: [
            NSTextField(labelWithString: "Synthetic editable fixture. Click the editor before each check; only this window is eligible."),
            scroll,
            NSTextField(labelWithString: "Secure fixture (never read)"), secure,
            NSTextField(labelWithString: "Read-only fixture (never read)"), readOnly,
            NSStackView(views: [runButton, staleButton, layoutButton]),
            NSStackView(views: [utf16Button, sourceButton, optionButton]),
            secureLabel,
            reportScroll
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView(frame: window.contentView?.bounds ?? .zero)
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -20),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            reportScroll.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        window.contentView = container
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(editor)
        append("preflight accessibilityTrusted=\(AXIsProcessTrusted()) secureInput=\(IsSecureEventInputEnabled()) ownWindowOnly=true")
        if freshWordManualAutoRun {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                S037FreshWordProbe.runManualPhysical(progress: append) { _ in }
            }
        } else if optionGestureAutoRun {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { armOptionGestureObserver(durationSeconds: 45) }
        } else if ownMatrixAutoRun {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { runOwnMatrix() }
        } else if automaticRun {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { runSyntheticChecks() }
        }
    }

    private static func installSyntheticUndoMenu() {
        // The accessory app has no normal Edit menu, so the fixture supplies the
        // responder-chain command needed to verify a real Cmd-Z against NSTextView.
        let mainMenu = NSApp.mainMenu ?? NSMenu(title: "Main")
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        let undo = NSMenuItem(title: "Undo", action: NSSelectorFromString("undo:"), keyEquivalent: "z")
        undo.keyEquivalentModifierMask = [.command]
        undo.target = nil
        editMenu.addItem(undo)
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    private static func runOwnMatrix() {
        runUTF16Checks {
            runSourceSwitchRoundTrip {
                S037FreshWordProbe.run { statusLines in
                    DispatchQueue.main.async {
                        statusLines.forEach(append)
                        finishAutomaticRun()
                    }
                }
            }
        }
    }

    fileprivate static func runSyntheticChecks() {
        guard let window, let editor else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(editor)

        probeProtectedFixtureFields()
        let original = editor.string
        let target = (original as NSString).range(of: "ghbdtn")
        guard target.location != NSNotFound, original == "fixture-before ghbdtn fixture-after" else {
            append("fixtureSeed=FAIL; mutation=SKIPPED")
            finishAutomaticRun()
            return
        }
        editor.setSelectedRange(target)

        guard let element = ownFocusedElement() else {
            append("focusedElement=UNAVAILABLE; mutation=SKIPPED")
            finishAutomaticRun()
            return
        }

        let rangeRead = selectedRange(of: element)
        append("focusedElement=own-process-editable; selectedRangeReadable=\(rangeRead != nil)")
        guard let rangeRead else { append("mutation=SKIPPED"); finishAutomaticRun(); return }

        let rangeSettable = isSettable(element, attribute: kAXSelectedTextRangeAttribute as CFString)
        let setRangeStatus = setSelectedRange(rangeRead, on: element)
        let rangeRoundTrip = selectedRange(of: element).map { rangesEqual($0, rangeRead) } ?? false
        let boundedValue = boundedSelectedText(of: element, range: rangeRead)
        let boundedTextStatus = boundedValue == "ghbdtn"
        append("selectedRangeSettable=\(rangeSettable); rangeSetStatus=\(setRangeStatus); rangeRoundTrip=\(rangeRoundTrip); boundedSelectedRead=\(boundedTextStatus)")
        guard setRangeStatus == .success, rangeRoundTrip,
              let freshRange = selectedRange(of: element), rangesEqual(freshRange, rangeRead),
              boundedSelectedText(of: element, range: freshRange) == "ghbdtn" else {
            append("mutation=SKIPPED; reason=range-readiness-failed")
            finishAutomaticRun()
            return
        }

        let pid = pid_t(getpid())
        guard dispatchSyntheticUnicode("привет", to: pid) else {
            append("unicodeEventDispatch=FAIL; postcondition=NOT-CHECKED")
            finishAutomaticRun()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            let replacementVisible = editor.string == "fixture-before привет fixture-after"
            guard let current = ownFocusedElement(), CFEqual(current, element),
                  let caretRange = selectedRange(of: current),
                  rangesEqual(caretRange, CFRange(location: target.location + ("привет" as NSString).length, length: 0)),
                  replacementVisible else {
                append("unicodeEventDispatch=POSTED; replacementOrCaretPostcondition=FAIL")
                finishAutomaticRun()
                return
            }
            append("unicodeEventDispatch=POSTED; replacementPostcondition=true; caretPostcondition=true")
            let undoAvailable = editor.undoManager?.canUndo ?? false
            guard dispatchCommandUndo(to: pid) else {
                append("commandZDispatch=FAIL; undoManagerCanUndo=\(undoAvailable); fixtureRemainsSyntheticReplacement=true")
                if undoAvailable { editor.undoManager?.undo() }
                finishAutomaticRun()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                let commandZRestored = editor.string == original
                append("commandZDispatch=POSTED; undoManagerCanUndo=\(undoAvailable); commandZRestoredFixture=\(commandZRestored)")
                if !commandZRestored && undoAvailable { editor.undoManager?.undo() }
                append("directUndoManagerRestoredFixture=\(editor.string == original)")
                finishAutomaticRun()
            }
        }
    }

    private static func runTextEditFixtureProbe() {
        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled(),
              let target = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == "com.apple.TextEdit" && !$0.isTerminated
              }) else {
            append("textEditHandoff=SKIPPED; trusted=\(AXIsProcessTrusted()); secureInput=\(IsSecureEventInputEnabled()); targetAvailable=false; payloadReads=0")
            finishAutomaticRun()
            return
        }

        let applicationElement = AXUIElementCreateApplication(target.processIdentifier)
        _ = AXUIElementSetMessagingTimeout(applicationElement, 0.15)
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(applicationElement, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focusedValue, CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            append("textEditHandoff=SKIPPED; appFocusedElementAvailable=false; payloadReads=0")
            finishAutomaticRun()
            return
        }
        let focused = unsafeBitCast(focusedValue, to: AXUIElement.self)
        _ = AXUIElementSetMessagingTimeout(focused, 0.15)
        var focusedPID: pid_t = 0
        guard AXUIElementGetPid(focused, &focusedPID) == .success,
              focusedPID == target.processIdentifier,
              parentWindowTitle(of: focused) == "Без названия 2" else {
            append("textEditHandoff=SKIPPED; exactSyntheticTargetMetadata=false; payloadReads=0")
            finishAutomaticRun()
            return
        }

        if !target.isActive { NSApp.yieldActivation(to: target) }
        let activationAccepted = target.isActive || target.activate(from: .current, options: [])
        append("textEditHandoff=\(activationAccepted ? "REQUESTED" : "REJECTED"); preHandoffTargetMetadata=true; payloadReads=0")
        guard activationAccepted else { finishAutomaticRun(); return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else {
                append("textEditHandoff=NOT-FRONTMOST; frontmostKind=\(frontmostKind(expectedPID: target.processIdentifier)); payloadReads=0")
                finishAutomaticRun()
                return
            }
            runExternalFixtureProbe(
                targetApplication: target,
                expectedFocusedElement: focused,
                targetKind: "textedit-synthetic-fixture",
                expectedTitle: "Без названия 2",
                chromeSuffixAllowed: false,
                fixture: "fixture-before ghbdtn fixture-after",
                selectedFragment: "ghbdtn",
                selection: CFRange(location: 15, length: 6),
                replacement: "привет"
            )
        }
    }

    private static func runChromeFixtureProbe() {
        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled(),
              let target = NSWorkspace.shared.frontmostApplication,
              target.bundleIdentifier == "com.google.Chrome",
              let focused = systemFocusedElement(),
              let focusedPID = axPID(focused), focusedPID == target.processIdentifier,
              let title = parentWindowTitle(of: focused),
              matchesWindowTitle(title, expected: "Qipli S037 synthetic browser probe", chromeSuffixAllowed: true) else {
            append("chromeProbe=SKIPPED; frontmostKind=\(frontmostKind(expectedPID: nil)); payloadReads=0; activationRequested=false")
            finishAutomaticRun()
            return
        }
        runExternalFixtureProbe(
            targetApplication: target,
            expectedFocusedElement: focused,
            targetKind: "chrome-static-fixture",
            expectedTitle: "Qipli S037 synthetic browser probe",
            chromeSuffixAllowed: true,
            fixture: "LEFT ghbdtn vbh RIGHT",
            selectedFragment: "ghbdtn",
            selection: CFRange(location: 5, length: 6),
            replacement: "привет"
        )
    }

    private static func runMDNChromeFixtureProbe() {
        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled(),
              let target = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == "com.google.Chrome" && !$0.isTerminated
              }) else {
            append("mdnChromeHandoff=SKIPPED; trusted=\(AXIsProcessTrusted()); secureInput=\(IsSecureEventInputEnabled()); targetAvailable=false; payloadReads=0")
            finishAutomaticRun()
            return
        }

        let applicationElement = AXUIElementCreateApplication(target.processIdentifier)
        _ = AXUIElementSetMessagingTimeout(applicationElement, 0.15)
        var focusedValue: CFTypeRef?
        let focusError = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )
        guard focusError == .success,
              let focusedValue,
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            append("mdnChromeHandoff=SKIPPED; focusedElementAXError=\(focusError.rawValue); focusedElementCFTypeValid=\(focusedValue.map { CFGetTypeID($0) == AXUIElementGetTypeID() } ?? false); payloadReads=0")
            finishAutomaticRun()
            return
        }
        let focused = unsafeBitCast(focusedValue, to: AXUIElement.self)
        _ = AXUIElementSetMessagingTimeout(focused, 0.15)
        let focusedElementPIDMatches = axPID(focused) == target.processIdentifier
        let windowMetadata = focusedElementPIDMatches ? parentWindowMetadata(of: focused) : WindowMetadata.unavailable
        let titleFound = windowMetadata.title != nil
        let titleMatches = windowMetadata.title.map {
            matchesMdnNativeWindowTitle($0)
        } ?? false
        let role = focusedElementPIDMatches ? axString(focused, attribute: kAXRoleAttribute as CFString) : nil
        let subrole = focusedElementPIDMatches ? axString(focused, attribute: kAXSubroleAttribute as CFString) : nil
        let roleMatches = role == (kAXTextFieldRole as String) && subrole != (kAXSecureTextFieldSubrole as String)
        let labelMatches = focusedElementPIDMatches && (
            axString(focused, attribute: kAXTitleAttribute as CFString) == "Choose a username:" ||
            axString(focused, attribute: kAXDescriptionAttribute as CFString) == "Choose a username:"
        )
        guard focusedElementPIDMatches, titleFound, titleMatches, roleMatches, labelMatches else {
            append("mdnChromeHandoff=SKIPPED; focusedElementPIDMatches=\(focusedElementPIDMatches); titleFound=\(titleFound); titleMatches=\(titleMatches); roleMatches=\(roleMatches); publicLabelMatches=\(labelMatches); axWindowAssociation=\(windowMetadata.axWindowAssociation); topLevelAssociation=\(windowMetadata.topLevelAssociation); ancestorWindowFoundWithinBound=\(windowMetadata.parentChainAssociation); payloadReads=0")
            finishAutomaticRun()
            return
        }

        if !target.isActive { NSApp.yieldActivation(to: target) }
        let activationAccepted = target.isActive || target.activate(from: .current, options: [])
        append("mdnChromeHandoff=\(activationAccepted ? "REQUESTED" : "REJECTED"); exactSyntheticInputMetadata=true; payloadReads=0")
        guard activationAccepted else { finishAutomaticRun(); return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else {
                append("mdnChromeHandoff=NOT-FRONTMOST; frontmostKind=\(frontmostKind(expectedPID: target.processIdentifier)); payloadReads=0")
                finishAutomaticRun()
                return
            }
            runExternalFixtureProbe(
                targetApplication: target,
                expectedFocusedElement: focused,
                targetKind: "mdn-synthetic-input",
                expectedTitle: Self.mdnNativeWindowTitle,
                chromeSuffixAllowed: false,
                fixture: "fixture-before ghbdtn fixture-after",
                selectedFragment: "ghbdtn",
                selection: CFRange(location: 15, length: 6),
                replacement: "привет",
                normalizeNBSPInWindowTitle: true,
                expectedAXLabel: "Choose a username:"
            )
        }
    }

    private static func runExternalFixtureProbe(
        targetApplication: NSRunningApplication,
        expectedFocusedElement: AXUIElement,
        targetKind: String,
        expectedTitle: String,
        chromeSuffixAllowed: Bool,
        fixture: String,
        selectedFragment: String,
        selection: CFRange,
        replacement: String,
        normalizeNBSPInWindowTitle: Bool = false,
        expectedAXLabel: String? = nil
    ) {
        let expectedReplacement = (fixture as NSString).replacingCharacters(
            in: NSRange(location: selection.location, length: selection.length),
            with: replacement
        )
        let expectedSelection = selection
        let expectedCaret = CFRange(location: selection.location + (replacement as NSString).length, length: 0)
        let fixtureRange = CFRange(location: 0, length: (fixture as NSString).length)

        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled(),
              let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.processIdentifier == targetApplication.processIdentifier else {
            append("externalProbe=SKIPPED; trusted=\(AXIsProcessTrusted()); secureInput=\(IsSecureEventInputEnabled()); frontmostKind=\(frontmostKind(expectedPID: targetApplication.processIdentifier)); payloadReads=0")
            finishAutomaticRun()
            return
        }

        let system = AXUIElementCreateSystemWide()
        _ = AXUIElementSetMessagingTimeout(system, 0.15)
        guard let focused = systemFocusedElement(),
              let focusedPID = axPID(focused), focusedPID == frontmost.processIdentifier,
              CFEqual(focused, expectedFocusedElement) else {
            append("textEditProbe=SKIPPED; systemFocus=\(systemFocusDiagnostic); payloadReads=0")
            finishAutomaticRun()
            return
        }
        _ = AXUIElementSetMessagingTimeout(focused, 0.15)
        guard
              let title = parentWindowTitle(of: focused), matchesWindowTitle(title, expected: expectedTitle, chromeSuffixAllowed: chromeSuffixAllowed, normalizeNBSP: normalizeNBSPInWindowTitle) else {
            append("externalProbe=SKIPPED; exactSyntheticWindow=false; payloadReads=0")
            finishAutomaticRun()
            return
        }

        let role = axString(focused, attribute: kAXRoleAttribute as CFString)
        let subrole = axString(focused, attribute: kAXSubroleAttribute as CFString)
        let labelMatches = expectedAXLabel.map { expected in
            axString(focused, attribute: kAXTitleAttribute as CFString) == expected ||
                axString(focused, attribute: kAXDescriptionAttribute as CFString) == expected
        } ?? true
        guard role == (kAXTextAreaRole as String) || role == (kAXTextFieldRole as String),
              subrole != (kAXSecureTextFieldSubrole as String), labelMatches else {
            append("externalProbe=SKIPPED; editableNonsecureRole=false; payloadReads=0")
            finishAutomaticRun()
            return
        }
        let rangeSettable = isSettable(focused, attribute: kAXSelectedTextRangeAttribute as CFString)
        guard rangeSettable else {
            append("externalProbe=SKIPPED; editableRangeNotSettable=true; payloadReads=0")
            finishAutomaticRun()
            return
        }

        guard let beforeRange = selectedRange(of: focused), rangesEqual(beforeRange, expectedSelection),
              boundedSelectedText(of: focused, range: beforeRange) == selectedFragment,
              boundedText(of: focused, range: fixtureRange) == fixture else {
            append("externalProbe=SKIPPED; expectedSelectionOrSyntheticSentinel=false; payloadReads=bounded-only")
            finishAutomaticRun()
            return
        }
        guard setSelectedRange(beforeRange, on: focused) == .success,
              selectedRange(of: focused).map({ rangesEqual($0, beforeRange) }) == true else {
            append("externalProbe=FAIL; rangeSettable=true; rangeRoundTrip=false; mutation=SKIPPED")
            finishAutomaticRun()
            return
        }

        guard let latestFrontmost = NSWorkspace.shared.frontmostApplication,
              latestFrontmost.processIdentifier == focusedPID,
              let latestFocused = systemFocusedElement(), CFEqual(latestFocused, focused),
              parentWindowTitle(of: latestFocused).map({ matchesWindowTitle($0, expected: expectedTitle, chromeSuffixAllowed: chromeSuffixAllowed, normalizeNBSP: normalizeNBSPInWindowTitle) }) == true,
              selectedRange(of: latestFocused).map({ rangesEqual($0, beforeRange) }) == true,
              boundedText(of: latestFocused, range: fixtureRange) == fixture else {
            append("externalProbe=CANCELLED; staleTargetOrRange=true; mutation=SKIPPED")
            finishAutomaticRun()
            return
        }

        append("externalProbe=STARTED; targetKind=\(targetKind); exactSyntheticWindow=true; selectedRangeReadable=true; selectedRangeSettable=true; selectedAndDocumentReads=bounded-only")
        guard dispatchSyntheticUnicode(replacement, to: focusedPID) else {
            append("unicodeEventDispatch=FAIL; externalPostcondition=NOT-CHECKED")
            finishAutomaticRun()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard let currentFrontmost = NSWorkspace.shared.frontmostApplication,
                  currentFrontmost.processIdentifier == focusedPID,
                  let current = systemFocusedElement(), CFEqual(current, focused),
                  parentWindowTitle(of: current).map({ matchesWindowTitle($0, expected: expectedTitle, chromeSuffixAllowed: chromeSuffixAllowed, normalizeNBSP: normalizeNBSPInWindowTitle) }) == true,
                  boundedText(of: current, range: fixtureRange) == expectedReplacement,
                  let caret = selectedRange(of: current),
                  rangesEqual(caret, expectedCaret) else {
                append("unicodeEventDispatch=POSTED; externalReplacementOrCaretPostcondition=FAIL; noRetry=true")
                finishAutomaticRun()
                return
            }
            append("unicodeEventDispatch=POSTED; externalReplacementPostcondition=true; externalCaretPostcondition=true")
            guard dispatchCommandUndo(to: focusedPID) else {
                append("commandZDispatch=FAIL; noRetry=true")
                finishAutomaticRun()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                let restored = NSWorkspace.shared.frontmostApplication?.processIdentifier == focusedPID &&
                    systemFocusedElement().map({ CFEqual($0, focused) }) == true &&
                    parentWindowTitle(of: focused).map({ matchesWindowTitle($0, expected: expectedTitle, chromeSuffixAllowed: chromeSuffixAllowed, normalizeNBSP: normalizeNBSPInWindowTitle) }) == true &&
                    boundedText(of: focused, range: fixtureRange) == fixture
                append("commandZDispatch=POSTED; externalSingleUndoRestoredFixture=\(restored); noRetry=true")
                finishAutomaticRun()
            }
        }
    }

    fileprivate static func runDelayedGuard() {
        guard let window, let editor else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(editor)
        editor.setSelectedRange((editor.string as NSString).range(of: "ghbdtn"))
        guard editor.string == "fixture-before ghbdtn fixture-after",
              let focused = ownFocusedElement(), let range = selectedRange(of: focused),
              boundedSelectedText(of: focused, range: range) == "ghbdtn" else {
            append("delayedGuard=SKIPPED; snapshotUnavailable")
            return
        }
        append("delayedGuard=ARMED; change selection or focus inside this fixture within 2 seconds")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            guard let current = ownFocusedElement(), CFEqual(current, focused),
                  selectedRange(of: current).map({ rangesEqual($0, range) }) == true,
                  boundedSelectedText(of: current, range: range) == "ghbdtn" else {
                append("delayedGuard=CANCELLED; stale focus/range/content")
                return
            }
            append("delayedGuard=FRESH; no mutation performed")
        }
    }

    fileprivate static func runUTF16Checks(completion: (() -> Void)? = nil) {
        guard let window, let editor,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid() else {
            append("utf16Probe=SKIPPED; ownWindowFrontmost=false; payloadReads=0")
            completeProbeStep(completion)
            return
        }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(editor)

        let original = editor.string
        let fixture = "L🙂e\u{301}R"
        let selected = "🙂e\u{301}"
        let sourceRange = CFRange(location: 1, length: 4)
        let replacement = "Привет"
        let expected = "LПриветR"
        let expectedCaret = CFRange(location: 7, length: 0)
        editor.string = fixture
        editor.undoManager?.removeAllActions()
        editor.setSelectedRange(NSRange(location: sourceRange.location, length: sourceRange.length))
        guard let element = ownFocusedElement(),
              axString(element, attribute: kAXRoleAttribute as CFString) == (kAXTextAreaRole as String),
              isSettable(element, attribute: kAXSelectedTextRangeAttribute as CFString),
              let initialRange = selectedRange(of: element), rangesEqual(initialRange, sourceRange),
              boundedText(of: element, range: sourceRange) == selected else {
            editor.string = original
            editor.undoManager?.removeAllActions()
            append("utf16Probe=SKIPPED; syntheticSurrogateCombiningRangeReady=false; mutation=SKIPPED")
            completeProbeStep(completion)
            return
        }

        let setRangeStatus = setSelectedRange(sourceRange, on: element)
        guard setRangeStatus == .success,
              selectedRange(of: element).map({ rangesEqual($0, sourceRange) }) == true,
              boundedText(of: element, range: sourceRange) == selected else {
            editor.string = original
            editor.undoManager?.removeAllActions()
            append("utf16Probe=SKIPPED; selectedRangeSettable=true; selectionRoundTrip=false; mutation=SKIPPED")
            completeProbeStep(completion)
            return
        }
        guard dispatchSyntheticUnicode(replacement, to: getpid()) else {
            editor.string = original
            editor.undoManager?.removeAllActions()
            append("utf16Probe=FAIL; unicodeEventDispatch=false; fixtureRestored=true")
            completeProbeStep(completion)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard editor.string == expected,
                  let current = ownFocusedElement(), CFEqual(current, element),
                  selectedRange(of: current).map({ rangesEqual($0, expectedCaret) }) == true else {
                append("utf16Replacement=false; caretPostcondition=false; cleanupSkippedToPreserveCurrentEditorState=true")
                completeProbeStep(completion)
                return
            }

            let correctedSelection = CFRange(location: 1, length: (replacement as NSString).length)
            let selectionWriteSucceeded = setSelectedRange(correctedSelection, on: current) == .success
            let selectionPreserved = selectionWriteSucceeded &&
                selectedRange(of: current).map({ rangesEqual($0, correctedSelection) }) == true &&
                boundedText(of: current, range: correctedSelection) == replacement
            guard selectionPreserved else {
                append("utf16Replacement=true; caretPostcondition=true; correctedSelectionPreserved=false; cleanupSkippedToPreserveCurrentEditorState=true")
                completeProbeStep(completion)
                return
            }

            let undoAvailable = editor.undoManager?.canUndo ?? false
            guard dispatchCommandUndo(to: getpid()) else {
                append("utf16Replacement=true; caretPostcondition=true; correctedSelectionPreserved=true; commandZDispatch=false; undoManagerCanUndo=\(undoAvailable); cleanupSkipped=true")
                completeProbeStep(completion)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                let nativeUndoRestored = editor.string == fixture
                let fixtureRestored = editor.string == fixture
                let focused = ownFocusedElement().map { CFEqual($0, element) } == true
                let mayRestoreSeed = nativeUndoRestored && focused &&
                    NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid()
                if mayRestoreSeed {
                    editor.string = original
                    editor.undoManager?.removeAllActions()
                }
                let qipliFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid()
                append("utf16RangeRead=true; taggedReplacement=true; caretPostcondition=true; correctedSelectionPreserved=true; nativeSingleUndoRestored=\(nativeUndoRestored); fixtureRestored=\(fixtureRestored); probeSeedRestored=\(mayRestoreSeed); cleanupSkippedOnUnexpectedState=\(!mayRestoreSeed); qipliFrontmostAtCleanup=\(qipliFrontmost)")
                guard fixtureRestored, mayRestoreSeed else {
                    completeProbeStep(completion)
                    return
                }
                runLongUTF16BudgetProbe(editor: editor, focusedElement: element, restoreText: original, completion: completion)
            }
        }
    }

    private static func runLongUTF16BudgetProbe(editor: NSTextView, focusedElement: AXUIElement, restoreText: String, completion: (() -> Void)?) {
        let prefix = String(repeating: "a", count: contextBudgetUTF16)
        let fixture = prefix + "Z"
        let targetRange = CFRange(location: contextBudgetUTF16, length: 1)
        let contextRange = CFRange(location: 0, length: contextBudgetUTF16)
        let replacement = String(repeating: "я", count: replacementBudgetUTF16)
        let replacementLength = (replacement as NSString).length
        let overBudgetLength = replacementBudgetUTF16 + 1
        let oversizeLengthIsAbovePolicy = overBudgetLength > replacementBudgetUTF16
        let expected = prefix + replacement
        let expectedCaret = CFRange(location: contextBudgetUTF16 + replacementBudgetUTF16, length: 0)
        guard replacementLength == replacementBudgetUTF16,
              oversizeLengthIsAbovePolicy,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid(),
              ownFocusedElement().map({ CFEqual($0, focusedElement) }) == true else {
            editor.string = restoreText
            editor.undoManager?.removeAllActions()
            append("longUTF16Probe=SKIPPED; selectedTextLimitUTF16=\(replacementBudgetUTF16); contextLimitUTF16=\(contextBudgetUTF16); oversizeReadCheck=NOT-REACHED")
            completeProbeStep(completion)
            return
        }

        editor.string = fixture
        editor.undoManager?.removeAllActions()
        editor.setSelectedRange(NSRange(location: targetRange.location, length: targetRange.length))
        guard let current = ownFocusedElement(), CFEqual(current, focusedElement),
              isSettable(current, attribute: kAXSelectedTextRangeAttribute as CFString),
              selectedRange(of: current).map({ rangesEqual($0, targetRange) }) == true,
              boundedText(of: current, range: targetRange) == "Z",
              boundedContextText(of: current, range: contextRange).map({ ($0 as NSString).length }) == contextBudgetUTF16 else {
            editor.string = restoreText
            editor.undoManager?.removeAllActions()
            append("longUTF16Probe=SKIPPED; focusedFixture=true; selectedRangeReady=false; contextReadLength256=false; mutation=SKIPPED")
            completeProbeStep(completion)
            return
        }

        let parameterizedReadsBeforeOversize = boundedAXStringForRangeRequests
        let rejectedRangesBeforeOversize = overBudgetAXStringForRangeRejections
        let overBudgetReadWasRejected = boundedText(
            of: current,
            range: CFRange(location: 0, length: overBudgetLength)
        ) == nil && boundedAXStringForRangeRequests == parameterizedReadsBeforeOversize &&
            overBudgetAXStringForRangeRejections == rejectedRangesBeforeOversize + 1
        guard overBudgetReadWasRejected else {
            editor.string = restoreText
            editor.undoManager?.removeAllActions()
            append("longUTF16Probe=FAIL; oversizeRejectedBeforeAXCall=false; mutation=SKIPPED")
            completeProbeStep(completion)
            return
        }

        guard dispatchSyntheticUnicode(replacement, to: getpid()) else {
            editor.string = restoreText
            editor.undoManager?.removeAllActions()
            append("longUTF16Probe=FAIL; oneEventDispatch=false; fixtureRestored=true")
            completeProbeStep(completion)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            let replacementAccepted = editor.string == expected
            let fresh = ownFocusedElement()
            let freshTarget = fresh.map { CFEqual($0, focusedElement) } == true
            let caretMatches = fresh.flatMap { selectedRange(of: $0) }.map({ rangesEqual($0, expectedCaret) }) == true
            let boundedReplacementMatches = fresh.flatMap { boundedText(of: $0, range: CFRange(location: contextBudgetUTF16, length: replacementBudgetUTF16)) } == replacement
            guard replacementAccepted, freshTarget, caretMatches, boundedReplacementMatches else {
                append("longUTF16Probe=FAIL; selectedTextLimitUTF16=\(replacementBudgetUTF16); contextLimitUTF16=\(contextBudgetUTF16); oversizeRejectedBeforeAXCall=\(overBudgetReadWasRejected); oneEventReplacementAccepted=\(replacementAccepted); caretPostcondition=\(caretMatches); boundedReplacementPostcondition=\(boundedReplacementMatches); noChunking=true")
                completeProbeStep(completion)
                return
            }

            let undoAvailable = editor.undoManager?.canUndo ?? false
            let dispatchedUndo = dispatchCommandUndo(to: getpid())
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                let nativeUndoRestored = editor.string == fixture
                let fixtureRestored = editor.string == fixture
                let focused = ownFocusedElement().map { CFEqual($0, focusedElement) } == true
                let mayRestoreSeed = nativeUndoRestored && focused &&
                    NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid()
                if mayRestoreSeed {
                    editor.string = restoreText
                    editor.undoManager?.removeAllActions()
                }
                let longProbePassed = replacementAccepted && freshTarget && caretMatches &&
                    boundedReplacementMatches && dispatchedUndo && nativeUndoRestored && mayRestoreSeed
                let qipliFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid()
                append("longUTF16Probe=\(longProbePassed ? "PASS" : "FAIL"); selectedTextLimitUTF16=\(replacementBudgetUTF16); contextLimitUTF16=\(contextBudgetUTF16); contextBoundedRead=true; oversizeRejectedBeforeAXCall=\(overBudgetReadWasRejected); oneEventReplacementAccepted=\(replacementAccepted); caretPostcondition=\(caretMatches); boundedReplacementPostcondition=\(boundedReplacementMatches); commandZDispatched=\(dispatchedUndo); nativeSingleUndoRestored=\(nativeUndoRestored); fixtureRestored=\(fixtureRestored); probeSeedRestored=\(mayRestoreSeed); cleanupSkippedOnUnexpectedState=\(!mayRestoreSeed); qipliFrontmostAtCleanup=\(qipliFrontmost); noChunking=true; undoManagerHadUndo=\(undoAvailable)")
                completeProbeStep(completion)
            }
        }
    }

    fileprivate static func runSourceSwitchRoundTrip(completion: (() -> Void)? = nil) {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid() else {
            append("inputSourceRoundTrip=SKIPPED; ownWindowFrontmost=false; sourceChanged=false")
            completeProbeStep(completion)
            return
        }
        let filter: [String: Any] = [
            kTISPropertyInputSourceIsEnabled as String: true,
            kTISPropertyInputSourceIsSelectCapable as String: true,
            kTISPropertyInputSourceType as String: kTISTypeKeyboardLayout as Any
        ]
        let sources = (TISCreateInputSourceList(filter as CFDictionary, false).takeRetainedValue() as? [TISInputSource]) ?? []
        guard sources.count >= 2,
              let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let currentID = inputSourceID(current),
              let original = sources.first(where: { inputSourceID($0) == currentID }),
              let target = sources.first(where: { inputSourceID($0) != currentID }),
              let targetID = inputSourceID(target) else {
            append("inputSourceRoundTrip=SKIPPED; enabledStaticSourceCount=\(sources.count); currentSourceInEnabledSet=false; sourceChanged=false")
            completeProbeStep(completion)
            return
        }

        let selectTargetStatus = TISSelectInputSource(target)
        guard selectTargetStatus == noErr else {
            append("inputSourceRoundTrip=FAIL; enabledStaticSourceCount=\(sources.count); targetSelectStatus=\(selectTargetStatus); restoreAttempted=false; currentSourceUnchanged=\(currentInputSourceID() == currentID)")
            completeProbeStep(completion)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let targetSelected = currentInputSourceID() == targetID
            guard targetSelected else {
                append("inputSourceRoundTrip=SKIPPED_RESTORE; enabledStaticSourceCount=\(sources.count); targetSelected=false; restoreAttempted=false; concurrentSourceChangePreserved=true")
                completeProbeStep(completion)
                return
            }
            guard currentInputSourceID() == targetID else {
                append("inputSourceRoundTrip=SKIPPED_RESTORE; enabledStaticSourceCount=\(sources.count); targetSelected=true; restoreAttempted=false; concurrentSourceChangePreserved=true")
                completeProbeStep(completion)
                return
            }
            let restoreStatus = TISSelectInputSource(original)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                let restored = currentInputSourceID() == currentID
                append("inputSourceRoundTrip=\(targetSelected && restoreStatus == noErr && restored ? "PASS" : "FAIL"); enabledStaticSourceCount=\(sources.count); targetSelected=\(targetSelected); restoreStatus=\(restoreStatus); sourceRestored=\(restored); sourceIdentifiersLogged=false")
                completeProbeStep(completion)
            }
        }
    }

    fileprivate static func observeOptionGesture() {
        armOptionGestureObserver(durationSeconds: 15)
    }

    private static func armOptionGestureObserver(durationSeconds: Int) {
        append("optionModifierGateChecks=\(S037OptionGestureObserver.modifierGateChecks ? "PASS" : "FAIL"); preheldShiftCancelled=true; postRecoveryRequiresNeutral=true; capsLockAllowed=true")
        guard AXIsProcessTrusted() else {
            append("optionGestureObserver=UNAVAILABLE; accessibilityTrusted=false; permissionPrompted=false")
            return
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid() else {
            append("optionGestureObserver=SKIPPED; ownWindowFrontmost=false; permissionPrompted=false")
            return
        }
        guard optionGestureObserver == nil,
              let observer = S037OptionGestureObserver.start() else {
            append("optionGestureObserver=UNAVAILABLE; tapCreated=false; permissionPrompted=false")
            return
        }
        optionGestureObserver = observer
        append("optionGestureObserver=ARMED; mode=defaultTapPassThrough; durationSeconds=\(durationSeconds); recordsOnlyOptionGestureCountsWhileProbeFrontmost=true; pressLeftOptionAloneThenRightOptionThenLeftOptionWithAKeyAndMouseClick")
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(durationSeconds)) {
            observer.stop()
            optionGestureObserver = nil
            append(observer.statusLine)
            if optionGestureAutoRun { finishAutomaticRun() }
        }
    }

    private static func inputSourceID(_ source: TISInputSource) -> String? {
        guard let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return unsafeBitCast(value, to: CFString.self) as String
    }

    private static func currentInputSourceID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return inputSourceID(source)
    }

    private static func completeProbeStep(_ completion: (() -> Void)?) {
        if let completion {
            completion()
        } else if automaticRun {
            finishAutomaticRun()
        }
    }

    fileprivate static func summarizeLayouts() {
        printLayoutSummary(appendToWindow: true)
    }

    private static func ownFocusedElement() -> AXUIElement? {
        let app = AXUIElementCreateApplication(getpid())
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &result) == .success,
              let element = result, CFGetTypeID(element) == AXUIElementGetTypeID() else { return nil }
        let axElement = unsafeBitCast(element, to: AXUIElement.self)
        _ = AXUIElementSetMessagingTimeout(axElement, 0.15)
        var pid: pid_t = 0
        guard AXUIElementGetPid(axElement, &pid) == .success, pid == getpid() else { return nil }
        return axElement
    }

    private static func systemFocusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        _ = AXUIElementSetMessagingTimeout(system, 0.15)
        var result: CFTypeRef?
        let applicationError = AXUIElementCopyAttributeValue(
            system,
            kAXFocusedApplicationAttribute as CFString,
            &result
        )
        guard applicationError == .success else {
            systemFocusDiagnostic = "focusedApplicationAXError=\(applicationError.rawValue); focusedApplicationCFTypeValid=false"
            return nil
        }
        guard let applicationValue = result,
              CFGetTypeID(applicationValue) == AXUIElementGetTypeID() else {
            systemFocusDiagnostic = "focusedApplicationAXError=0; focusedApplicationCFTypeValid=false"
            return nil
        }

        let application = unsafeBitCast(applicationValue, to: AXUIElement.self)
        _ = AXUIElementSetMessagingTimeout(application, 0.15)
        var applicationPID: pid_t = 0
        let pidError = AXUIElementGetPid(application, &applicationPID)
        guard pidError == .success,
              let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              applicationPID == frontmostPID else {
            systemFocusDiagnostic = "focusedApplicationPIDMatch=false; pidAXError=\(pidError.rawValue)"
            return nil
        }

        var focusedValue: CFTypeRef?
        let focusedError = AXUIElementCopyAttributeValue(
            application,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )
        guard focusedError == .success else {
            systemFocusDiagnostic = "focusedElementAXError=\(focusedError.rawValue); focusedElementCFTypeValid=false"
            return nil
        }
        guard let focusedValue,
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            systemFocusDiagnostic = "focusedElementAXError=0; focusedElementCFTypeValid=false"
            return nil
        }
        let focused = unsafeBitCast(focusedValue, to: AXUIElement.self)
        _ = AXUIElementSetMessagingTimeout(focused, 0.15)
        let focusedPID = axPID(focused)
        guard focusedPID == applicationPID else {
            systemFocusDiagnostic = "focusedElementPIDMatch=false; focusedElementPIDReadable=\(focusedPID != nil)"
            return nil
        }
        systemFocusDiagnostic = "focusedApplicationAXError=0; focusedApplicationCFTypeValid=true; focusedApplicationPIDMatch=true; focusedElementAXError=0; focusedElementCFTypeValid=true; focusedElementPIDMatch=true"
        return focused
    }

    private static func axPID(_ element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        return pid
    }

    private static func parentWindowTitle(of element: AXUIElement) -> String? {
        parentWindowMetadata(of: element).title
    }

    private struct WindowMetadata {
        let title: String?
        let axWindowAssociation: Bool
        let topLevelAssociation: Bool
        let parentChainAssociation: Bool

        static let unavailable = WindowMetadata(
            title: nil,
            axWindowAssociation: false,
            topLevelAssociation: false,
            parentChainAssociation: false
        )
    }

    private static func parentWindowMetadata(of element: AXUIElement) -> WindowMetadata {
        let elementPID = axPID(element)
        let windowAttribute = associatedWindowMetadata(of: element, attribute: kAXWindowAttribute as CFString, expectedPID: elementPID)
        if windowAttribute.metadata != nil {
            return WindowMetadata(title: windowAttribute.metadata, axWindowAssociation: true, topLevelAssociation: false, parentChainAssociation: false)
        }

        let topLevelAttribute = associatedWindowMetadata(of: element, attribute: kAXTopLevelUIElementAttribute as CFString, expectedPID: elementPID)
        if topLevelAttribute.metadata != nil {
            return WindowMetadata(title: topLevelAttribute.metadata, axWindowAssociation: false, topLevelAssociation: true, parentChainAssociation: false)
        }

        var current = element
        for _ in 0..<12 {
            guard let elementPID, axPID(current) == elementPID else { return .unavailable }
            _ = AXUIElementSetMessagingTimeout(current, 0.15)
            if axString(current, attribute: kAXRoleAttribute as CFString) == (kAXWindowRole as String) {
                let title = axString(current, attribute: kAXTitleAttribute as CFString)
                return WindowMetadata(title: title, axWindowAssociation: false, topLevelAssociation: false, parentChainAssociation: true)
            }
            var parentValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentValue) == .success,
                  let parentValue, CFGetTypeID(parentValue) == AXUIElementGetTypeID() else { return .unavailable }
            current = unsafeBitCast(parentValue, to: AXUIElement.self)
        }
        return .unavailable
    }

    private static func associatedWindowMetadata(
        of element: AXUIElement,
        attribute: CFString,
        expectedPID: pid_t?
    ) -> (metadata: String?, typeValid: Bool) {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return (nil, false) }
        let associated = unsafeBitCast(value, to: AXUIElement.self)
        guard let expectedPID, axPID(associated) == expectedPID,
              axString(associated, attribute: kAXRoleAttribute as CFString) == (kAXWindowRole as String) else {
            return (nil, true)
        }
        return (axString(associated, attribute: kAXTitleAttribute as CFString), true)
    }

    private static func matchesWindowTitle(_ actual: String, expected: String, chromeSuffixAllowed: Bool, normalizeNBSP: Bool = false) -> Bool {
        let normalizedActual = normalizeNBSP ? actual.replacingOccurrences(of: "\u{00A0}", with: " ") : actual
        let normalizedExpected = normalizeNBSP ? expected.replacingOccurrences(of: "\u{00A0}", with: " ") : expected
        return normalizedActual == normalizedExpected || (chromeSuffixAllowed && normalizedActual == normalizedExpected + " - Google Chrome")
    }

    private static func matchesMdnNativeWindowTitle(_ actual: String) -> Bool {
        matchesWindowTitle(actual, expected: mdnNativeWindowTitle, chromeSuffixAllowed: false, normalizeNBSP: true)
    }

    private static func frontmostKind(expectedPID: pid_t?) -> String {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return "none" }
        if frontmost.processIdentifier == getpid() { return "ownProcess" }
        if let expectedPID, frontmost.processIdentifier == expectedPID { return "expectedTarget" }
        return "other"
    }

    private static func selectedRange(of element: AXUIElement) -> CFRange? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &result) == .success,
              let value = result, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cfRange, &range) else { return nil }
        return range
    }

    private static func isSettable(_ element: AXUIElement, attribute: CFString) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute, &settable) == .success && settable.boolValue
    }

    private static func probeProtectedFixtureFields() {
        let app = AXUIElementCreateApplication(getpid())
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement],
              let fixtureWindow = windows.first(where: { axString($0, attribute: kAXTitleAttribute as CFString) == "Qipli Dev — S037 Synthetic Platform Probe" }),
              let secure = findElement(identifier: "s037.synthetic.secure", startingAt: fixtureWindow, depth: 0),
              let readOnly = findElement(identifier: "s037.synthetic.readonly", startingAt: fixtureWindow, depth: 0) else {
            append("protectedFieldRoleCheck=UNAVAILABLE; secureValueRead=SKIPPED; readOnlyValueRead=SKIPPED")
            return
        }

        let secureRole = axString(secure, attribute: kAXRoleAttribute as CFString)
        let secureSubrole = axString(secure, attribute: kAXSubroleAttribute as CFString)
        let readOnlyRole = axString(readOnly, attribute: kAXRoleAttribute as CFString)
        let secureClassified = secureRole == (kAXTextFieldRole as String) && secureSubrole == (kAXSecureTextFieldSubrole as String)
        let readOnlyClassified = readOnlyRole == (kAXTextFieldRole as String) || readOnlyRole == (kAXStaticTextRole as String)
        let readOnlyWritable = isSettable(readOnly, attribute: kAXValueAttribute as CFString)
        append("secureFieldClassified=\(secureClassified); secureValueRead=SKIPPED; secureSelectedTextRead=SKIPPED; readOnlyFieldClassified=\(readOnlyClassified); readOnlyValueSettable=\(readOnlyWritable); readOnlyValueRead=SKIPPED; protectedFieldPayloadRead=SKIPPED")
    }

    private static func findElement(identifier: String, startingAt element: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth <= 12 else { return nil }
        let ownIdentifier = axString(element, attribute: kAXIdentifierAttribute as CFString)
        if ownIdentifier == identifier { return element }
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement], children.count <= 100 else { return nil }
        for child in children {
            var pid: pid_t = 0
            guard AXUIElementGetPid(child, &pid) == .success, pid == getpid() else { continue }
            if let match = findElement(identifier: identifier, startingAt: child, depth: depth + 1) { return match }
        }
        return nil
    }

    private static func axString(_ element: AXUIElement, attribute: CFString) -> String? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &result) == .success else { return nil }
        return result as? String
    }

    private static func setSelectedRange(_ range: CFRange, on element: AXUIElement) -> AXError {
        var mutableRange = range
        guard let value = AXValueCreate(.cfRange, &mutableRange) else { return .cannotComplete }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value)
    }

    private static func boundedSelectedText(of element: AXUIElement, range: CFRange) -> String? {
        boundedText(of: element, range: range)
    }

    private static func boundedText(of element: AXUIElement, range: CFRange) -> String? {
        guard range.location >= 0, range.length >= 0 else { return nil }
        guard range.length <= replacementBudgetUTF16 else {
            overBudgetAXStringForRangeRejections += 1
            return nil
        }
        boundedAXStringForRangeRequests += 1
        var mutableRange = range
        guard let parameter = AXValueCreate(.cfRange, &mutableRange) else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            parameter,
            &result
        ) == .success else { return nil }
        return result as? String
    }

    private static func boundedContextText(of element: AXUIElement, range: CFRange) -> String? {
        guard range.location >= 0, range.length >= 0, range.length <= contextBudgetUTF16 else { return nil }
        return boundedText(of: element, range: range)
    }

    private static func rangesEqual(_ lhs: CFRange, _ rhs: CFRange) -> Bool {
        lhs.location == rhs.location && lhs.length == rhs.length
    }

    private static func dispatchSyntheticUnicode(_ string: String, to pid: pid_t) -> Bool {
        let units = Array(string.utf16)
        guard let down = CGEvent(keyboardEventSource: CGEventSource(stateID: .combinedSessionState), virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: CGEventSource(stateID: .combinedSessionState), virtualKey: 0, keyDown: false) else { return false }
        down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        down.setIntegerValueField(.eventSourceUserData, value: SyntheticEventMarker.sourceUserData)
        up.setIntegerValueField(.eventSourceUserData, value: SyntheticEventMarker.sourceUserData)
        down.postToPid(pid)
        up.postToPid(pid)
        return true
    }

    private static func dispatchCommandUndo(to pid: pid_t) -> Bool {
        guard let down = CGEvent(keyboardEventSource: CGEventSource(stateID: .combinedSessionState), virtualKey: 6, keyDown: true),
              let up = CGEvent(keyboardEventSource: CGEventSource(stateID: .combinedSessionState), virtualKey: 6, keyDown: false) else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.setIntegerValueField(.eventSourceUserData, value: SyntheticEventMarker.sourceUserData)
        up.setIntegerValueField(.eventSourceUserData, value: SyntheticEventMarker.sourceUserData)
        down.postToPid(pid)
        up.postToPid(pid)
        return true
    }

    private static func printLayoutSummary(appendToWindow: Bool = false) {
        let filter: [String: Any] = [
            kTISPropertyInputSourceIsEnabled as String: true,
            kTISPropertyInputSourceIsSelectCapable as String: true,
            kTISPropertyInputSourceType as String: kTISTypeKeyboardLayout as Any
        ]
        let sources = (TISCreateInputSourceList(filter as CFDictionary, false).takeRetainedValue() as? [TISInputSource]) ?? []
        var summaries: [String] = []
        for (index, source) in sources.enumerated() {
            var hasLayoutData = false
            var translatedLevels = 0
            var deadKeyLevels = 0
            var ambiguousGlyphs = 0
            var sampleMappedLevels = 0
            var sampleOutputCounts: [String: Int] = [:]
            let sampleKeys: Set<UInt16> = [5, 4, 11, 2, 17, 45, 50, 43, 47, 33, 30, 27, 39, 41, 44] // Synthetic letters and common punctuation positions.
            if let rawData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
                hasLayoutData = true
                let data = unsafeBitCast(rawData, to: CFData.self) as Data
                if data.count >= MemoryLayout< UCKeyboardLayout >.size {
                    data.withUnsafeBytes { bytes in
                        guard let base = bytes.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
                        var glyphCounts: [String: Int] = [:]
                        let keyboardType = UInt32(LMGetKbdType())
                        for keyCode in UInt16(0)...UInt16(127) {
                            let modifierCases: [UInt32] = [
                                0,
                                UInt32(shiftKey >> 8),
                                UInt32(alphaLock >> 8),
                                UInt32((shiftKey | alphaLock) >> 8)
                            ]
                            for modifiers in modifierCases {
                                var deadState: UInt32 = 0
                                var length = 0
                                var characters = [UniChar](repeating: 0, count: 8)
                                let status = UCKeyTranslate(
                                    base,
                                    keyCode,
                                    UInt16(kUCKeyActionDown),
                                    modifiers,
                                    keyboardType,
                                    UInt32(kUCKeyTranslateNoDeadKeysMask),
                                    &deadState,
                                    characters.count,
                                    &length,
                                    &characters
                                )
                                if status == noErr && length > 0 {
                                    translatedLevels += 1
                                    let output = String(decoding: characters.prefix(length), as: UTF16.self)
                                    glyphCounts[output, default: 0] += 1
                                    if sampleKeys.contains(keyCode) {
                                        sampleMappedLevels += 1
                                        let inverseKey = "\(modifiers)|\(output)"
                                        sampleOutputCounts[inverseKey, default: 0] += 1
                                    }
                                }
                                deadState = 0
                                length = 0
                                let deadStatus = UCKeyTranslate(
                                    base,
                                    keyCode,
                                    UInt16(kUCKeyActionDown),
                                    modifiers,
                                    keyboardType,
                                    0,
                                    &deadState,
                                    characters.count,
                                    &length,
                                    &characters
                                )
                                if deadStatus == noErr && deadState != 0 { deadKeyLevels += 1 }
                            }
                        }
                        ambiguousGlyphs = glyphCounts.values.filter { $0 > 1 }.count
                    }
                }
            }
            let sampleMappingAvailable = hasLayoutData && sampleMappedLevels == sampleKeys.count * 4
            let sampleMappingUnambiguous = sampleMappingAvailable && sampleOutputCounts.values.allSatisfy { $0 == 1 }
            summaries.append("source#\(index + 1){staticData=\(hasLayoutData),translatedLevels=\(translatedLevels),repeatedOutputGlyphs=\(ambiguousGlyphs),deadKeyLevels=\(deadKeyLevels),syntheticSampleMappingAvailable=\(sampleMappingAvailable),syntheticSampleMappingUnambiguous=\(sampleMappingUnambiguous)}")
        }
        let summary = "enabledSelectableStaticKeyboardSources=\(sources.count) " + summaries.joined(separator: " ")
        print("S037 layouts: \(summary)")
        if appendToWindow { append(summary) }
    }

    private static func append(_ line: String) {
        reportLines.append(line)
        print("S037 probe: \(line)")
        writeReport()
        guard let reportView else { return }
        reportView.string += "\n" + line
        reportView.scrollToEndOfDocument(nil)
    }

    private static func finishAutomaticRun() {
        guard automaticRun else { return }
        append("automaticRun=finished")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { NSApp.terminate(nil) }
    }

    private static func writeReport() {
        let contents = reportLines.joined(separator: "\n") + "\n"
        try? contents.write(to: reportURL, atomically: true, encoding: .utf8)
    }
}

@MainActor
private final class S037ProbeActions: NSObject {
    static let shared = S037ProbeActions()

    @objc func runSyntheticChecks() { S037PlatformProbe.runSyntheticChecks() }
    @objc func runDelayedGuard() { S037PlatformProbe.runDelayedGuard() }
    @objc func summarizeLayouts() { S037PlatformProbe.summarizeLayouts() }
    @objc func runUTF16Checks() { S037PlatformProbe.runUTF16Checks() }
    @objc func runSourceSwitchRoundTrip() { S037PlatformProbe.runSourceSwitchRoundTrip() }
    @objc func observeOptionGesture() { S037PlatformProbe.observeOptionGesture() }
}

private final class S037OptionGestureObserver {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var leftOptionDown = false
    private var rightOptionDown = false
    private var leftOptionCancelled = false
    private var leftOptionStartedAt: CFAbsoluteTime = 0
    private var leftStandaloneReleases = 0
    private var leftCancelledReleases = 0
    private var rightOptionReleases = 0
    private var cancellationsByKey = 0
    private var cancellationsByMouse = 0
    private var cancellationsByModifier = 0
    private var maximumLeftHoldMilliseconds = 0
    private var observedFlagsChangedEvents = 0
    private var observedKeyDownEvents = 0
    private var observedMouseDownEvents = 0
    private var disabledTapEvents = 0
    private var reenabledTapEvents = 0
    private var enabledWhenStopped = false
    private var awaitingNeutralAfterRecovery = false

    private init() {}

    static func start() -> S037OptionGestureObserver? {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        guard !flags.contains(.maskAlternate) else { return nil }
        let eventTypes: [CGEventType] = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = eventTypes.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let observer = S037OptionGestureObserver()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.callback,
            userInfo: Unmanaged.passUnretained(observer).toOpaque()
        ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            return nil
        }
        observer.tap = tap
        observer.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        guard CGEvent.tapIsEnabled(tap: tap) else {
            CFMachPortInvalidate(tap)
            return nil
        }
        return observer
    }

    private func handle(_ type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let probeFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid()
            if probeFrontmost { disabledTapEvents += 1 }
            leftOptionDown = false
            rightOptionDown = false
            leftOptionCancelled = false
            awaitingNeutralAfterRecovery = true
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
                if probeFrontmost, CGEvent.tapIsEnabled(tap: tap) { reenabledTapEvents += 1 }
            }
            return
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid() else { return }
        switch type {
        case .flagsChanged: observedFlagsChangedEvents += 1
        case .keyDown: observedKeyDownEvents += 1
        case .leftMouseDown, .rightMouseDown, .otherMouseDown: observedMouseDownEvents += 1
        default: break
        }

        switch type {
        case .flagsChanged:
            if awaitingNeutralAfterRecovery {
                let flags = event.flags
                if !Self.requiresNeutral(flags) {
                    awaitingNeutralAfterRecovery = false
                }
                return
            }
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == Int64(kVK_Option) {
                if !leftOptionDown {
                    leftOptionDown = true
                    leftOptionCancelled = Self.leftDownMustCancel(flags: event.flags, rightOptionDown: rightOptionDown)
                    if leftOptionCancelled { cancellationsByModifier += 1 }
                    leftOptionStartedAt = CFAbsoluteTimeGetCurrent()
                } else {
                    let duration = max(0, Int((CFAbsoluteTimeGetCurrent() - leftOptionStartedAt) * 1_000))
                    maximumLeftHoldMilliseconds = max(maximumLeftHoldMilliseconds, duration)
                    if leftOptionCancelled || rightOptionDown {
                        leftCancelledReleases += 1
                    } else {
                        leftStandaloneReleases += 1
                    }
                    leftOptionDown = false
                    leftOptionCancelled = false
                }
            } else if keyCode == Int64(kVK_RightOption) {
                if !rightOptionDown {
                    rightOptionDown = true
                    if leftOptionDown { leftOptionCancelled = true }
                    if leftOptionDown { cancellationsByModifier += 1 }
                } else {
                    rightOptionReleases += 1
                    rightOptionDown = false
                }
            } else if leftOptionDown && Self.hasChordModifier(event.flags) {
                leftOptionCancelled = true
                cancellationsByModifier += 1
            }
        case .keyDown:
            if leftOptionDown {
                leftOptionCancelled = true
                cancellationsByKey += 1
            }
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if leftOptionDown {
                leftOptionCancelled = true
                cancellationsByMouse += 1
            }
        default:
            break
        }
    }

    private static func hasChordModifier(_ flags: CGEventFlags) -> Bool {
        flags.contains(.maskShift) || flags.contains(.maskControl) || flags.contains(.maskCommand)
    }

    private static func requiresNeutral(_ flags: CGEventFlags) -> Bool {
        flags.contains(.maskAlternate) || hasChordModifier(flags)
    }

    private static func leftDownMustCancel(flags: CGEventFlags, rightOptionDown: Bool) -> Bool {
        rightOptionDown || hasChordModifier(flags)
    }

    static var modifierGateChecks: Bool {
        leftDownMustCancel(flags: .maskShift, rightOptionDown: false) &&
            leftDownMustCancel(flags: .maskControl, rightOptionDown: false) &&
            leftDownMustCancel(flags: .maskCommand, rightOptionDown: false) &&
            leftDownMustCancel(flags: [], rightOptionDown: true) &&
            !leftDownMustCancel(flags: .maskAlphaShift, rightOptionDown: false) &&
            requiresNeutral(.maskAlternate) && requiresNeutral(.maskShift) &&
            !requiresNeutral([]) && !requiresNeutral(.maskAlphaShift)
    }

    var statusLine: String {
        "optionGestureObserver=FINISHED; observedFlagsChangedEvents=\(observedFlagsChangedEvents); observedKeyDownEvents=\(observedKeyDownEvents); observedMouseDownEvents=\(observedMouseDownEvents); leftStandaloneReleases=\(leftStandaloneReleases); leftCancelledReleases=\(leftCancelledReleases); rightOptionReleases=\(rightOptionReleases); cancellationsByKey=\(cancellationsByKey); cancellationsByMouse=\(cancellationsByMouse); cancellationsByModifier=\(cancellationsByModifier); maximumLeftHoldMilliseconds=\(maximumLeftHoldMilliseconds); tapDisabledEvents=\(disabledTapEvents); tapReenabledEvents=\(reenabledTapEvents); tapEnabledAtStop=\(enabledWhenStopped); keyCodesLogged=false; textCaptured=false"
    }

    func stop() {
        if let tap { enabledWhenStopped = CGEvent.tapIsEnabled(tap: tap) }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        if let tap { CFMachPortInvalidate(tap) }
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let observer = Unmanaged<S037OptionGestureObserver>.fromOpaque(userInfo).takeUnretainedValue()
        observer.handle(type, event: event)
        return Unmanaged.passUnretained(event)
    }
}
#endif
