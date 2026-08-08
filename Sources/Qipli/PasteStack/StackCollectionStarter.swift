import Foundation

/// Starts Stack collection through either product entry point. The global hotkey
/// intentionally asks the still-active source app to perform a normal Copy;
/// Stack itself never writes NSPasteboard or appends directly.
@MainActor
final class StackCollectionStarter {
    private let sessionController: StackSessionController
    private let currentPasteboardChangeCount: () -> Int
    private let showStackPanel: () -> Void
    private let copyCommandDispatcher: TaggedCopyCommandDispatching

    init(
        sessionController: StackSessionController,
        currentPasteboardChangeCount: @escaping () -> Int,
        showStackPanel: @escaping () -> Void,
        copyCommandDispatcher: TaggedCopyCommandDispatching
    ) {
        self.sessionController = sessionController
        self.currentPasteboardChangeCount = currentPasteboardChangeCount
        self.showStackPanel = showStackPanel
        self.copyCommandDispatcher = copyCommandDispatcher
    }

    /// A repeated hotkey preserves the existing session but requests another
    /// source-owned Copy so another selection can enter the same Stack.
    func startFromHotKey() {
        _ = sessionController.startIfNeeded(captureAfterChangeCount: currentPasteboardChangeCount())
        showStackPanel()
        guard copyCommandDispatcher.postTaggedCommandC() else {
            sessionController.recordCopyCommandDispatchFailure()
            return
        }
        sessionController.clearCopyCommandDispatchFailure()
    }

    /// Status-menu Start has no source selection and therefore starts empty.
    func startFromMenu() {
        _ = sessionController.startIfNeeded(captureAfterChangeCount: currentPasteboardChangeCount())
        showStackPanel()
    }
}
