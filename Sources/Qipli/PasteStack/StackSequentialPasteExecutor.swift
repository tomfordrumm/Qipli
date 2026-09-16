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
    private let payloadProvider: ((StackPayloadHandle) async throws -> HistoryPastePayload?)?
    private let leaseValidator: (HistoryStackPayloadLease) async -> Bool
    private let currentPasteboardChangeCount: (() -> Int)?
    private let scheduleProduction: (@escaping () -> Void) -> Void
    private let scheduleAutoFinish: (@escaping () -> Void) -> Void
    private let finishPresentation: () -> Void

    init(
        permissionService: AccessibilityPermissionChecking,
        pasteboardWriter: HistoryPasteboardWriting,
        registerSelfWrite: @escaping (Int) -> Void,
        commandDispatcher: TaggedPasteCommandDispatching,
        sessionController: StackSessionController,
        payloadProvider: ((StackPayloadHandle) async throws -> HistoryPastePayload?)? = nil,
        leaseValidator: @escaping (HistoryStackPayloadLease) async -> Bool = { _ in true },
        currentPasteboardChangeCount: (() -> Int)? = nil,
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
        self.payloadProvider = payloadProvider
        self.leaseValidator = leaseValidator
        self.currentPasteboardChangeCount = currentPasteboardChangeCount
        self.scheduleProduction = scheduleProduction
        self.scheduleAutoFinish = scheduleAutoFinish
        self.finishPresentation = finishPresentation
    }

    /// Called after the event tap has atomically reserved an occurrence. It
    /// never activates a target application.
    func executeReservedPaste() {
        guard let reservation = sessionController.currentPasteReservation else { return }
        sessionController.publishReservedPasteState()
        scheduleProduction { [weak self] in
            guard let self else { return }
            if self.payloadProvider == nil {
                self.producePlainPaste(reservation)
            } else {
                Task { @MainActor [weak self] in
                    await self?.produceTypedPaste(reservation)
                }
            }
        }
    }

    private func producePlainPaste(_ reservation: StackPasteReservation) {
        guard sessionController.isPasteReservationCurrent(reservation) else { return }
        guard !sessionController.isReservedOccurrenceUnavailable(reservation) else {
            sessionController.releasePasteReservation(reservation, failure: .payloadUnavailable)
            return
        }
        guard permissionService.refresh() == .granted else {
            sessionController.releasePasteReservation(reservation, failure: .accessibilityRequired)
            return
        }
        guard pasteboardHasNotChanged(since: reservation.pasteboardChangeCount) else {
            sessionController.releasePasteReservation(reservation, failure: .pasteboardChanged)
            return
        }
        do {
            let changeCount = try pasteboardWriter.write(text: reservation.occurrence.text)
            registerSelfWrite(changeCount)
            finishWriteAndDispatch(reservation, changeCount: changeCount)
        } catch {
            sessionController.releasePasteReservation(reservation, failure: .pasteboardWriteFailed)
        }
    }

    private func produceTypedPaste(_ reservation: StackPasteReservation) async {
        guard sessionController.isPasteReservationCurrent(reservation) else { return }
        guard !sessionController.isReservedOccurrenceUnavailable(reservation) else {
            sessionController.releasePasteReservation(reservation, failure: .payloadUnavailable)
            return
        }
        guard permissionService.refresh() == .granted else {
            sessionController.releasePasteReservation(reservation, failure: .accessibilityRequired)
            return
        }
        guard pasteboardHasNotChanged(since: reservation.pasteboardChangeCount) else {
            sessionController.releasePasteReservation(reservation, failure: .pasteboardChanged)
            return
        }
        if let lease = sessionController.payloadLease(for: reservation.occurrence.id),
           !(await leaseValidator(lease)) {
            sessionController.releasePasteReservation(reservation, failure: .payloadUnavailable)
            return
        }

        if reservation.occurrence.payloadHandle.kind == .text {
            do {
                let changeCount = try pasteboardWriter.write(text: reservation.occurrence.text)
                registerSelfWrite(changeCount)
                finishWriteAndDispatch(reservation, changeCount: changeCount)
            } catch {
                sessionController.releasePasteReservation(reservation, failure: .pasteboardWriteFailed)
            }
            return
        }

        let payload: HistoryPastePayload
        do {
            guard let payloadProvider,
                  let providedPayload = try await payloadProvider(reservation.occurrence.payloadHandle)
            else {
                throw StackPasteFailure.payloadUnavailable
            }
            payload = providedPayload
        } catch {
            sessionController.releasePasteReservation(reservation, failure: .payloadUnavailable)
            return
        }

        guard sessionController.isPasteReservationCurrent(reservation),
              pasteboardHasNotChanged(since: reservation.pasteboardChangeCount)
        else {
            if sessionController.isPasteReservationCurrent(reservation) {
                sessionController.releasePasteReservation(reservation, failure: .pasteboardChanged)
            }
            return
        }
        if let lease = sessionController.payloadLease(for: reservation.occurrence.id),
           !(await leaseValidator(lease)) {
            sessionController.releasePasteReservation(reservation, failure: .payloadUnavailable)
            return
        }

        guard let typedWriter = pasteboardWriter as? TypedHistoryPasteboardWriting else {
            sessionController.releasePasteReservation(reservation, failure: .pasteboardWriteFailed)
            return
        }
        do {
            let changeCount = try typedWriter.write(payload: payload)
            registerSelfWrite(changeCount)
            finishWriteAndDispatch(reservation, changeCount: changeCount)
        } catch {
            sessionController.releasePasteReservation(reservation, failure: .pasteboardWriteFailed)
        }
    }

    private func finishWriteAndDispatch(_ reservation: StackPasteReservation, changeCount: Int) {
        guard sessionController.isPasteReservationCurrent(reservation) else { return }
        guard currentPasteboardChangeCount.map({ $0() == changeCount }) ?? true else {
            sessionController.releasePasteReservation(reservation, failure: .pasteboardChanged)
            return
        }
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

    private func pasteboardHasNotChanged(since expectedChangeCount: Int?) -> Bool {
        guard let expectedChangeCount, let currentPasteboardChangeCount else { return true }
        return currentPasteboardChangeCount() == expectedChangeCount
    }
}
