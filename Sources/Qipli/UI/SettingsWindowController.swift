import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let viewModel: SettingsViewModel
    private let permissionService: AccessibilityPermissionService
    private let requestAccessibilityAccess: () -> Void
    private let openAccessibilitySettings: () -> Void
    private let refreshSystemState: () -> GlobalInputStatus
    private let showOnboarding: () -> Void
    private let applicationActivator: QipliApplicationActivating
    private var window: NSWindow?

    private(set) var windowCreationCount = 0

    init(
        viewModel: SettingsViewModel,
        permissionService: AccessibilityPermissionService,
        applicationActivator: QipliApplicationActivating? = nil,
        requestAccessibilityAccess: @escaping () -> Void,
        openAccessibilitySettings: @escaping () -> Void,
        refreshSystemState: @escaping () -> GlobalInputStatus,
        showOnboarding: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.permissionService = permissionService
        self.requestAccessibilityAccess = requestAccessibilityAccess
        self.openAccessibilitySettings = openAccessibilitySettings
        self.refreshSystemState = refreshSystemState
        self.showOnboarding = showOnboarding
        self.applicationActivator = applicationActivator ?? SystemQipliApplicationActivator()
    }

    var managedWindow: NSWindow? { window }

    func show(section: SettingsSection? = nil) {
        if let section {
            viewModel.select(section)
        }
        let inputStatus = refreshSystemState()
        viewModel.refresh(inputStatus: inputStatus)

        let settingsWindow = window ?? makeWindow()
        if window == nil {
            window = settingsWindow
            windowCreationCount += 1
            settingsWindow.center()
        }
        settingsWindow.makeKeyAndOrderFront(nil)
        applicationActivator.requestUserInitiatedActivation()
    }

    func refresh() {
        viewModel.refresh(inputStatus: refreshSystemState())
    }

    func close() {
        window?.close()
        window = nil
    }

    private func makeWindow() -> NSWindow {
        let settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        settingsWindow.title = "Qipli Settings"
        settingsWindow.isReleasedWhenClosed = false
        settingsWindow.tabbingMode = .disallowed
        settingsWindow.contentView = NSHostingView(
            rootView: SettingsRootView(
                viewModel: viewModel,
                permissionService: permissionService,
                requestAccessibilityAccess: requestAccessibilityAccess,
                openAccessibilitySettings: openAccessibilitySettings,
                showOnboarding: showOnboarding
            )
        )
        return settingsWindow
    }
}

private struct SettingsRootView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var permissionService: AccessibilityPermissionService
    let requestAccessibilityAccess: () -> Void
    let openAccessibilitySettings: () -> Void
    let showOnboarding: () -> Void

    var body: some View {
        TabView(selection: $viewModel.selectedSection) {
            GeneralSettingsView(
                viewModel: viewModel,
                permissionService: permissionService,
                requestAccessibilityAccess: requestAccessibilityAccess,
                openAccessibilitySettings: openAccessibilitySettings,
                showOnboarding: showOnboarding
            )
            .tabItem { Label("General", systemImage: "gearshape") }
            .tag(SettingsSection.general)

            ShortcutSettingsView(viewModel: viewModel)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(SettingsSection.shortcuts)
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 400)
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var permissionService: AccessibilityPermissionService
    let requestAccessibilityAccess: () -> Void
    let openAccessibilitySettings: () -> Void
    let showOnboarding: () -> Void

    var body: some View {
        Form {
            Section("Accessibility") {
                let presentation = SettingsAccessibilityPresentation.resolve(
                    permissionState: permissionService.state,
                    inputStatus: viewModel.inputStatus
                )
                LabeledContent("Status") {
                    Label(presentation.status, systemImage: presentation.symbolName)
                }
                Text(presentation.explanation)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(presentation.buttonTitle) {
                    switch presentation.action {
                    case .requestAccess:
                        requestAccessibilityAccess()
                    case .openSettings:
                        openAccessibilitySettings()
                    }
                }
                .accessibilityHint(presentation.explanation)
            }

            Section("Launch at Login") {
                Toggle(
                    "Open Qipli when I sign in",
                    isOn: Binding(
                        get: { viewModel.launchAtLoginIsEnabled },
                        set: { viewModel.setLaunchAtLoginEnabled($0) }
                    )
                )
                .disabled(!viewModel.launchAtLoginCanToggle)
                Text(viewModel.launchAtLoginDescription)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if viewModel.launchAtLoginStatus == .requiresApproval {
                    Button("Open Login Items Settings") {
                        viewModel.openLoginItemsSettings()
                    }
                }
                if viewModel.launchAtLoginStatus == .notFound {
                    Button("Check Again") {
                        viewModel.refresh()
                    }
                }
                if let error = viewModel.launchAtLoginError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Launch at Login error: \(error)")
                }
            }

            Section("Onboarding") {
                Button("Show Onboarding Again", action: showOnboarding)
                Text("Review Qipli's privacy, permission, login, and shortcut setup without resetting your choices.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ShortcutSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var recordingCommand: ShortcutCommand?

    var body: some View {
        Form {
            Section {
                Text("Qipli applies all three shortcuts together. Command-V and Escape keep their existing Paste Stack behavior.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Qipli commands") {
                ForEach(ShortcutCommand.allCases, id: \.rawValue) { command in
                    VStack(alignment: .leading, spacing: 5) {
                        LabeledContent(command.title) {
                            ShortcutRecorderField(
                                displayValue: viewModel.shortcuts.binding(for: command).displayValue,
                                isRecording: recordingCommand == command,
                                beginRecording: { recordingCommand = command },
                                cancelRecording: { recordingCommand = nil },
                                capture: { binding in
                                    viewModel.updateShortcut(command, binding: binding)
                                    recordingCommand = nil
                                }
                            )
                            .frame(width: 132, height: 26)
                        }
                        if viewModel.shortcutErrorCommand == command,
                           let error = viewModel.shortcutError {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Shortcut error: \(error)")
                        }
                    }
                }
            }

            Section {
                if viewModel.recoveredShortcutDefaults {
                    Label(
                        "Saved shortcuts were invalid, so Qipli restored the defaults.",
                        systemImage: "arrow.counterclockwise"
                    )
                    .foregroundStyle(.secondary)
                }
                Button("Reset to Defaults") {
                    viewModel.resetShortcuts()
                    recordingCommand = nil
                }
                .disabled(viewModel.shortcuts == .defaults)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ShortcutRecorderField: NSViewRepresentable {
    let displayValue: String
    let isRecording: Bool
    let beginRecording: () -> Void
    let cancelRecording: () -> Void
    let capture: (ShortcutBinding) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.onBeginRecording = beginRecording
        button.onCancelRecording = cancelRecording
        button.onCapture = capture
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.onBeginRecording = beginRecording
        button.onCancelRecording = cancelRecording
        button.onCapture = capture
        button.update(displayValue: displayValue, isRecording: isRecording)
    }
}

private final class ShortcutRecorderButton: NSButton {
    var onBeginRecording: (() -> Void)?
    var onCancelRecording: (() -> Void)?
    var onCapture: ((ShortcutBinding) -> Void)?
    private var isRecording = false

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        target = self
        action = #selector(beginRecording)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(displayValue: String, isRecording: Bool) {
        self.isRecording = isRecording
        title = isRecording ? "Type shortcut…" : displayValue
        setAccessibilityLabel("Shortcut")
        setAccessibilityValue(isRecording ? "Recording" : displayValue)
        setAccessibilityHelp(isRecording ? "Press a key with Command, Control, or Option." : "Press to record a new shortcut.")
        if isRecording {
            window?.makeFirstResponder(self)
        }
    }

    @objc private func beginRecording() {
        onBeginRecording?()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == UInt16(kVK_Escape) {
            onCancelRecording?()
            return
        }
        onCapture?(ShortcutBinding.from(event: event))
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        onCapture?(ShortcutBinding.from(event: event))
        return true
    }

    override func cancelOperation(_ sender: Any?) {
        if isRecording {
            onCancelRecording?()
        } else {
            super.cancelOperation(sender)
        }
    }
}

struct SettingsAccessibilityPresentation {
    enum Action {
        case requestAccess
        case openSettings
    }

    let status: String
    let explanation: String
    let symbolName: String
    let buttonTitle: String
    let action: Action

    static func resolve(
        permissionState: AccessibilityPermissionState,
        inputStatus: GlobalInputStatus
    ) -> Self {
        if case let .unavailable(message) = inputStatus {
            return Self(
                status: "Global input unavailable",
                explanation: message,
                symbolName: "exclamationmark.triangle",
                buttonTitle: "Open System Settings",
                action: .openSettings
            )
        }

        switch permissionState {
        case .notRequested:
            return Self(
                status: "Access needed",
                explanation: permissionState.explanation,
                symbolName: "lock",
                buttonTitle: "Allow Access",
                action: .requestAccess
            )
        case .denied:
            return Self(
                status: "Access denied",
                explanation: permissionState.explanation,
                symbolName: "lock.slash",
                buttonTitle: "Open System Settings",
                action: .openSettings
            )
        case .granted:
            return Self(
                status: "Access enabled",
                explanation: permissionState.explanation,
                symbolName: "checkmark.circle",
                buttonTitle: "Open System Settings",
                action: .openSettings
            )
        }
    }
}
