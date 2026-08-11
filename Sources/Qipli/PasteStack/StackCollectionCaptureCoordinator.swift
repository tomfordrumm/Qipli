import Foundation

/// Bridges a single external clipboard event to both product features in the
/// required order: durable History first, transient Stack second.
@MainActor
final class StackCollectionCaptureCoordinator {
    private let historyViewModel: HistoryViewModel
    private let stackSessionController: StackSessionController

    init(historyViewModel: HistoryViewModel, stackSessionController: StackSessionController) {
        self.historyViewModel = historyViewModel
        self.stackSessionController = stackSessionController
    }

    func recordExternalText(
        _ text: String,
        observedChangeCount: Int,
        stackCaptureContext: StackCaptureContext?
    ) {
        guard HistoryTextPolicy.shouldCapture(text) else { return }
        guard let entry = historyViewModel.recordExternalText(text) else {
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
