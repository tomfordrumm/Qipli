import AppKit
import Foundation

protocol TaggedPasteCommandDispatching: AnyObject {
    @discardableResult func postTaggedCommandV() -> Bool
}

protocol HistoryPasteboardWriting: AnyObject {
    /// Returns the pasteboard's final change count after this write completes.
    func write(text: String) throws -> Int
}

enum HistoryPasteboardWriteError: Error {
    case unableToWriteText
}

final class SystemHistoryPasteboardWriter: HistoryPasteboardWriting {
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
}

protocol HistoryPasteTarget: AnyObject {
    var isTerminated: Bool { get }
    var isActive: Bool { get }
    /// Returns whether macOS accepted the activation request. It does not guarantee that a third-party field accepted text.
    func activate() -> Bool
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

    func activate() -> Bool {
        guard !application.isTerminated else { return false }
        NSApp.yieldActivation(to: application)
        return application.activate(from: .current, options: [])
    }
}

enum HistoryPasteFailure: Error, Equatable {
    case accessibilityRequired
    case targetUnavailable
    case pasteboardWriteFailed
    case commandDispatchFailed

    var message: String {
        switch self {
        case .accessibilityRequired:
            "Accessibility access is required before Qipli can send a paste command."
        case .targetUnavailable:
            "The app you were using is no longer available. Return to it, reopen History, and try again."
        case .pasteboardWriteFailed:
            "Qipli could not prepare the system clipboard. Try again."
        case .commandDispatchFailed:
            "Qipli could not send the paste command. The history entry was kept; try again."
        }
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
    private let scheduleAfterActivation: (@escaping () -> Void) -> Void
    private let maximumActivationChecks: Int

    init(
        permissionService: AccessibilityPermissionChecking,
        pasteboardWriter: HistoryPasteboardWriting,
        registerSelfWrite: @escaping (Int) -> Void,
        commandDispatcher: TaggedPasteCommandDispatching,
        maximumActivationChecks: Int = 3,
        scheduleAfterActivation: @escaping (@escaping () -> Void) -> Void = { work in
            RunLoop.main.perform(inModes: [.common]) { work() }
        }
    ) {
        self.permissionService = permissionService
        self.pasteboardWriter = pasteboardWriter
        self.registerSelfWrite = registerSelfWrite
        self.commandDispatcher = commandDispatcher
        self.maximumActivationChecks = maximumActivationChecks
        self.scheduleAfterActivation = scheduleAfterActivation
    }

    func paste(
        entry: HistoryEntry,
        target: HistoryPasteTarget?,
        closePanel: @escaping () -> Void,
        completion: @escaping (Result<Void, HistoryPasteFailure>) -> Void
    ) {
        guard permissionService.refresh() == .granted else {
            completion(.failure(.accessibilityRequired))
            return
        }
        guard let target, !target.isTerminated else {
            completion(.failure(.targetUnavailable))
            return
        }

        // Copy the immutable value before any UI or activation side effect can change the selected row.
        let textSnapshot = entry.text
        do {
            let changeCount = try pasteboardWriter.write(text: textSnapshot)
            registerSelfWrite(changeCount)
        } catch {
            completion(.failure(.pasteboardWriteFailed))
            return
        }

        closePanel()
        guard !target.isTerminated, target.activate() else {
            completion(.failure(.targetUnavailable))
            return
        }

        dispatchWhenTargetIsActive(
            target: target,
            remainingChecks: maximumActivationChecks,
            completion: completion
        )
    }

    private func dispatchWhenTargetIsActive(
        target: HistoryPasteTarget,
        remainingChecks: Int,
        completion: @escaping (Result<Void, HistoryPasteFailure>) -> Void
    ) {
        guard !target.isTerminated else {
            completion(.failure(.targetUnavailable))
            return
        }
        guard target.isActive else {
            guard remainingChecks > 1 else {
                completion(.failure(.targetUnavailable))
                return
            }
            scheduleAfterActivation { [weak self, weak target] in
                guard let self, let target else {
                    completion(.failure(.targetUnavailable))
                    return
                }
                self.dispatchWhenTargetIsActive(
                    target: target,
                    remainingChecks: remainingChecks - 1,
                    completion: completion
                )
            }
            return
        }
        guard commandDispatcher.postTaggedCommandV() else {
            completion(.failure(.commandDispatchFailed))
            return
        }
        completion(.success(()))
    }
}
