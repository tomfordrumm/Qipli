import AppKit
import Foundation

protocol TaggedPasteCommandDispatching: AnyObject {
    @discardableResult func postTaggedCommandV() -> Bool
}

/// Sends a source-owned Copy command without reading or writing NSPasteboard.
protocol TaggedCopyCommandDispatching: AnyObject {
    @discardableResult func postTaggedCommandC() -> Bool
}

protocol HistoryPasteboardWriting: AnyObject {
    /// Returns the pasteboard's final change count after this write completes.
    func write(text: String) throws -> Int
}

protocol TypedHistoryPasteboardWriting: AnyObject {
    func write(payload: HistoryPastePayload) throws -> Int
}

enum HistoryPasteboardWriteError: Error {
    case unableToWriteText
}

final class SystemHistoryPasteboardWriter: HistoryPasteboardWriting, TypedHistoryPasteboardWriting {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func write(text: String) throws -> Int {
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw HistoryPasteboardWriteError.unableToWriteText
        }
        return pasteboard.changeCount
    }

    func write(payload: HistoryPastePayload) throws -> Int {
        pasteboard.clearContents()
        let items = payload.items.map { payloadItem in
            let item = NSPasteboardItem()
            for representation in payloadItem.representations {
                item.setData(
                    representation.data,
                    forType: NSPasteboard.PasteboardType(rawValue: representation.typeIdentifier)
                )
            }
            return item
        }
        guard !items.isEmpty, pasteboard.writeObjects(items) else {
            throw HistoryPasteboardWriteError.unableToWriteText
        }
        return pasteboard.changeCount
    }
}

protocol HistoryPasteTarget: AnyObject {
    var isTerminated: Bool { get }
    var isActive: Bool { get }
    /// The display containing the captured target window, when the platform can
    /// resolve it. Presentation falls back to the current display otherwise.
    var preferredScreen: NSScreen? { get }
    /// Returns whether macOS accepted the activation request. It does not guarantee that a third-party field accepted text.
    func activate() -> Bool
}

extension HistoryPasteTarget {
    var preferredScreen: NSScreen? { nil }
}

protocol FrontmostApplicationCapturing: AnyObject {
    func capturePriorApplication() -> HistoryPasteTarget?
}

final class SystemFrontmostApplicationCapture: FrontmostApplicationCapturing {
    func capturePriorApplication() -> HistoryPasteTarget? {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.bundleIdentifier != Bundle.main.bundleIdentifier,
              !application.isTerminated
        else {
            return nil
        }
        return SystemHistoryPasteTarget(application: application)
    }
}

private final class SystemHistoryPasteTarget: HistoryPasteTarget {
    private let application: NSRunningApplication

    init(application: NSRunningApplication) {
        self.application = application
    }

    var isTerminated: Bool { application.isTerminated }
    var isActive: Bool { application.isActive }

    var preferredScreen: NSScreen? {
        let windows = (CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]]) ?? []
        let processID = application.processIdentifier
        guard let window = windows.first(where: { info in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = info[kCGWindowLayer as String] as? Int
            else { return false }
            return ownerPID == processID && layer == 0
        }),
        let bounds = window[kCGWindowBounds as String] as? NSDictionary,
        let windowRect = CGRect(dictionaryRepresentation: bounds)
        else { return nil }
        return NSScreen.screens.first(where: { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            let displayBounds = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
            return displayBounds.contains(CGPoint(x: windowRect.midX, y: windowRect.midY))
        })
    }

    func activate() -> Bool {
        guard !application.isTerminated else { return false }
        NSApp.yieldActivation(to: application)
        return application.activate(from: .current, options: [])
    }
}

enum HistoryPasteFailure: Error, Equatable {
    case accessibilityRequired
    case targetUnavailable
    case entryUnavailable
    case pasteboardWriteFailed
    case referenceUnavailable
    case commandDispatchFailed

    var message: String {
        switch self {
        case .accessibilityRequired:
            "Accessibility access is required before Qipli can send a paste command."
        case .targetUnavailable:
            "The app you were using is no longer available. Return to it, reopen History, and try again."
        case .entryUnavailable:
            "This History item is no longer available. The entry was kept; try another item."
        case .pasteboardWriteFailed:
            "Qipli could not prepare the system clipboard. Try again."
        case .referenceUnavailable:
            "The original file is no longer available. The History entry was kept."
        case .commandDispatchFailed:
            "Qipli could not send the paste command. The history entry was kept; try again."
        }
    }
}

enum HistoryPasteMode: Equatable, Sendable {
    case rich
    case plainText
}

/// `NSRunningApplication` updates dynamic activation state on the main run loop.
/// This deadline-based policy lets a user-initiated handoff settle without
/// sleeping or spinning the event loop.
struct HistoryTargetActivationWaitPolicy: Equatable {
    static let userInitiated = HistoryTargetActivationWaitPolicy(
        retryInterval: 0.05,
        timeout: 1.0
    )

    let retryInterval: TimeInterval
    let timeout: TimeInterval

    init(retryInterval: TimeInterval, timeout: TimeInterval) {
        precondition(retryInterval > 0)
        precondition(timeout >= retryInterval)
        self.retryInterval = retryInterval
        self.timeout = timeout
    }
}

protocol HistoryTargetActivationObserving: AnyObject {
    func invalidate()
}

final class SystemHistoryTargetActivationObservation: HistoryTargetActivationObserving {
    private let notificationCenter: NotificationCenter
    private var token: NSObjectProtocol?

    init(
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        onActivation: @escaping () -> Void
    ) {
        self.notificationCenter = notificationCenter
        token = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { _ in
            onActivation()
        }
    }

    deinit {
        invalidate()
    }

    func invalidate() {
        guard let token else { return }
        notificationCenter.removeObserver(token)
        self.token = nil
    }
}

enum HistoryFocusRestorer {
    /// Uses the same target activation contract as paste cancellation, but has no pasteboard or event side effect.
    static func returnToCapturedTarget(_ target: HistoryPasteTarget?) -> Bool {
        guard let target, !target.isTerminated else { return false }
        return target.activate()
    }
}

/// Executes the observable portion of a history paste. It intentionally never claims that the destination field changed.
@MainActor
final class HistoryPasteExecutor {
    private let permissionService: AccessibilityPermissionChecking
    private let pasteboardWriter: HistoryPasteboardWriting
    private let registerSelfWrite: (Int) -> Void
    private let commandDispatcher: TaggedPasteCommandDispatching
    private let scheduleAfterActivation: (TimeInterval, @escaping () -> Void) -> Void
    private let observeTargetActivation: (@escaping () -> Void) -> HistoryTargetActivationObserving
    private let now: () -> Date
    private let activationWaitPolicy: HistoryTargetActivationWaitPolicy
    private let payloadProvider: ((HistoryEntry) async throws -> HistoryPastePayload?)?
    private var activeOperationID: UUID?
    private var activationObservation: HistoryTargetActivationObserving?

    init(
        permissionService: AccessibilityPermissionChecking,
        pasteboardWriter: HistoryPasteboardWriting,
        registerSelfWrite: @escaping (Int) -> Void,
        commandDispatcher: TaggedPasteCommandDispatching,
        payloadProvider: ((HistoryEntry) async throws -> HistoryPastePayload?)? = nil,
        activationWaitPolicy: HistoryTargetActivationWaitPolicy = .userInitiated,
        scheduleAfterActivation: @escaping (TimeInterval, @escaping () -> Void) -> Void = { interval, work in
            let timer = Timer(timeInterval: interval, repeats: false) { _ in
                work()
            }
            RunLoop.main.add(timer, forMode: .common)
        },
        observeTargetActivation: @escaping (@escaping () -> Void) -> HistoryTargetActivationObserving = {
            SystemHistoryTargetActivationObservation(onActivation: $0)
        },
        now: @escaping () -> Date = Date.init
    ) {
        self.permissionService = permissionService
        self.pasteboardWriter = pasteboardWriter
        self.registerSelfWrite = registerSelfWrite
        self.commandDispatcher = commandDispatcher
        self.activationWaitPolicy = activationWaitPolicy
        self.payloadProvider = payloadProvider
        self.scheduleAfterActivation = scheduleAfterActivation
        self.observeTargetActivation = observeTargetActivation
        self.now = now
    }

    var hasActivePaste: Bool { activeOperationID != nil }

    @discardableResult
    func paste(
        entry: HistoryEntry,
        target: HistoryPasteTarget?,
        mode: HistoryPasteMode = .rich,
        concealPanel: @escaping () -> Void,
        closePanel: @escaping () -> Void,
        completion: @escaping (Result<Void, HistoryPasteFailure>) -> Void
    ) -> Bool {
        guard activeOperationID == nil else { return false }
        let operationID = UUID()
        activeOperationID = operationID

        guard permissionService.refresh() == .granted else {
            finish(operationID: operationID, result: .failure(.accessibilityRequired), completion: completion)
            return true
        }
        guard let target, !target.isTerminated else {
            finish(operationID: operationID, result: .failure(.targetUnavailable), completion: completion)
            return true
        }

        // Copy the immutable value before any UI or activation side effect can change the selected row.
        if mode == .rich, entry.isTypedEntry {
            guard let payloadProvider,
                  let typedWriter = pasteboardWriter as? TypedHistoryPasteboardWriting
            else {
                finish(operationID: operationID, result: .failure(.pasteboardWriteFailed), completion: completion)
                return true
            }
            Task { @MainActor [weak self] in
                do {
                    guard let payload = try await payloadProvider(entry) else {
                        throw HistoryPasteboardWriteError.unableToWriteText
                    }
                    guard let self, self.activeOperationID == operationID else { return }
                    let changeCount = try typedWriter.write(payload: payload)
                    self.registerSelfWrite(changeCount)
                    self.beginActivation(
                        operationID: operationID,
                        target: target,
                        concealPanel: concealPanel,
                        closePanel: closePanel,
                        completion: completion
                    )
                } catch {
                    let failure: HistoryPasteFailure = {
                        if case HistoryStoreError.referenceUnavailable = error {
                            return .referenceUnavailable
                        }
                        return .pasteboardWriteFailed
                    }()
                    self?.finish(
                        operationID: operationID,
                        result: .failure(failure),
                        completion: completion
                    )
                }
            }
            return true
        }

        do {
            let changeCount = try pasteboardWriter.write(text: entry.text)
            registerSelfWrite(changeCount)
        } catch {
            finish(operationID: operationID, result: .failure(.pasteboardWriteFailed), completion: completion)
            return true
        }

        beginActivation(
            operationID: operationID,
            target: target,
            concealPanel: concealPanel,
            closePanel: closePanel,
            completion: completion
        )
        return true
    }

    private func beginActivation(
        operationID: UUID,
        target: HistoryPasteTarget,
        concealPanel: @escaping () -> Void,
        closePanel: @escaping () -> Void,
        completion: @escaping (Result<Void, HistoryPasteFailure>) -> Void
    ) {
        // Keep the ordered key window alive for macOS's cooperative activation
        // handoff, but remove the waiting state from the user's screen.
        concealPanel()
        let deadline = now().addingTimeInterval(activationWaitPolicy.timeout)
        activationObservation = observeTargetActivation { [weak self, weak target] in
            guard let self, let target else { return }
            self.dispatchWhenTargetIsActive(
                operationID: operationID,
                target: target,
                deadline: deadline,
                closePanel: closePanel,
                completion: completion
            )
        }
        guard !target.isTerminated, target.activate() else {
            finish(operationID: operationID, result: .failure(.targetUnavailable), completion: completion)
            return
        }

        // Yield Qipli's active state while the transparent History panel stays
        // ordered. macOS 14's cooperative handoff requires that window state.
        dispatchWhenTargetIsActive(
            operationID: operationID,
            target: target,
            deadline: deadline,
            closePanel: closePanel,
            completion: completion
        )
    }

    func cancelActivePaste() {
        activeOperationID = nil
        activationObservation?.invalidate()
        activationObservation = nil
    }

    private func dispatchWhenTargetIsActive(
        operationID: UUID,
        target: HistoryPasteTarget,
        deadline: Date,
        closePanel: @escaping () -> Void,
        completion: @escaping (Result<Void, HistoryPasteFailure>) -> Void
    ) {
        guard activeOperationID == operationID else { return }
        guard !target.isTerminated else {
            finish(operationID: operationID, result: .failure(.targetUnavailable), completion: completion)
            return
        }
        guard target.isActive else {
            guard now() < deadline else {
                finish(operationID: operationID, result: .failure(.targetUnavailable), completion: completion)
                return
            }
            scheduleAfterActivation(activationWaitPolicy.retryInterval) { [weak self, weak target] in
                guard let self else { return }
                guard let target else {
                    self.finish(operationID: operationID, result: .failure(.targetUnavailable), completion: completion)
                    return
                }
                self.dispatchWhenTargetIsActive(
                    operationID: operationID,
                    target: target,
                    deadline: deadline,
                    closePanel: closePanel,
                    completion: completion
                )
            }
            return
        }
        activationObservation?.invalidate()
        activationObservation = nil
        closePanel()
        guard commandDispatcher.postTaggedCommandV() else {
            finish(operationID: operationID, result: .failure(.commandDispatchFailed), completion: completion)
            return
        }
        finish(operationID: operationID, result: .success(()), completion: completion)
    }

    private func finish(
        operationID: UUID,
        result: Result<Void, HistoryPasteFailure>,
        completion: (Result<Void, HistoryPasteFailure>) -> Void
    ) {
        guard activeOperationID == operationID else { return }
        activeOperationID = nil
        activationObservation?.invalidate()
        activationObservation = nil
        completion(result)
    }
}
