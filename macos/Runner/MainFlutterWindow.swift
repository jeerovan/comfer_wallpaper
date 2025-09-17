import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Set up the method channel
    
    let wallpaperChannel = FlutterMethodChannel(name: "comfer.jeerovan.com/wallpaper",
                                            binaryMessenger: flutterViewController.engine.binaryMessenger)
    wallpaperChannel.setMethodCallHandler { (call, result) in
      if call.method == "setWallpaper" {
        if let args = call.arguments as? [String: Any],
            let path = args["path"] as? String {
          let success = self.setWallpaper(at: path)
          result(success)
        } else {
          result(FlutterError(code: "INVALID_ARGUMENTS",
                              message: "Missing path argument",
                              details: nil))
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  // Method to set wallpaper
  func setWallpaper(at path: String) -> Bool {
    let workspace = NSWorkspace.shared
    let screen = NSScreen.main!
    let fileURL = URL(fileURLWithPath: path)

    do {
      try workspace.setDesktopImageURL(fileURL, for: screen, options: [:])
      return true
    } catch {
      print("Error setting wallpaper: \(error)")
      return false
    }
  }
}
