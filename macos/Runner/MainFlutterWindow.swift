import Cocoa
import FlutterMacOS
import ServiceManagement

class MainFlutterWindow: NSWindow {
  private var wallpaperChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let commands = ["--enable-startup", "--disable-startup", "--startup-status"]
    if ProcessInfo.processInfo.arguments.contains(where: { commands.contains($0) }) {
      super.awakeFromNib()
      return
    }
    let project = FlutterDartProject()
    project.dartEntrypointArguments = Array(ProcessInfo.processInfo.arguments.dropFirst())
    let engine = FlutterEngine(name: "comfer-background", project: project, allowHeadlessExecution: true)
    let controller = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    contentViewController = controller
    setFrame(frame, display: false)
    wallpaperChannel = FlutterMethodChannel(
      name: "comfer.jeerovan.com/wallpaper", binaryMessenger: controller.engine.binaryMessenger)
    wallpaperChannel?.setMethodCallHandler { call, result in
      switch call.method {
      case "getLoginStartup":
        result(["status": SMAppService.mainApp.status.rawValue,
                "installed": self.isInstalledApplication])
      case "enableLoginStartup":
        guard self.isInstalledApplication else {
          result(FlutterError(code: "INSTALL_FIRST", message: "Move Comfer to Applications first", details: nil))
          return
        }
        do {
          let service = SMAppService.mainApp
          if service.status == .notRegistered || service.status == .notFound {
            try service.register()
          }
          result(nil)
        } catch {
          result(FlutterError(code: "STARTUP_FAILED", message: error.localizedDescription, details: nil))
        }
      case "openLoginSettings":
        SMAppService.openSystemSettingsLoginItems()
        result(nil)
      case "getWallpaperPaths":
        guard !NSScreen.screens.isEmpty else {
          result(FlutterError(code: "NO_DISPLAY", message: "No desktop display is available", details: nil))
          return
        }
        result(NSScreen.screens.compactMap { NSWorkspace.shared.desktopImageURL(for: $0)?.path })
      case "setWallpaper":
        guard let args = call.arguments as? [String: Any], let path = args["path"] as? String,
              let screen = NSScreen.screens.first else {
          result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing image or desktop display", details: nil))
          return
        }
        do {
          try NSWorkspace.shared.setDesktopImageURL(URL(fileURLWithPath: path), for: screen, options: [:])
          result(true)
        } catch {
          result(FlutterError(code: "APPLY_FAILED", message: error.localizedDescription, details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    RegisterGeneratedPlugins(registry: controller)
    engine.run(withEntrypoint: nil)
    super.awakeFromNib()
    orderOut(nil)
  }

  private var isInstalledApplication: Bool {
    let appPath = Bundle.main.bundleURL.resolvingSymlinksInPath().path
    let userApplications = FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask).first
    let roots = ["/Applications", userApplications?.resolvingSymlinksInPath().path].compactMap { $0 }
    return roots.contains { appPath.hasPrefix($0 + "/") }
  }
}
