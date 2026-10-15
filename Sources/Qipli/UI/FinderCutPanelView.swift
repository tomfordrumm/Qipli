import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum FinderCutPresentationState {
    case hidden, compact, dismissing
}

/// Finder Cut is a status surface, with no expansion or hover transitions.
@MainActor
final class FinderCutPresentationModel: ObservableObject {
    @Published private(set) var state: FinderCutPresentationState = .hidden
    @Published private(set) var compactGeometry: PasteStackCompactGeometry?
    private(set) var generation = 0
    var onDismiss: ((Int) -> Void)?

    func beginSession(geometry: PasteStackCompactGeometry) {
        generation &+= 1
        compactGeometry = geometry
        state = .compact
    }

    func updateGeometry(_ geometry: PasteStackCompactGeometry) {
        if compactGeometry != geometry { compactGeometry = geometry }
    }

    func requestDismissal() {
        guard state == .compact else { return }
        generation &+= 1
        state = .dismissing
        onDismiss?(generation)
    }

    func finishDismissal(token: Int) {
        guard isCurrent(token: token, state: .dismissing) else { return }
        close()
    }

    func isCurrent(token: Int, state expectedState: FinderCutPresentationState) -> Bool {
        generation == token && state == expectedState
    }

    func close() {
        generation &+= 1
        state = .hidden
        compactGeometry = nil
    }
}

extension FinderCutSessionState {
    /// Status replaces the filename when a selection is no longer actionable.
    var compactStatusMessage: String? {
        switch self {
        case .failed: "Move unavailable. Cut again."
        case .blockedByPasteStack: "Finish Paste Stack first."
        case .handedOff: "Command sent to Finder"
        case .idle, .preparing, .ready: nil
        }
    }

    var isHandedOff: Bool {
        if case .handedOff = self { return true }
        return false
    }
}

struct FinderCutPanelView: View {
    @ObservedObject var sessionController: FinderCutSessionController
    @ObservedObject var presentationModel: FinderCutPresentationModel
    let close: () -> Void

    var body: some View {
        Group {
            if let geometry = presentationModel.compactGeometry {
                compactPanel(geometry: geometry)
            }
        }
        .accessibilityIdentifier("finder-cut-panel")
    }

    private func compactPanel(geometry: PasteStackCompactGeometry) -> some View {
        // Status and cancel stay on opposite sides of the hardware camera.
        ZStack(alignment: .topLeading) {
            Image(systemName: compactSymbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(compactSymbolColor)
                .padding(.leading, 6)
                .frame(width: geometry.localLeftContentRect.width, height: geometry.localLeftContentRect.height, alignment: .leading)
                .clipped()
                .offset(x: geometry.localLeftContentRect.minX, y: geometry.panelFrame.height - geometry.localLeftContentRect.maxY)
                .accessibilityHidden(true)
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .padding(.trailing, 6)
                    .frame(width: geometry.localRightContentRect.width, height: geometry.localRightContentRect.height, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: geometry.localRightContentRect.width, height: geometry.localRightContentRect.height)
            .offset(x: geometry.localRightContentRect.minX, y: geometry.panelFrame.height - geometry.localRightContentRect.maxY)
            .accessibilityLabel(sessionController.state.isHandedOff ? "Close Finder move status" : "Cancel Finder move")
            .accessibilityHint(sessionController.state.isHandedOff
                ? "Closes this notice. The operation in Finder continues."
                : "Cancels the pending move. Source files stay in place.")
            .help(sessionController.state.isHandedOff ? "Close status" : "Cancel move")
            compactFilename
                .padding(.horizontal, 16)
                .padding(.bottom, 5)
                .frame(width: geometry.panelFrame.width, height: PasteStackCompactGeometry.finderCutFilenameRowHeight)
                .offset(y: geometry.panelFrame.height - PasteStackCompactGeometry.finderCutFilenameRowHeight)
        }
        .frame(width: geometry.panelFrame.width, height: geometry.panelFrame.height, alignment: .topLeading)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
    }

    private var compactFilename: some View {
        HStack(spacing: 5) {
            if let message = sessionController.state.compactStatusMessage {
                Text(message)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(compactSymbolColor)
            } else {
                Text(sessionController.state.selection?.urls.first?.lastPathComponent ?? sessionController.statusTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if sessionController.itemCount > 1 {
                    Text("+\(sessionController.itemCount - 1) more")
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
        }
        .font(.system(size: 12, weight: .medium))
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(sessionController.statusDetail)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Finder move status")
        .accessibilityValue(compactAccessibilityValue)
    }

    private var compactSymbol: String {
        switch sessionController.state {
        case .blockedByPasteStack, .failed:
            "exclamationmark.triangle.fill"
        case .handedOff:
            "arrow.right.circle.fill"
        default:
            "scissors"
        }
    }

    private var compactSymbolColor: Color {
        switch sessionController.state {
        case .blockedByPasteStack, .failed:
            .yellow
        case .handedOff:
            .green
        default:
            .primary
        }
    }

    private var compactAccessibilityValue: String {
        if sessionController.state.compactStatusMessage != nil {
            return "\(sessionController.statusTitle). \(sessionController.statusDetail)"
        }
        if sessionController.itemCount > 0 {
            return "\(sessionController.statusTitle), \(sessionController.itemCount) items, \(sessionController.state.selection?.urls.first?.lastPathComponent ?? ""). \(sessionController.statusDetail)"
        }
        return sessionController.statusTitle
    }
}

/// Transient correction feedback shares the compact Top Notch surface without
/// borrowing Finder Cut's session, ownership, or cancellation callbacks.
@MainActor
final class LayoutCorrectionNoticeModel: ObservableObject {
    @Published private(set) var message: String?
    @Published private(set) var topInset: CGFloat = 0
    @Published private(set) var width: CGFloat = 440
    private(set) var generation = 0
    private(set) var isDismissing = false
    private var dismissalTask: Task<Void, Never>?
    var onDismiss: ((Int) -> Void)?

    @discardableResult
    func show(_ outcome: LayoutCorrectionOutcome) -> Bool {
        let text: String
        switch outcome {
        case .completed: return false
        case let .denied(value), let .failed(value): text = value
        }
        dismissalTask?.cancel()
        generation &+= 1
        message = text
        isDismissing = false
        let token = generation
        dismissalTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            self?.expire(token: token)
        }
        return true
    }

    func setGeometry(width: CGFloat, topInset: CGFloat) {
        self.width = width
        self.topInset = topInset
    }

    func expire(token: Int) {
        guard generation == token, message != nil, !isDismissing else { return }
        isDismissing = true
        onDismiss?(token)
    }

    func finishDismissal(token: Int) {
        guard generation == token, isDismissing else { return }
        close()
    }

    func close() {
        dismissalTask?.cancel()
        dismissalTask = nil
        generation &+= 1
        message = nil
        isDismissing = false
    }
}

struct LayoutCorrectionNoticeView: View {
    @ObservedObject var model: LayoutCorrectionNoticeModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: model.topInset)
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .accessibilityHidden(true)
                Text(model.message ?? "")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 76)
        }
        .frame(width: model.width, height: model.topInset + 76)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Layout correction")
        .accessibilityValue(model.message ?? "")
    }
}
