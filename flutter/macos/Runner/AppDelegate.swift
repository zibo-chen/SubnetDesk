import Cocoa
import FlutterMacOS

@_silgen_name("subnetdesk_shutdown")
private func subnetdesk_shutdown()

@main
class AppDelegate: FlutterAppDelegate {
    var launched = false;

    override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // https://github.com/leanflutter/window_manager/issues/214
    return false
  }
    
    override func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        if (launched) {
            (NSApplication.shared.windows.first { $0 is MainFlutterWindow } as? MainFlutterWindow)?.reopenMainWindow()
        }
        return true
    }
    
    override func applicationDidFinishLaunching(_ aNotification: Notification) {
        launched = true;
        if !ProcessInfo.processInfo.arguments.contains("--background") {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    override func applicationWillTerminate(_ notification: Notification) {
        subnetdesk_shutdown()
    }
}
