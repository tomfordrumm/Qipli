import Foundation

/// Produces one previously reserved Stack paste outside the active event-tap
/// callback. The reservation is UUID-based, so duplicate text cannot be sent
/// or marked used more than once.
@MainActor
final class StackSequentialPasteExecutor {
    private let permissionService: AccessibilityPermissionChecking
    private let pasteboardWriter: HistoryPasteboardWriting
    private let registerSelfWrite: (Int) -> Void
    private let commandDispatcher: TaggedPasteCommandDispatching
    private let sessionController: StackSessionController
    private let scheduleProduction: (@escaping () -> Void) -> Void
    private let scheduleAutoFinish: (@escaping () -> Void) -> Void
    private let finishPresentation: () -> Void

    init(
        permissionService: AccessibilityPermissionChecking,
        pasteboardWriter: HistoryPasteboardWriting,
        registerSelfWrite: @escaping (Int) -> Void,
        commandDispatcher: TaggedPasteCommandDispatching,
        sessionController: StackSessionController,
        scheduleProduction: @escaping (@escaping () -> Void) -> Void = { action in
            RunLoop.main.perform(inModes: [.common]) { action() }
        },
        scheduleAutoFinish: @escaping (@escaping () -> Void) -> Void = { action in
            RunLoop.main.perform(inModes: [.common]) { action() }
        },
        finishPresentation: @escaping () -> Void
    ) {
        self.permissionService = permissionService
        self.pasteboardWriter = pasteboardWriter
        self.registerSelfWrite = registerSelfWrite
        self.commandDispatcher = commandDispatcher
        self.sessionController = sessionController
        self.scheduleProduction = scheduleProduction
        self.scheduleAutoFinish = scheduleAutoFinish
        self.finishPresentation = finishPresentation
    }

    /// Called asynchronously after the event tap has atomically reserved an
    /// occurrence. It never activates a target application (S007 is separate).
    func executeReservedPaste() {
        guard let reservation = sessionController.currentPasteReservation else { return }
        sessionController.publishReservedPasteState()
        // SwiftUI's native List needs a completed layout turn for the processing
        // row before the same occurrence can become used or the panel can close.
        // This mirrors the panel's existing deferred intent boundary.
        scheduleProduction { [weak self] in
            self?.produceReservedPaste(reservation)
        }
    }

    private func produceReservedPaste(_ reservation: StackPasteReservation) {
        guard sessionController.isPasteReservationCurrent(reservation) else { return }

        guard permissionService.refresh() == .granted else {
            sessionController.releasePasteReservation(reservation, failure: .accessibilityRequired)
            return
        }

        do {
            let changeCount = try pasteboardWriter.write(text: reservation.occurrence.text)
            registerSelfWrite(changeCount)
        } catch {
            sessionController.releasePasteReservation(reservation, failure: .pasteboardWriteFailed)
            return
        }

        guard sessionController.isPasteReservationCurrent(reservation) else { return }
        guard commandDispatcher.postTaggedCommandV() else {
            sessionController.releasePasteReservation(reservation, failure: .commandDispatchFailed)
            return
        }

        guard sessionController.completePasteReservation(reservation) else { return }
        scheduleAutoFinish { [weak self] in
            guard let self,
                  self.sessionController.finishCompletedSession(sessionID: reservation.sessionID)
            else { return }
            self.finishPresentation()
        }
    }
}
