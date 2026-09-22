import ApplicationServices
import AppKit
import Foundation

struct FinderCutSelection: Equatable, Sendable {
    let urls: [URL]

    init(urls: [URL]) {
        var seen = Set<String>()
        self.urls = urls.filter { url in
            let key = url.standardizedFileURL.path
            return seen.insert(key).inserted
        }
    }

    var isEmpty: Bool { urls.isEmpty }
    var count: Int { urls.count }
    var displayNames: [String] { urls.map { $0.lastPathComponent } }
}

struct FinderCutContext: Equatable, Sendable {
    let applicationBundleIdentifier: String?
    let focusedRole: String?
    let isTextField: Bool
    let selectedFileURLs: [URL]
    let isInsertionContext: Bool

    var sourceSelection: FinderCutSelection? {
        guard applicationBundleIdentifier == SystemFinderContextProvider.finderBundleIdentifier,
              !isTextField
        else { return nil }
        let selection = FinderCutSelection(urls: selectedFileURLs)
        return selection.isEmpty ? nil : selection
    }

    var isValidDestination: Bool {
        applicationBundleIdentifier == SystemFinderContextProvider.finderBundleIdentifier
            && !isTextField
            && isInsertionContext
            && selectedFileURLs.isEmpty
    }
}

protocol FinderContextProviding: AnyObject {
    func currentContext() -> FinderCutContext?
}

/// Reads only Finder's accessibility focus/selection metadata. It never reads
/// pasteboard content and never materializes source file bytes.
final class SystemFinderContextProvider: FinderContextProviding {
    static let finderBundleIdentifier = "com.apple.finder"

    func currentContext() -> FinderCutContext? {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.bundleIdentifier == Self.finderBundleIdentifier,
              !application.isTerminated
        else { return nil }

        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        guard let focusedValue = attribute(kAXFocusedUIElementAttribute, from: applicationElement) else {
            return nil
        }
        guard CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else { return nil }
        let focusedElement = focusedValue as! AXUIElement

        let focusedRole = attribute(kAXRoleAttribute, from: focusedElement) as? String
        let isTextField = [
            kAXTextFieldRole,
            kAXTextAreaRole
        ].contains(focusedRole)
        let selectedElements = selectedElementsAround(focusedElement)
        let selectedURLs = selectedElements
            .flatMap(fileURLs(in:))
            .filter(Self.isSupportedSourceURL)

        let insertionRoles = [
            kAXListRole,
            kAXOutlineRole,
            kAXTableRole,
            kAXBrowserRole,
            kAXScrollAreaRole
        ]
        return FinderCutContext(
            applicationBundleIdentifier: application.bundleIdentifier,
            focusedRole: focusedRole,
            isTextField: isTextField,
            selectedFileURLs: Array(Set(selectedURLs)),
            isInsertionContext: insertionRoles.contains(focusedRole ?? "") && !isTextField
        )
    }

    private func selectedElementsAround(_ focusedElement: AXUIElement) -> [AXUIElement] {
        var result: [AXUIElement] = []
        var current: AXUIElement? = focusedElement
        for _ in 0..<6 {
            guard let element = current else { break }
            result.append(contentsOf: arrayAttribute(kAXSelectedChildrenAttribute, from: element))
            result.append(contentsOf: arrayAttribute(kAXSelectedRowsAttribute, from: element))
            if let parent = attribute(kAXParentAttribute, from: element),
               CFGetTypeID(parent) == AXUIElementGetTypeID() {
                current = (parent as! AXUIElement)
            } else {
                current = nil
            }
        }
        return result
    }

    private func fileURLs(in element: AXUIElement) -> [URL] {
        var urls: [URL] = []
        if let value = attribute(kAXURLAttribute, from: element) {
            if let url = value as? URL {
                urls.append(url)
            } else if let url = value as? NSURL {
                urls.append(url as URL)
            } else if let string = value as? String, let url = URL(string: string) {
                urls.append(url)
            }
        }
        for child in arrayAttribute(kAXChildrenAttribute, from: element) {
            urls.append(contentsOf: fileURLs(in: child))
        }
        return urls
    }

    private func attribute(_ name: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private func arrayAttribute(_ name: String, from element: AXUIElement) -> [AXUIElement] {
        (attribute(name, from: element) as? [AXUIElement]) ?? []
    }

    private static func isSupportedSourceURL(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let values = try? url.resourceValues(forKeys: [
            .isDirectoryKey,
            .isRegularFileKey,
            .isUbiquitousItemKey,
            .volumeIsLocalKey
        ])
        guard values?.isDirectory == false,
              values?.isRegularFile == true,
              values?.isUbiquitousItem != true
        else { return false }
        return values?.volumeIsLocal != false
    }
}

protocol FinderCutPasteboardReading: AnyObject {
    var changeCount: Int { get }
    func fileURLs() -> [URL]
}

final class SystemFinderCutPasteboard: FinderCutPasteboardReading {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int { pasteboard.changeCount }

    func fileURLs() -> [URL] {
        pasteboard.pasteboardItems?.compactMap { item in
            let type = NSPasteboard.PasteboardType.fileURL
            if let url = item.propertyList(forType: type) as? URL, url.isFileURL {
                return url
            }
            if let url = item.propertyList(forType: type) as? NSURL, (url as URL).isFileURL {
                return url as URL
            }
            if let string = item.string(forType: type), let url = URL(string: string), url.isFileURL {
                return url
            }
            return nil
        } ?? []
    }
}

/// A small lock-protected bridge between the main-actor AX refresh and the
/// synchronous event tap. The tap never calls Accessibility APIs.
final class FinderCutInputGate {
    private enum Phase {
        case idle
        case ready
        case dispatching
        case handedOff
    }

    private let lock = NSLock()
    private var phase: Phase = .idle
    private var destinationIsValid = false

    func update(isReady: Bool, destinationIsValid: Bool) {
        lock.lock()
        if isReady {
            // The event tap reserves the first paste synchronously and posts
            // the tagged move on the main actor. AX refreshes may run in that
            // gap, but must not reopen the gate for a second paste.
            if phase != .dispatching, phase != .handedOff {
                phase = .ready
            }
            self.destinationIsValid = phase == .ready && destinationIsValid
        } else {
            phase = .idle
            self.destinationIsValid = false
        }
        lock.unlock()
    }

    func releaseDispatchReservation(destinationIsValid: Bool) {
        lock.lock()
        if phase == .dispatching {
            phase = .ready
            self.destinationIsValid = destinationIsValid
        }
        lock.unlock()
    }

    func admitPaste(isRepeat: Bool) -> FinderCutPasteInputDisposition {
        lock.lock()
        defer { lock.unlock() }
        guard phase != .idle else { return .passThrough }
        if phase == .dispatching || phase == .handedOff {
            return .consume
        }
        guard !isRepeat, destinationIsValid else { return .passThrough }
        phase = .dispatching
        return .consumeAndDispatch
    }

    func blockPasteRepeatsAfterDispatch() {
        lock.lock()
        phase = .handedOff
        destinationIsValid = false
        lock.unlock()
    }
}

enum FinderCutSessionState: Equatable {
    case idle
    case preparing(FinderCutSelection)
    case ready(FinderCutSelection)
    case handedOff(FinderCutSelection)
    case blockedByPasteStack
    case failed(FinderCutSelection?, String)

    var selection: FinderCutSelection? {
        switch self {
        case let .preparing(selection), let .ready(selection), let .handedOff(selection):
            selection
        case let .failed(selection, _):
            selection
        case .idle, .blockedByPasteStack:
            nil
        }
    }
}

@MainActor
final class FinderCutSessionController: ObservableObject {
    @Published private(set) var state: FinderCutSessionState = .idle

    let inputGate = FinderCutInputGate()
    var showPanel: () -> Void = {}
    var hidePanel: () -> Void = {}

    private let contextProvider: FinderContextProviding
    private let pasteboard: FinderCutPasteboardReading
    private let copyCommandDispatcher: TaggedCopyCommandDispatching
    private let moveCommandDispatcher: TaggedMoveCommandDispatching
    private let pasteCommandDispatcher: TaggedPasteCommandDispatching?
    var registerSelfWrite: (Int) -> Void
    private let stackIsActive: () -> Bool
    private struct CopyAttempt: Equatable {
        let baselineChangeCount: Int
        let selection: FinderCutSelection
        let issuedAtNanoseconds: UInt64
    }

    private var pendingCopyAttempt: CopyAttempt?
    private var lateCopySuppressions: [CopyAttempt] = []
    private var readyPasteboardChangeCount: Int?
    private var admittedDestinationContext: FinderCutContext?
    private var generation = 0
    private var timeoutWorkItem: DispatchWorkItem?
    private var dismissalWorkItem: DispatchWorkItem?
    private var destinationRefreshTimer: Timer?

    init(
        contextProvider: FinderContextProviding,
        pasteboard: FinderCutPasteboardReading,
        copyCommandDispatcher: TaggedCopyCommandDispatching,
        moveCommandDispatcher: TaggedMoveCommandDispatching,
        pasteCommandDispatcher: TaggedPasteCommandDispatching? = nil,
        registerSelfWrite: @escaping (Int) -> Void = { _ in },
        stackIsActive: @escaping () -> Bool
    ) {
        self.contextProvider = contextProvider
        self.pasteboard = pasteboard
        self.copyCommandDispatcher = copyCommandDispatcher
        self.moveCommandDispatcher = moveCommandDispatcher
        self.pasteCommandDispatcher = pasteCommandDispatcher
        self.registerSelfWrite = registerSelfWrite
        self.stackIsActive = stackIsActive
    }

    deinit {
        timeoutWorkItem?.cancel()
        dismissalWorkItem?.cancel()
        destinationRefreshTimer?.invalidate()
    }

    var isActive: Bool {
        if case .idle = state { return false }
        return true
    }

    var itemNames: [String] { state.selection?.displayNames ?? [] }
    var itemCount: Int { state.selection?.count ?? 0 }

    var statusTitle: String {
        switch state {
        case .idle: ""
        case .preparing: "Preparing move"
        case .ready: "Ready to move"
        case .handedOff: "Command sent to Finder"
        case .blockedByPasteStack: "Finish Paste Stack first"
        case .failed: "Move unavailable"
        }
    }

    var statusDetail: String {
        switch state {
        case .idle:
            ""
        case .preparing:
            "Preparing a native Finder move…"
        case .ready:
            "Open a Finder folder and press ⌘V."
        case .handedOff:
            "Finder owns the move and any conflict or permission dialog."
        case .blockedByPasteStack:
            "Cancel or finish the active Paste Stack before cutting files."
        case let .failed(_, message):
            message
        }
    }

    /// Command-X is observed, not consumed. This keeps rename/search and
    /// other Finder text fields on their normal platform path while avoiding
    /// Accessibility reads from the event-tap callback.
    func handleCommandX(isRepeat: Bool) {
        guard !isRepeat else { return }
        guard !stackIsActive() else {
            recordStackConflict()
            return
        }
        guard let selection = contextProvider.currentContext()?.sourceSelection else { return }
        prepare(selection: selection)
    }

    func recordStackConflict() {
        cancelTimers()
        generation &+= 1
        rememberPendingCopyAttempt()
        state = .blockedByPasteStack
        inputGate.update(isReady: false, destinationIsValid: false)
        showPanel()
    }

    func prepare(selection: FinderCutSelection) {
        guard !selection.isEmpty, !stackIsActive() else { return }
        rememberPendingCopyAttempt()
        cancelTimers()
        generation &+= 1
        let currentGeneration = generation
        pendingCopyAttempt = CopyAttempt(
            baselineChangeCount: pasteboard.changeCount,
            selection: selection,
            issuedAtNanoseconds: DispatchTime.now().uptimeNanoseconds
        )
        readyPasteboardChangeCount = nil
        state = .preparing(selection)
        inputGate.update(isReady: false, destinationIsValid: false)
        showPanel()

        guard copyCommandDispatcher.postTaggedCommandC() else {
            state = .failed(selection, "Qipli could not ask Finder to prepare the selected files.")
            pendingCopyAttempt = nil
            return
        }

        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.generation == currentGeneration else { return }
            self.rememberPendingCopyAttempt()
            self.state = .failed(selection, "Finder did not provide a current file selection.")
        }
        timeoutWorkItem = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: timeout)
    }

    /// Called by PasteboardMonitor before it reads a newly observed external
    /// value. Returning true suppresses the exact Finder self-write from
    /// History; all other changes continue through the normal History path.
    func handleExternalPasteboardChange(changeCount: Int) -> Bool {
        if case let .preparing(selection) = state,
           let attempt = pendingCopyAttempt {
            guard changeCount == attempt.baselineChangeCount + 1,
                  isWithinCopyCorrelationWindow(attempt),
                  sameFiles(pasteboard.fileURLs(), as: selection.urls),
                  currentFinderSelectionMatches(selection)
            else {
                pendingCopyAttempt = nil
                cancel(keepLateCopySuppression: false)
                return false
            }
            timeoutWorkItem?.cancel()
            timeoutWorkItem = nil
            pendingCopyAttempt = nil
            readyPasteboardChangeCount = changeCount
            registerSelfWrite(changeCount)
            state = .ready(selection)
            startDestinationRefresh()
            return true
        }

        if let index = lateCopySuppressions.firstIndex(where: {
            $0.baselineChangeCount + 1 == changeCount
        }) {
            let attempt = lateCopySuppressions.remove(at: index)
            guard isWithinCopyCorrelationWindow(attempt),
                  sameFiles(pasteboard.fileURLs(), as: attempt.selection.urls),
                  currentFinderSelectionMatches(attempt.selection)
            else { return false }
            registerSelfWrite(changeCount)
            return true
        }
        lateCopySuppressions.removeAll { $0.baselineChangeCount + 1 <= changeCount }

        switch state {
        case .ready, .preparing:
            cancel(keepLateCopySuppression: false)
        case .idle, .handedOff, .blockedByPasteStack, .failed:
            break
        }
        return false
    }

    func dispatchMove() {
        guard case let .ready(selection) = state else { return }
        guard let readyPasteboardChangeCount,
              pasteboard.changeCount == readyPasteboardChangeCount
        else {
            let shouldReplayOrdinaryPaste = destinationContextIsStable
            cancel()
            if shouldReplayOrdinaryPaste {
                replayOrdinaryPaste()
            }
            return
        }
        let currentContext = contextProvider.currentContext()
        let stackIsActive = stackIsActive()
        let destinationContextIsStable = currentContext != nil
            && currentContext == admittedDestinationContext
        guard !stackIsActive,
              destinationContextIsStable,
              currentContext?.isValidDestination == true,
              selection.urls.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) })
        else {
            guard !stackIsActive, destinationContextIsStable else {
                inputGate.releaseDispatchReservation(destinationIsValid: false)
                cancel()
                return
            }
            cancel()
            replayOrdinaryPaste()
            return
        }
        guard moveCommandDispatcher.postTaggedCommandMove() else {
            inputGate.update(isReady: false, destinationIsValid: false)
            state = .failed(selection, "Qipli could not send the move command to Finder.")
            return
        }
        cancelTimers()
        inputGate.blockPasteRepeatsAfterDispatch()
        state = .handedOff(selection)
        let currentGeneration = generation
        let dismissal = DispatchWorkItem { [weak self] in
            guard let self, self.generation == currentGeneration,
                  case .handedOff = self.state else { return }
            // Hide the acknowledgement, retaining the one-shot input guard.
            // Dispatch is not evidence that Finder completed the move.
            self.hidePanel()
        }
        dismissalWorkItem = dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: dismissal)
    }

    func cancel(keepLateCopySuppression: Bool = true) {
        cancelTimers()
        generation &+= 1
        if keepLateCopySuppression {
            rememberPendingCopyAttempt()
        } else {
            pendingCopyAttempt = nil
        }
        readyPasteboardChangeCount = nil
        admittedDestinationContext = nil
        state = .idle
        inputGate.update(isReady: false, destinationIsValid: false)
        hidePanel()
    }

    private func startDestinationRefresh() {
        destinationRefreshTimer?.invalidate()
        refreshDestinationAdmission()
        destinationRefreshTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshDestinationAdmission()
            }
        }
    }

    func refreshDestinationAdmission() {
        guard case .ready = state else {
            admittedDestinationContext = nil
            inputGate.update(isReady: false, destinationIsValid: false)
            return
        }
        let context = contextProvider.currentContext()
        admittedDestinationContext = context?.isValidDestination == true ? context : nil
        inputGate.update(
            isReady: true,
            destinationIsValid: context?.isValidDestination == true
        )
    }

    private func sameFiles(_ lhs: [URL], as rhs: [URL]) -> Bool {
        let normalize: (URL) -> String = { $0.standardizedFileURL.resolvingSymlinksInPath().path }
        return Set(lhs.map(normalize)) == Set(rhs.map(normalize)) && !lhs.isEmpty
    }

    private func currentFinderSelectionMatches(_ selection: FinderCutSelection) -> Bool {
        guard let context = contextProvider.currentContext(),
              context.applicationBundleIdentifier == SystemFinderContextProvider.finderBundleIdentifier,
              !context.isTextField,
              context.sourceSelection != nil
        else { return false }
        return sameFiles(context.selectedFileURLs, as: selection.urls)
    }

    private func isWithinCopyCorrelationWindow(_ attempt: CopyAttempt) -> Bool {
        let now = DispatchTime.now().uptimeNanoseconds
        return now >= attempt.issuedAtNanoseconds
            && now - attempt.issuedAtNanoseconds <= 1_000_000_000
    }

    private func replayOrdinaryPaste() {
        _ = pasteCommandDispatcher?.postTaggedCommandV()
    }

    private var destinationContextIsStable: Bool {
        guard let currentContext = contextProvider.currentContext(),
              let admittedDestinationContext
        else { return false }
        return currentContext == admittedDestinationContext
    }

    private func rememberPendingCopyAttempt() {
        guard let pendingCopyAttempt else { return }
        lateCopySuppressions.append(pendingCopyAttempt)
        lateCopySuppressions = Array(lateCopySuppressions.suffix(4))
        self.pendingCopyAttempt = nil
    }

    private func cancelTimers() {
        dismissalWorkItem?.cancel()
        dismissalWorkItem = nil
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        destinationRefreshTimer?.invalidate()
        destinationRefreshTimer = nil
    }
}
