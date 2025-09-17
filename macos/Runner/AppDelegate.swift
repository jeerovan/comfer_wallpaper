import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate, NSWindowDelegate {
  var mainWindow: NSWindow?  // Keep a reference to main window
  private var methodChannel: FlutterMethodChannel?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)

    // Capture main window pointer
    if let window = NSApplication.shared.windows.first {
      mainWindow = window
      mainWindow?.delegate = self
    }
  
  }

  // Intercept window close on macOS, hide instead of close
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    sender.orderOut(nil)  // Hide window
    return false          // Prevent closing
  }
  
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
