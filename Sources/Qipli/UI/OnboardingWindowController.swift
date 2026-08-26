import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let viewModel: OnboardingViewModel
    private let settingsViewModel: SettingsViewModel
    private let permissionService: AccessibilityPermissionService
    private let applicationActivator: QipliApplicationActivating
    private let requestAccessibilityAccess: () -> Void
    private let openAccessibilitySettings: () -> Void
    private let completeFirstRun: () -> Void
    private var window: NSWindow?
    private var activeMode: OnboardingPresentationMode?
    private var suppressCloseCompletion = false

    private(set) var windowCreationCount = 0

    init(
        viewModel: OnboardingViewModel? = nil,
        settingsViewModel: SettingsViewModel,
        permissionService: AccessibilityPermissionService,
        applicationActivator: QipliApplicationActivating? = nil,
        requestAccessibilityAccess: @escaping () -> Void,
        openAccessibilitySettings: @escaping () -> Void,
        completeFirstRun: @escaping () -> Void
    ) {
        self.viewModel = viewModel ?? OnboardingViewModel()
        self.settingsViewModel = settingsViewModel
        self.permissionService = permissionService
        self.applicationActivator = applicationActivator ?? SystemQipliApplicationActivator()
        self.requestAccessibilityAccess = requestAccessibilityAccess
        self.openAccessibilitySettings = openAccessibilitySettings
        self.completeFirstRun = completeFirstRun
    }

    var managedWindow: NSWindow? { window }
    var currentStep: OnboardingStep { viewModel.step }

    func show(mode: OnboardingPresentationMode) {
        activeMode = mode
        viewModel.begin(mode: mode)
        permissionService.refresh()
        settingsViewModel.refresh()

        let onboardingWindow = window ?? makeWindow()
        if window == nil {
            window = onboardingWindow
            windowCreationCount += 1
            onboardingWindow.center()
        }
        onboardingWindow.makeKeyAndOrderFront(nil)
        applicationActivator.requestUserInitiatedActivation()
    }

    func refresh() {
        permissionService.refresh()
        settingsViewModel.refresh()
    }

    func skip() {
        dismissFromUserAction()
    }

    func finish() {
        dismissFromUserAction()
    }

    func closeWithoutCompleting() {
        guard let window else { return }
        suppressCloseCompletion = true
        window.close()
        self.window = nil
        activeMode = nil
        suppressCloseCompletion = false
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        let mode = activeMode
        activeMode = nil
        guard !suppressCloseCompletion, mode == .firstRun else { return }
        completeFirstRun()
    }

    private func dismissFromUserAction() {
        let mode = activeMode
        if let window {
            suppressCloseCompletion = true
            window.close()
            self.window = nil
            suppressCloseCompletion = false
        }
        activeMode = nil
        if mode == .firstRun {
            completeFirstRun()
        }
    }

    private func makeWindow() -> NSWindow {
        let onboardingWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 570),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        onboardingWindow.title = "Welcome to Qipli"
        onboardingWindow.titleVisibility = .hidden
        onboardingWindow.titlebarAppearsTransparent = true
        onboardingWindow.titlebarSeparatorStyle = .none
        onboardingWindow.isMovableByWindowBackground = true
        onboardingWindow.isOpaque = true
        onboardingWindow.backgroundColor = .windowBackgroundColor
        onboardingWindow.isReleasedWhenClosed = false
        onboardingWindow.tabbingMode = .disallowed
        onboardingWindow.delegate = self
        onboardingWindow.contentView = NSHostingView(
            rootView: OnboardingRootView(
                viewModel: viewModel,
                settingsViewModel: settingsViewModel,
                permissionService: permissionService,
                requestAccessibilityAccess: requestAccessibilityAccess,
                openAccessibilitySettings: openAccessibilitySettings,
                back: { [weak viewModel] in viewModel?.goBack() },
                continueForward: { [weak viewModel] in viewModel?.continueForward() },
                skip: { [weak self] in self?.skip() },
                finish: { [weak self] in self?.finish() }
            )
        )
        return onboardingWindow
    }
}

private struct OnboardingRootView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var permissionService: AccessibilityPermissionService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let requestAccessibilityAccess: () -> Void
    let openAccessibilitySettings: () -> Void
    let back: () -> Void
    let continueForward: () -> Void
    let skip: () -> Void
    let finish: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                OnboardingVisualPane(step: viewModel.step)
                    .id(viewModel.step)
                    .transition(.opacity)
            }
            .frame(width: 270)
            .clipped()

            VStack(alignment: .leading, spacing: 0) {
                OnboardingProgressView(step: viewModel.step)

                ZStack(alignment: .topLeading) {
                    currentScreen
                        .id(viewModel.step)
                        .transition(screenTransition)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()

                OnboardingFooter(
                    step: viewModel.step,
                    back: back,
                    continueForward: continueForward,
                    skip: skip,
                    finish: finish
                )
            }
            .padding(.horizontal, 34)
            .padding(.top, 48)
            .padding(.bottom, 30)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea()
        .frame(minWidth: 800, minHeight: 550)
        .animation(screenAnimation, value: viewModel.step)
    }

    @ViewBuilder
    private var currentScreen: some View {
        switch viewModel.step {
        case .welcome:
            OnboardingWelcomeView()
        case .accessibility:
            OnboardingAccessibilityView(
                permissionService: permissionService,
                requestAccessibilityAccess: requestAccessibilityAccess,
                openAccessibilitySettings: openAccessibilitySettings
            )
        case .launchAtLogin:
            OnboardingLaunchAtLoginView(viewModel: settingsViewModel)
        case .shortcuts:
            OnboardingShortcutsView(snapshot: settingsViewModel.shortcuts)
        }
    }

    private var screenTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let insertionEdge: Edge = viewModel.navigationDirection == .forward ? .trailing : .leading
        let removalEdge: Edge = viewModel.navigationDirection == .forward ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertionEdge).combined(with: .opacity),
            removal: .move(edge: removalEdge).combined(with: .opacity)
        )
    }

    private var screenAnimation: Animation {
        if reduceMotion {
            return .timingCurve(0.23, 1, 0.32, 1, duration: 0.20)
        }
        return .timingCurve(0.77, 0, 0.175, 1, duration: 0.22)
    }
}

private struct OnboardingVisualPane: View {
    let step: OnboardingStep
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.20),
                    Color.accentColor.opacity(0.08),
                    Color(nsColor: .controlBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.accentColor.opacity(0.10))
                .frame(width: 250, height: 250)
                .offset(x: -80, y: -170)

            Circle()
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.55))
                .frame(width: 210, height: 210)
                .offset(x: 110, y: 190)

            VStack(spacing: 22) {
                Spacer()

                ZStack {
                    if reduceTransparency {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    } else {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(.thinMaterial)
                    }

                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color(nsColor: .windowBackgroundColor).opacity(0.75), lineWidth: 1)

                    Image(systemName: step.symbolName)
                        .font(.system(size: 52, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 116, height: 116)
                .shadow(color: Color.accentColor.opacity(0.14), radius: 18, x: 0, y: 10)

                VStack(spacing: 7) {
                    Text("Qipli")
                        .font(.system(size: 19, weight: .semibold))
                    Text(step.visualCaption)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 28)

                Spacer()
            }
            .padding(.vertical, 44)
        }
        .accessibilityHidden(true)
    }
}

private struct OnboardingProgressView: View {
    let step: OnboardingStep

    var body: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { item in
                Circle()
                    .fill(item == step ? Color.accentColor : Color.secondary.opacity(0.24))
                    .frame(width: 7, height: 7)
            }
            Spacer()
        }
        .padding(.bottom, 26)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Setup progress, step \(step.position) of \(OnboardingStep.allCases.count)")
    }
}

private struct OnboardingFooter: View {
    let step: OnboardingStep
    let back: () -> Void
    let continueForward: () -> Void
    let skip: () -> Void
    let finish: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button("Skip Setup", action: skip)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityHint("Finish setup without changing the remaining options.")

            Spacer()

            Button("Back", action: back)
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(step.previous == nil)

            if step.next == nil {
                Button("Finish", action: finish)
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Continue", action: continueForward)
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.top, 22)
    }
}

private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isEnabled ? Color.white : Color.secondary)
            .padding(.horizontal, 22)
            .frame(minHeight: 36)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isEnabled ? Color.accentColor : Color.secondary.opacity(0.16))
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(
                .timingCurve(0.23, 1, 0.32, 1, duration: 0.12),
                value: configuration.isPressed
            )
    }
}

private struct OnboardingScreenHeader: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 29, weight: .bold))
                .tracking(-0.6)

            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct OnboardingSurface<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.32), lineWidth: 1)
            }
    }
}

private struct OnboardingInfoRow: View {
    let title: String
    let symbolName: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)
            Text(title)
                .font(.system(size: 13.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct OnboardingWelcomeView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            OnboardingScreenHeader(
                title: "Your clipboard history, on this Mac",
                message: "Qipli keeps a 30-day clipboard history and builds Paste Stacks for repeated work."
            )

            OnboardingSurface {
                VStack(alignment: .leading, spacing: 13) {
                    OnboardingInfoRow(
                        title: "History stays in your local macOS account.",
                        symbolName: "internaldrive"
                    )
                    Divider()
                    OnboardingInfoRow(
                        title: "Qipli has no account and sends no clipboard contents over the network.",
                        symbolName: "network.slash"
                    )
                    Divider()
                    OnboardingInfoRow(
                        title: "Passwords and tokens can appear in history. Delete anything you do not want to keep.",
                        symbolName: "exclamationmark.shield"
                    )
                }
            }
        }
    }
}

private struct OnboardingAccessibilityView: View {
    @ObservedObject var permissionService: AccessibilityPermissionService
    let requestAccessibilityAccess: () -> Void
    let openAccessibilitySettings: () -> Void

    var body: some View {
        let presentation = SettingsAccessibilityPresentation.resolve(
            permissionState: permissionService.state,
            inputStatus: .stopped
        )
        VStack(alignment: .leading, spacing: 24) {
            OnboardingScreenHeader(
                title: "Paste from any app",
                message: "Accessibility enables global shortcuts and sends a chosen item back to the app you were using. History works without it."
            )

            OnboardingSurface {
                HStack(alignment: .top, spacing: 13) {
                    Image(systemName: presentation.symbolName)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(presentation.status)
                            .font(.headline)
                        Text(presentation.explanation)
                            .font(.system(size: 13.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Button(presentation.buttonTitle) {
                switch presentation.action {
                case .requestAccess:
                    requestAccessibilityAccess()
                case .openSettings:
                    openAccessibilitySettings()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityHint(presentation.explanation)
        }
    }
}

private struct OnboardingLaunchAtLoginView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            OnboardingScreenHeader(
                title: "Open Qipli at Login",
                message: "Launch at Login is optional. Qipli changes this setting only when you use the toggle."
            )

            OnboardingSurface {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(
                        "Open Qipli when I sign in",
                        isOn: Binding(
                            get: { viewModel.launchAtLoginIsEnabled },
                            set: { viewModel.setLaunchAtLoginEnabled($0) }
                        )
                    )
                    .toggleStyle(.switch)
                    .disabled(!viewModel.launchAtLoginCanToggle)

                    Text(viewModel.launchAtLoginDescription)
                        .font(.system(size: 13.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                if viewModel.launchAtLoginStatus == .requiresApproval {
                    Button("Open Login Items Settings") {
                        viewModel.openLoginItemsSettings()
                    }
                    .buttonStyle(.bordered)
                }
                if viewModel.launchAtLoginStatus == .notFound {
                    Button("Check Again") {
                        viewModel.refresh()
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let error = viewModel.launchAtLoginError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Launch at Login error: \(error)")
            }
        }
    }
}

private struct OnboardingShortcutsView: View {
    let snapshot: ShortcutSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            OnboardingScreenHeader(
                title: "Qipli shortcuts",
                message: "Use these from any app. The first three can be changed later in Settings."
            )

            OnboardingSurface {
                VStack(spacing: 0) {
                    ForEach(Array(ShortcutCommand.allCases.enumerated()), id: \.element.rawValue) { index, command in
                        OnboardingShortcutRow(
                            title: command.title,
                            shortcut: snapshot.binding(for: command).displayValue,
                            accessibilityShortcut: snapshot.binding(for: command).displayValue
                        )
                        if index < ShortcutCommand.allCases.count - 1 {
                            Divider()
                        }
                    }

                    Divider()
                    OnboardingShortcutRow(
                        title: "Paste next Stack item",
                        shortcut: "⌘V",
                        accessibilityShortcut: "Command V"
                    )
                    Divider()
                    OnboardingShortcutRow(
                        title: "Cancel active Paste Stack",
                        shortcut: "Esc",
                        accessibilityShortcut: "Escape"
                    )
                }
            }

            Text("Command-V and Escape are fixed Paste Stack actions.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct OnboardingShortcutRow: View {
    let title: String
    let shortcut: String
    let accessibilityShortcut: String

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.system(size: 13.5))
            Spacer()
            Text(shortcut)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.09))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(accessibilityShortcut)")
    }
}

private extension OnboardingStep {
    var symbolName: String {
        switch self {
        case .welcome: "clipboard"
        case .accessibility: "lock.shield"
        case .launchAtLogin: "power"
        case .shortcuts: "command"
        }
    }

    var visualCaption: String {
        switch self {
        case .welcome: "Stored on this Mac"
        case .accessibility: "Access only when you allow it"
        case .launchAtLogin: "Off until you enable it"
        case .shortcuts: "Available from any app"
        }
    }
}
