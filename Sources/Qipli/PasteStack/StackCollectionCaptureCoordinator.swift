import Foundation

/// Bridges a single external clipboard event to both product features in the
/// required order: durable History first, transient Stack second.
@MainActor
final class StackCollectionCaptureCoordinator {
    private let historyViewModel: HistoryViewModel
    private let stackSessionController: StackSessionController
    private var pendingCapture: Task<Void, Never>?

    init(historyViewModel: HistoryViewModel, stackSessionController: StackSessionController) {
        self.historyViewModel = historyViewModel
        self.stackSessionController = stackSessionController
    }

    func enqueueExternalText(
        _ text: String,
        observedChangeCount: Int,
        stackCaptureContext: StackCaptureContext?
    ) {
        let previousCapture = pendingCapture
        pendingCapture = Task { @MainActor [weak self] in
            await previousCapture?.value
            await self?.recordExternalText(
                text,
                observedChangeCount: observedChangeCount,
                stackCaptureContext: stackCaptureContext
            )
        }
    }

    func drainPendingCaptures() async {
        await pendingCapture?.value
    }

    func recordExternalText(
        _ text: String,
        observedChangeCount: Int,
        stackCaptureContext: StackCaptureContext?
    ) async {
        guard HistoryTextPolicy.shouldCapture(text) else { return }
        guard let entry = await historyViewModel.recordExternalText(text) else {
            stackSessionController.recordCaptureFailure(
                observedChangeCount: observedChangeCount,
                for: stackCaptureContext
            )
            return
        }
        stackSessionController.appendPersistedHistoryEntry(
            entry,
            observedChangeCount: observedChangeCount,
            for: stackCaptureContext
        )
    }
}
