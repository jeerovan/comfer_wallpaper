import Cocoa
import FlutterMacOS
import ServiceManagement

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    // Installer operations are explicit. Normal launches never re-enable a
    // login item the user disabled in System Settings.
    let arguments = ProcessInfo.processInfo.arguments
    if arguments.contains("--enable-startup") || arguments.contains("--disable-startup") {
      do {
        if arguments.contains("--enable-startup") {
          if SMAppService.mainApp.status == .notRegistered || SMAppService.mainApp.status == .notFound {
            try SMAppService.mainApp.register()
          }
          guard SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval else {
            fputs("Login registration did not become available.\n", stderr)
            exit(1)
          }
        } else {
          if SMAppService.mainApp.status != .notRegistered && SMAppService.mainApp.status != .notFound {
            try SMAppService.mainApp.unregister()
          }
        }
        print("Login startup status: \(SMAppService.mainApp.status.rawValue)")
        exit(0)
      } catch {
        fputs("Login startup failed: \(error.localizedDescription)\n", stderr)
        exit(1)
      }
    }
    if arguments.contains("--startup-status") {
      print("\(SMAppService.mainApp.status.rawValue)")
      exit(0)
    }
    super.applicationDidFinishLaunching(notification)
    NSApp.setActivationPolicy(.accessory)
    mainFlutterWindow?.orderOut(nil)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
