import Foundation

/// Routes one normalized clipboard occurrence through durable History first and
/// the transient Paste Stack second. Captures stay ordered even when storage is
/// slower than the pasteboard polling cadence.
@MainActor
final class StackCollectionCaptureCoordinator {
    private let historyViewModel: HistoryViewModel
    private let stackSessionController: StackSessionController
    private var pendingCapture: Task<Void, Never>?

    init(historyViewModel: HistoryViewModel, stackSessionController: StackSessionController) {
        self.historyViewModel = historyViewModel
        self.stackSessionController = stackSessionController
    }

    func enqueue(
        _ capture: HistoryCapture,
        observedChangeCount: Int,
        stackCaptureContext: StackCaptureContext?
    ) {
        let previousCapture = pendingCapture
        pendingCapture = Task { @MainActor [weak self] in
            await previousCapture?.value
            await self?.record(
                capture,
                observedChangeCount: observedChangeCount,
                stackCaptureContext: stackCaptureContext
            )
        }
    }

    func enqueueExternalText(
        _ text: String,
        observedChangeCount: Int,
        stackCaptureContext: StackCaptureContext?
    ) {
        enqueue(.text(text), observedChangeCount: observedChangeCount, stackCaptureContext: stackCaptureContext)
    }

    func enqueueExternalRichText(
        _ items: [HistoryRichTextCaptureItem],
        canonicalText: String,
        observedChangeCount: Int,
        stackCaptureContext: StackCaptureContext?
    ) {
        enqueue(
            .richText(text: canonicalText, items: items),
            observedChangeCount: observedChangeCount,
            stackCaptureContext: stackCaptureContext
        )
    }

    func enqueueExternalImage(
        _ items: [ManagedImageCaptureItem],
        observedChangeCount: Int,
        stackCaptureContext: StackCaptureContext?
    ) {
        enqueue(.images(items), observedChangeCount: observedChangeCount, stackCaptureContext: stackCaptureContext)
    }

    func enqueueExternalReference(
        _ items: [HistoryReferenceCaptureItem],
        observedChangeCount: Int,
        stackCaptureContext: StackCaptureContext?
    ) {
        enqueue(.references(items), observedChangeCount: observedChangeCount, stackCaptureContext: stackCaptureContext)
    }

    func enqueueExternalMixed(
        imageItems: [ManagedImageCaptureItem],
        referenceItems: [HistoryReferenceCaptureItem],
        observedChangeCount: Int,
        stackCaptureContext: StackCaptureContext?
    ) {
        enqueue(
            .mixed(images: imageItems, references: referenceItems),
            observedChangeCount: observedChangeCount,
            stackCaptureContext: stackCaptureContext
        )
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

        guard let entry = await historyViewModel.recordExternalCapture(capture) else {
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

        if capture.stackText != nil {
            stackSessionController.appendPersistedHistoryEntry(
                entry,
                observedChangeCount: observedChangeCount,
                for: stackCaptureContext
            )
        } else {
            stackSessionController.recordNonTextCapture(
                observedChangeCount: observedChangeCount,
                for: stackCaptureContext
            )
        }
    }
}
