import SwiftUI

struct HistoryPanelView: View {
    @ObservedObject var viewModel: HistoryViewModel
    @ObservedObject var permissionService: AccessibilityPermissionService
    let openAccessibilitySettings: () -> Void
    let pasteSelection: () -> Void
    let close: () -> Void
    @State private var confirmsClearAll = false
    @FocusState private var searchIsFocused: Bool
    @State private var handledPresentationViewportResetRequestID: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("History")
                    .font(.headline)
                Spacer()
                if case .list = viewModel.state {
                    Button("Clear All", role: .destructive) {
                        confirmsClearAll = true
                    }
                }
            }

            TextField("Search history", text: Binding(
                get: { viewModel.query },
                set: { viewModel.updateQuery($0) }
            ))
            .textFieldStyle(.roundedBorder)
            .focused($searchIsFocused)
            .accessibilityIdentifier("history-search")
            .onKeyPress(.upArrow) {
                schedule(.moveSelection(by: -1))
                return .handled
            }
            .onKeyPress(.downArrow) {
                schedule(.moveSelection(by: 1))
                return .handled
            }
            .onKeyPress(.return) {
                schedule(.pasteSelected)
                return .handled
            }
            .onKeyPress(.escape) {
                schedule(.close)
                return .handled
            }

            content

            footer
        }
        .padding(20)
        .frame(width: 460, height: 340, alignment: .topLeading)
        .onAppear {
            HistoryKeyboardActionScheduler.deferToNextMainRunLoop {
                searchIsFocused = true
            }
        }
        .onChange(of: viewModel.searchFocusRequestID) { _, _ in
            HistoryKeyboardActionScheduler.deferToNextMainRunLoop {
                searchIsFocused = true
            }
        }
        .alert("Clear all Qipli history?", isPresented: $confirmsClearAll) {
            Button("Clear All", role: .destructive) {
                viewModel.clearAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes Qipli’s local history. It does not change your current system clipboard.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView("Loading history…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            ContentUnavailableView("No History Yet", systemImage: "clipboard", description: Text("Copied text will appear here while Qipli is running."))
        case let .list(entries):
            if entries.isEmpty {
                ContentUnavailableView(
                    "No Matching History",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different search term.")
                )
            } else {
                ScrollViewReader { proxy in
                    List(entries) { entry in
                        HStack(alignment: .top, spacing: 12) {
                            Button {
                                schedule(.select(entry.id))
                            } label: {
                                Text(entry.text)
                                    .lineLimit(3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .highPriorityGesture(
                                TapGesture(count: 2).onEnded {
                                    schedule(.selectAndPaste(entry.id))
                                }
                            )

                            Button("Delete", role: .destructive) {
                                schedule(.delete(entry))
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 3)
                        .id(entry.id)
                        .listRowBackground(viewModel.selectedEntryID == entry.id ? Color.accentColor.opacity(0.18) : Color.clear)
                    }
                    .listStyle(.inset)
                    .onAppear {
                        scrollSelectionIntoView(using: proxy)
                        resetViewportForFreshPresentation(using: proxy)
                    }
                    .onChange(of: viewModel.selectedEntryID) { _, _ in
                        scrollSelectionIntoView(using: proxy)
                    }
                    .onChange(of: viewModel.presentationViewportResetRequestID) { _, _ in
                        resetViewportForFreshPresentation(using: proxy)
                    }
                }
            }
        case .error:
            VStack(alignment: .leading, spacing: 12) {
                Text("History is unavailable.")
                    .font(.headline)
                Text("Qipli could not read or update local history. Your system clipboard was not changed.")
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    viewModel.reload()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let failure = viewModel.pasteFailure {
                Text(failure.message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if permissionService.state != .granted {
                    Text("Accessibility access is needed to paste.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Settings", action: openAccessibilitySettings)
                } else {
                    Spacer()
                    Button("Paste", action: pasteSelection)
                        .disabled(viewModel.selectedEntry == nil)
                }
            }
        }
    }

    private var canPaste: Bool {
        permissionService.state == .granted
    }

    private func schedule(_ intent: HistoryPanelIntent) {
        HistoryKeyboardActionScheduler.deferToNextMainRunLoop {
            HistoryPanelIntentExecutor(
                moveSelection: viewModel.moveSelection,
                select: viewModel.select,
                hasSelectedEntry: { viewModel.selectedEntry != nil },
                canPaste: { canPaste },
                pasteSelection: pasteSelection,
                close: close,
                delete: viewModel.delete
            )
            .execute(intent)
        }
    }

    private func scrollSelectionIntoView(using proxy: ScrollViewProxy) {
        guard let selectedEntryID = viewModel.selectedEntryID else { return }
        HistoryKeyboardActionScheduler.deferToNextMainRunLoop {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                proxy.scrollTo(selectedEntryID)
            }
        }
    }

    private func resetViewportForFreshPresentation(using proxy: ScrollViewProxy) {
        let requestID = viewModel.presentationViewportResetRequestID
        guard handledPresentationViewportResetRequestID != requestID,
              let firstEntryID = viewModel.visibleEntries.first?.id
        else { return }

        handledPresentationViewportResetRequestID = requestID
        HistoryKeyboardActionScheduler.deferToNextMainRunLoop {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                proxy.scrollTo(firstEntryID, anchor: .top)
            }
        }
    }
}

/// Intent is separated from SwiftUI event callbacks so keyboard and row actions
/// can be verified without depending on an XCUI event loop.
enum HistoryPanelIntent: Equatable {
    case moveSelection(by: Int)
    case pasteSelected
    case close
    case select(UUID)
    case selectAndPaste(UUID)
    case delete(HistoryEntry)
}

/// Executes a deferred History UI intent without depending on SwiftUI. Keeping
/// this small seam makes selection, paste and destructive actions testable.
@MainActor
struct HistoryPanelIntentExecutor {
    let moveSelection: (Int) -> Void
    let select: (UUID) -> Void
    let hasSelectedEntry: () -> Bool
    let canPaste: () -> Bool
    let pasteSelection: () -> Void
    let close: () -> Void
    let delete: (HistoryEntry) -> Void

    func execute(_ intent: HistoryPanelIntent) {
        switch intent {
        case let .moveSelection(offset):
            moveSelection(offset)
        case .pasteSelected:
            pasteIfAvailable()
        case .close:
            close()
        case let .select(id):
            select(id)
        case let .selectAndPaste(id):
            select(id)
            pasteIfAvailable()
        case let .delete(entry):
            delete(entry)
        }
    }

    private func pasteIfAvailable() {
        guard canPaste(), hasSelectedEntry() else { return }
        pasteSelection()
    }
}

/// Keeps keyboard-driven state and window changes outside SwiftUI's current view-update transaction.
private enum HistoryKeyboardActionScheduler {
    static func deferToNextMainRunLoop(_ action: @escaping () -> Void) {
        RunLoop.main.perform(inModes: [.common]) {
            action()
        }
    }
}

struct PasteStackPanelView: View {
    @ObservedObject var sessionController: StackSessionController
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Paste Stack")
                    .font(.headline)
                Spacer()
                Text("Collecting")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if sessionController.occurrences.isEmpty {
                ContentUnavailableView(
                    "Copy text to add it",
                    systemImage: "doc.on.clipboard",
                    description: Text("This stack starts empty and collects new copies only.")
                )
            } else {
                List(sessionController.occurrences) { occurrence in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(occurrence.position + 1).")
                            .foregroundStyle(.secondary)
                        Text(StackPreview.text(for: occurrence.text))
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
            }

            if sessionController.hasCaptureError {
                Text("Qipli could not save the last copied text. Copy it again to retry.")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel Stack", action: cancel)
            }
        }
        .padding(16)
        .frame(width: 400, height: 280, alignment: .topLeading)
        .accessibilityIdentifier("paste-stack-panel")
    }
}

struct PermissionStatusView: View {
    @ObservedObject var permissionService: AccessibilityPermissionService
    let requestAccess: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Accessibility Permission")
                .font(.headline)
            Text(permissionService.state.explanation)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Allow Accessibility Access", action: requestAccess)
                Button("Open System Settings", action: openSettings)
            }
            Text(permissionService.state.menuDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 420, alignment: .leading)
    }
}
