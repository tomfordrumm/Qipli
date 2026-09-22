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
    private let payloadProvider: (StackPayloadHandle) async throws -> HistoryPastePayload?
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
        payloadProvider: @escaping (StackPayloadHandle) async throws -> HistoryPastePayload?,
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
            self.producePaste(reservation)
        }
    }

    private func producePaste(_ reservation: StackPasteReservation) {
        guard validateReservation(reservation) else { return }
        let lease = sessionController.payloadLease(for: reservation.occurrence.id)
        let isText = reservation.occurrence.payloadHandle.kind == .text
        // Text already belongs to the reservation. Without a lease there is
        // no storage work to await, so it uses the same write boundary directly.
        if isText && lease == nil {
            writeAndDispatch(reservation, payload: nil)
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                if let lease, !(await self.leaseValidator(lease)) {
                    throw StackPasteFailure.payloadUnavailable
                }
                guard self.validateReservation(reservation) else { return }
                let payload: HistoryPastePayload?
                if isText {
                    payload = nil
                } else {
                    guard let resolved = try await self.payloadProvider(reservation.occurrence.payloadHandle) else {
                        throw StackPasteFailure.payloadUnavailable
                    }
                    payload = resolved
                    if let lease, !(await self.leaseValidator(lease)) {
                        throw StackPasteFailure.payloadUnavailable
                    }
                }
                self.writeAndDispatch(reservation, payload: payload)
            } catch {
                self.sessionController.releasePasteReservation(reservation, failure: .payloadUnavailable)
            }
        }
    }

    /// Check again after every suspension, immediately before touching the
    /// clipboard. Cancellation, deletion, permission and external copies can
    /// change while storage is reading a payload or validating its lease.
    private func validateReservation(_ reservation: StackPasteReservation) -> Bool {
        guard sessionController.isPasteReservationCurrent(reservation) else { return false }
        let failure: StackPasteFailure?
        if sessionController.isReservedOccurrenceUnavailable(reservation) {
            failure = .payloadUnavailable
        } else if permissionService.refresh() != .granted {
            failure = .accessibilityRequired
        } else if !pasteboardHasNotChanged(since: reservation.pasteboardChangeCount) {
            failure = .pasteboardChanged
        } else {
            failure = nil
        }
        if let failure {
            sessionController.releasePasteReservation(reservation, failure: failure)
            return false
        }
        return true
    }

    private func writeAndDispatch(_ reservation: StackPasteReservation, payload: HistoryPastePayload?) {
        guard validateReservation(reservation) else { return }
        do {
            let changeCount: Int
            if let payload {
                guard let writer = pasteboardWriter as? TypedHistoryPasteboardWriting else {
                    throw HistoryPasteboardWriteError.unableToWriteText
                }
                changeCount = try writer.write(payload: payload)
            } else {
                changeCount = try pasteboardWriter.write(text: reservation.occurrence.text)
            }
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
