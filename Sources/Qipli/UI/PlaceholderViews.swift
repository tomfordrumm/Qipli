import SwiftUI

struct HistoryPanelView: View {
    @ObservedObject var viewModel: HistoryViewModel
    @ObservedObject var permissionService: AccessibilityPermissionService
    let openAccessibilitySettings: () -> Void
    let pasteSelection: () -> Void
    let close: () -> Void
    @State private var confirmsClearAll = false
    @FocusState private var searchIsFocused: Bool

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
        .onKeyPress(.upArrow) {
            HistoryKeyboardActionScheduler.deferToNextMainRunLoop {
                viewModel.moveSelection(by: -1)
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            HistoryKeyboardActionScheduler.deferToNextMainRunLoop {
                viewModel.moveSelection(by: 1)
            }
            return .handled
        }
        .onKeyPress(.return) {
            HistoryKeyboardActionScheduler.deferToNextMainRunLoop {
                if canPaste, viewModel.selectedEntry != nil {
                    pasteSelection()
                }
            }
            return .handled
        }
        .onKeyPress(.escape) {
            HistoryKeyboardActionScheduler.deferToNextMainRunLoop {
                close()
            }
            return .handled
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
                List(entries) { entry in
                HStack(alignment: .top, spacing: 12) {
                    Text(entry.text)
                        .lineLimit(3)
                        .textSelection(.enabled)
                    Spacer(minLength: 8)
                    Button("Delete", role: .destructive) {
                        viewModel.delete(entry)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 3)
                .contentShape(Rectangle())
                .onTapGesture { viewModel.select(id: entry.id) }
                .listRowBackground(viewModel.selectedEntryID == entry.id ? Color.accentColor.opacity(0.18) : Color.clear)
            }
            .listStyle(.inset)
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
}

/// Keeps keyboard-driven state and window changes outside SwiftUI's current view-update transaction.
private enum HistoryKeyboardActionScheduler {
    static func deferToNextMainRunLoop(_ action: @escaping () -> Void) {
        RunLoop.main.perform(inModes: [.common]) {
            action()
        }
    }
}

struct PasteStackPlaceholderView: View {
    var body: some View {
        PlaceholderSurface(
            title: "Paste Stack",
            message: "Paste Stack collection starts in a later implementation slice."
        )
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

private struct PlaceholderSurface: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
