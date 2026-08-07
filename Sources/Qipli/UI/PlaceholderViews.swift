import SwiftUI

struct HistoryPlaceholderView: View {
    var body: some View {
        PlaceholderSurface(
            title: "History",
            message: "History capture starts in the next implementation slice."
        )
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
