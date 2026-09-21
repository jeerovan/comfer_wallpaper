#include "flutter_window.h"

#include <optional>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  wallpaper_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "comfer.jeerovan.com/wallpaper",
      &flutter::StandardMethodCodec::GetInstance());
  wallpaper_channel_->SetMethodCallHandler([](const auto& call, auto result) {
    if (call.method_name() == "getWallpaperPaths") {
      wchar_t path[32768] = {};
      if (!SystemParametersInfoW(SPI_GETDESKWALLPAPER, 32768, path, 0)) {
        result->Error("READ_FAILED", "Could not read the desktop wallpaper");
        return;
      }
      const int length = WideCharToMultiByte(CP_UTF8, 0, path, -1, nullptr, 0, nullptr, nullptr);
      std::string utf8(length, '\0');
      WideCharToMultiByte(CP_UTF8, 0, path, -1, utf8.data(), length, nullptr, nullptr);
      if (!utf8.empty()) utf8.pop_back();
      result->Success(flutter::EncodableValue(flutter::EncodableList{flutter::EncodableValue(utf8)}));
    } else if (call.method_name() == "setWallpaper") {
      const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
      if (!args) { result->Error("INVALID_ARGUMENTS", "Missing wallpaper path"); return; }
      const auto it = args->find(flutter::EncodableValue("path"));
      const auto* path = it == args->end() ? nullptr : std::get_if<std::string>(&it->second);
      if (!path) { result->Error("INVALID_ARGUMENTS", "Missing wallpaper path"); return; }
      const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path->c_str(), -1, nullptr, 0);
      if (!length) { result->Error("INVALID_PATH", "Invalid UTF-8 path"); return; }
      std::wstring wide(length, L'\0');
      MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path->c_str(), -1, wide.data(), length);
      if (!SystemParametersInfoW(SPI_SETDESKWALLPAPER, 0, wide.data(), SPIF_UPDATEINIFILE | SPIF_SENDCHANGE)) {
        result->Error("APPLY_FAILED", "Windows refused the wallpaper"); return;
      }
      result->Success(flutter::EncodableValue(true));
    } else {
      result->NotImplemented();
    }
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // The controller explicitly shows a window only for a fallback/error.

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  wallpaper_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
