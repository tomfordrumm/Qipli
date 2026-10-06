import AppKit

/// Standalone synthetic test utility; never starts Qipli's ApplicationShell.
@main
final class S037ProbeApp: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = S037ProbeApp()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !S037PlatformProbe.launchIfRequested(arguments: ProcessInfo.processInfo.arguments) {
            NSApp.terminate(nil)
        }
    }
}
