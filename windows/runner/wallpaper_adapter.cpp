#include "wallpaper_adapter.h"

#include <windows.h>
#include <shobjidl.h>
#include <wrl/client.h>
#include <algorithm>
#include <string>
#include <vector>

namespace {
struct Monitor {
  std::wstring id;
  bool primary;
};

std::string Utf8(const std::wstring& value) {
  if (value.empty()) return {};
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.data(),
      static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
  std::string output(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
      output.data(), size, nullptr, nullptr);
  return output;
}

void Fail(flutter::MethodResult<flutter::EncodableValue>* result,
          const char* stage, HRESULT hr) {
  result->Error(stage, std::string(stage) + " (HRESULT " +
      std::to_string(static_cast<long>(hr)) + ")");
}
}  // namespace

void HandleWallpaperCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const bool reading = call.method_name() == "getWallpaperPaths";
  if (!reading && call.method_name() != "setWallpaper") {
    result->NotImplemented();
    return;
  }
  Microsoft::WRL::ComPtr<IDesktopWallpaper> desktop;
  auto hr = CoCreateInstance(CLSID_DesktopWallpaper, nullptr, CLSCTX_ALL,
                            IID_PPV_ARGS(desktop.GetAddressOf()));
  if (FAILED(hr)) { Fail(result.get(), "DESKTOP_UNAVAILABLE", hr); return; }
  UINT count = 0;
  hr = desktop->GetMonitorDevicePathCount(&count);
  if (FAILED(hr)) { Fail(result.get(), "MONITOR_READ_FAILED", hr); return; }
  std::vector<Monitor> monitors;
  for (UINT i = 0; i < count; ++i) {
    LPWSTR id = nullptr;
    hr = desktop->GetMonitorDevicePathAt(i, &id);
    if (FAILED(hr)) { Fail(result.get(), "MONITOR_READ_FAILED", hr); return; }
    std::wstring monitor_id(id);
    CoTaskMemFree(id);
    RECT rect{};
    hr = desktop->GetMonitorRECT(monitor_id.c_str(), &rect);
    if (FAILED(hr)) { Fail(result.get(), "MONITOR_READ_FAILED", hr); return; }
    // A disconnected monitor can still reference a wallpaper; keep its path.
    const bool primary = hr == S_OK && rect.left == 0 && rect.top == 0;
    monitors.push_back({monitor_id, primary});
  }
  std::stable_sort(monitors.begin(), monitors.end(),
      [](const Monitor& a, const Monitor& b) { return a.primary > b.primary; });
  if (monitors.empty() || !monitors.front().primary) {
    result->Error("NO_PRIMARY_DISPLAY", "No primary desktop is available");
    return;
  }
  if (reading) {
    flutter::EncodableList paths;
    for (const auto& monitor : monitors) {
      LPWSTR path = nullptr;
      hr = desktop->GetWallpaper(monitor.id.c_str(), &path);
      if (FAILED(hr)) { Fail(result.get(), "READ_FAILED", hr); return; }
      paths.emplace_back(Utf8(path ? path : L""));
      CoTaskMemFree(path);
    }
    result->Success(flutter::EncodableValue(paths));
    return;
  }
  const auto* args = call.arguments()
      ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
  const std::string* path = nullptr;
  if (args) {
    const auto it = args->find(flutter::EncodableValue("path"));
    if (it != args->end()) path = std::get_if<std::string>(&it->second);
  }
  if (!path || path->empty() || path->find('\0') != std::string::npos) {
    result->Error("INVALID_PATH", "A nonempty wallpaper path is required");
    return;
  }
  const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
      path->data(), static_cast<int>(path->size()), nullptr, 0);
  if (!size) { result->Error("INVALID_PATH", "Invalid UTF-8 path"); return; }
  std::wstring wide(size, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path->data(),
      static_cast<int>(path->size()), wide.data(), size);
  const DWORD attributes = GetFileAttributesW(wide.c_str());
  if (attributes == INVALID_FILE_ATTRIBUTES ||
      (attributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT))) {
    result->Error("INVALID_PATH", "Wallpaper must be an existing regular file");
    return;
  }
  hr = desktop->SetWallpaper(monitors.front().id.c_str(), wide.c_str());
  if (FAILED(hr)) { Fail(result.get(), "APPLY_FAILED", hr); return; }
  result->Success(flutter::EncodableValue(true));
}
