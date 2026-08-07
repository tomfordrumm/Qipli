import AppKit

@main
final class QipliAppDelegate: NSObject, NSApplicationDelegate {
    private var shell: ApplicationShell?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        shell = ApplicationShell()
        shell?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        shell?.stop()
    }
}
