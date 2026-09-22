import Foundation

/// Routes one normalized clipboard occurrence through durable History first and
/// the transient Paste Stack second. Captures stay ordered even when storage is
/// slower than the pasteboard polling cadence.
@MainActor
final class StackCollectionCaptureCoordinator {
    private let historyViewModel: HistoryViewModel
    private let stackSessionController: StackSessionController
    private var pendingCapture: Task<Void, Never>?
    private let maxPendingBytes: Int
    private let maxPendingCount: Int
    private(set) var pendingByteCount = 0
    private(set) var pendingCount = 0
    private var latestRejection: (message: String, changeCount: Int, context: StackCaptureContext?)?

    init(historyViewModel: HistoryViewModel, stackSessionController: StackSessionController,
         maxPendingBytes: Int = 64 * 1024 * 1024, maxPendingCount: Int = 64) {
        precondition(maxPendingBytes > 0 && maxPendingCount > 0)
        self.maxPendingBytes = maxPendingBytes
        self.maxPendingCount = maxPendingCount
        self.historyViewModel = historyViewModel
        self.stackSessionController = stackSessionController
    }

    func enqueue(
        _ capture: HistoryCapture,
        observedChangeCount: Int,
        stackCaptureContext: StackCaptureContext?
    ) {
        let bytes = capture.payloadByteCount
        guard bytes <= maxPendingBytes else {
            reject(message: "This copy is too large to save.",
                   observedChangeCount: observedChangeCount, stackCaptureContext: stackCaptureContext)
            return
        }
        guard pendingCount < maxPendingCount, bytes <= maxPendingBytes - pendingByteCount else {
            reject(message: "Qipli is busy. This copy was not saved; try copying it again.",
                   observedChangeCount: observedChangeCount, stackCaptureContext: stackCaptureContext)
            return
        }
        pendingCount += 1
        pendingByteCount += bytes
        let previousCapture = pendingCapture
        pendingCapture = Task { @MainActor [weak self] in
            await previousCapture?.value
            guard let self else { return }
            defer {
                self.pendingCount -= 1
                self.pendingByteCount -= bytes
            }
            await self.record(
                capture,
                observedChangeCount: observedChangeCount,
                stackCaptureContext: stackCaptureContext
            )
            if let rejection = self.latestRejection, rejection.changeCount > observedChangeCount {
                self.publishRejection(rejection)
            } else {
                self.latestRejection = nil
            }

        }
    }

    func reject(message: String, observedChangeCount: Int, stackCaptureContext: StackCaptureContext?) {
        let rejection = (message: message, changeCount: observedChangeCount, context: stackCaptureContext)
        latestRejection = rejection
        publishRejection(rejection)
    }

    private func publishRejection(_ rejection: (message: String, changeCount: Int, context: StackCaptureContext?)) {
        historyViewModel.recordCaptureRejection(rejection.message)
        stackSessionController.recordNonTextCaptureFailure(
            message: rejection.message, observedChangeCount: rejection.changeCount, for: rejection.context
        )
    }

    func enqueueExternalText(
        _ text: String,
        observedChangeCount: Int,
        stackCaptureContext: StackCaptureContext?
    ) {
        enqueue(.text(text), observedChangeCount: observedChangeCount, stackCaptureContext: stackCaptureContext)
    }

    func drainPendingCaptures() async {
        await pendingCapture?.value
    }

    func recordExternalText(
        _ text: String,
        observedChangeCount: Int,
        stackCaptureContext: StackCaptureContext?
    ) async {
        await record(
            .text(text),
            observedChangeCount: observedChangeCount,
            stackCaptureContext: stackCaptureContext
        )
    }

    private func record(
        _ capture: HistoryCapture,
        observedChangeCount: Int,
        stackCaptureContext: StackCaptureContext?
    ) async {
        if let text = capture.stackText, !HistoryTextPolicy.shouldCapture(text) {
            return
        }

        guard let result = await historyViewModel.recordExternalCaptureResult(capture) else {
            if capture.stackText != nil {
                stackSessionController.recordCaptureFailure(
                    observedChangeCount: observedChangeCount,
                    for: stackCaptureContext
                )
            } else {
                stackSessionController.recordNonTextCaptureFailure(
                    message: historyViewModel.captureNotice ?? capture.failureMessage,
                    observedChangeCount: observedChangeCount,
                    for: stackCaptureContext
                )
            }
            return
        }

        guard Self.isStackSupported(capture) else {
            stackSessionController.recordNonTextCapture(
                observedChangeCount: observedChangeCount,
                for: stackCaptureContext
            )
            return
        }

        guard let stackCaptureContext else { return }

        guard let lease = await historyViewModel.acquireStackPayloadLease(
            occurrenceID: result.entry.id,
            sessionID: stackCaptureContext.sessionID
        ) else {
            stackSessionController.recordNonTextCaptureFailure(
                message: "This copy was saved to History, but Paste Stack could not hold its payload.",
                observedChangeCount: observedChangeCount,
                for: stackCaptureContext
            )
            return
        }

        let appended = stackSessionController.appendPersistedHistoryEntry(
            result.entry,
            observedChangeCount: observedChangeCount,
            for: stackCaptureContext,
            payloadLease: lease
        )
        if !appended {
            historyViewModel.releaseStackPayloadLease(lease)
            return
        }
        if result.entry.isImageEntry {
            historyViewModel.requestStackThumbnail(for: result.entry)
        }
        stackSessionController.recordCaptureNotice(
            result.notice,
            observedChangeCount: observedChangeCount,
            for: stackCaptureContext
        )
    }

    private static func isStackSupported(_ capture: HistoryCapture) -> Bool {
        switch capture {
        case .text, .richText, .images:
            return true
        case .references, .mixed:
            return false
        }
    }
}
