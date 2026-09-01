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

    func enqueueExternalImage(
        _ items: [ManagedImageCaptureItem],
        observedChangeCount: Int,
        stackCaptureContext: StackCaptureContext?
    ) {
        let previousCapture = pendingCapture
        pendingCapture = Task { @MainActor [weak self] in
            await previousCapture?.value
            await self?.recordExternalImage(
                items,
                observedChangeCount: observedChangeCount,
                stackCaptureContext: stackCaptureContext
            )
        }
    }

    func enqueueExternalReference(
        _ items: [HistoryReferenceCaptureItem],
        observedChangeCount: Int,
        stackCaptureContext: StackCaptureContext?
    ) {
        let previousCapture = pendingCapture
        pendingCapture = Task { @MainActor [weak self] in
            await previousCapture?.value
            await self?.recordExternalReference(
                items,
                observedChangeCount: observedChangeCount,
                stackCaptureContext: stackCaptureContext
            )
        }
    }

    func enqueueExternalMixed(
        imageItems: [ManagedImageCaptureItem],
        referenceItems: [HistoryReferenceCaptureItem],
        observedChangeCount: Int,
        stackCaptureContext: StackCaptureContext?
    ) {
        let previousCapture = pendingCapture
        pendingCapture = Task { @MainActor [weak self] in
            await previousCapture?.value
            await self?.recordExternalMixed(
                imageItems: imageItems,
                referenceItems: referenceItems,
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

    private func recordExternalImage(
        _ items: [ManagedImageCaptureItem],
        observedChangeCount: Int,
        stackCaptureContext: StackCaptureContext?
    ) async {
        guard await historyViewModel.recordExternalImage(items) != nil else {
            let message = historyViewModel.imageCaptureNotice
                ?? "Qipli could not save the copied image."
            stackSessionController.recordNonTextCaptureFailure(
                message: message,
                observedChangeCount: observedChangeCount,
                for: stackCaptureContext
            )
            return
        }
        stackSessionController.recordNonTextCapture(
            observedChangeCount: observedChangeCount,
            for: stackCaptureContext
        )
    }

    private func recordExternalReference(
        _ items: [HistoryReferenceCaptureItem],
        observedChangeCount: Int,
        stackCaptureContext: StackCaptureContext?
    ) async {
        guard await historyViewModel.recordExternalReference(items) != nil else {
            let message = historyViewModel.imageCaptureNotice
                ?? "Qipli could not save the copied file reference."
            stackSessionController.recordNonTextCaptureFailure(
                message: message,
                observedChangeCount: observedChangeCount,
                for: stackCaptureContext
            )
            return
        }
        stackSessionController.recordNonTextCapture(
            observedChangeCount: observedChangeCount,
            for: stackCaptureContext
        )
    }

    private func recordExternalMixed(
        imageItems: [ManagedImageCaptureItem],
        referenceItems: [HistoryReferenceCaptureItem],
        observedChangeCount: Int,
        stackCaptureContext: StackCaptureContext?
    ) async {
        guard await historyViewModel.recordExternalMixed(
            imageItems: imageItems,
            referenceItems: referenceItems
        ) != nil else {
            let message = historyViewModel.imageCaptureNotice
                ?? "Qipli could not save the copied item."
            stackSessionController.recordNonTextCaptureFailure(
                message: message,
                observedChangeCount: observedChangeCount,
                for: stackCaptureContext
            )
            return
        }
        stackSessionController.recordNonTextCapture(
            observedChangeCount: observedChangeCount,
            for: stackCaptureContext
        )
    }
}
