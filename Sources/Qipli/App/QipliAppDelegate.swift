import AppKit

@main
final class QipliAppDelegate: NSObject, NSApplicationDelegate {
    private var shell: ApplicationShell?

    static func main() {
        let application = NSApplication.shared
        let delegate = QipliAppDelegate()
        application.setActivationPolicy(.accessory)
        application.delegate = delegate

        withExtendedLifetime(delegate) {
            application.run()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        shell = ApplicationShell()
        shell?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        shell?.stop()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        shell?.refreshSystemPermissions()
    }
}
