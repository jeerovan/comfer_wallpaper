# Comfer Wallpaper release guide

Build dependencies, platform restrictions, packaging, icon requirements, installation/startup behavior, troubleshooting, and recorded validation. For application behavior and data recovery, see [README.md](README.md).

Run commands from the repository root unless stated otherwise. Build native releases on their respective platforms. The current version comes from `pubspec.yaml` (`0.2.0+2`); packaging does not bump it or publish a release. Validation results below are historical observations, not guarantees for a different build host or a new artifact.

- [Linux dependencies, release build, and installation](#linux-release-build-and-installation)
- [Ubuntu /usr/local permission error](#ubuntu-troubleshooting-installation-into-usrlocal)
- [x86-64 AppImage and icon requirements](#build-an-x86-64-appimage)
- [macOS build and installation](#macos-build-and-installation-macos-13)
- [Windows build and installation](#windows-build-and-installation)
- [Validation and known limitations](#release-validation-and-known-limitations)

## Linux release build and installation

Linux release packaging currently targets x86-64 GNOME systems. KDE is unsupported. Keep platform support claims limited to the combinations actually tested below.

Verified host: **Debian 12, x86-64, GNOME 43.9, Wayland**, Flutter 3.41.9 / Dart 3.11.5, Clang 14, GTK 3.24.38 and Ayatana AppIndicator 0.5.90. No OS upgrade was needed. GNOME X11 uses the same adapter but is untested. Other desktops/architectures and native macOS/Windows builds were not revalidated during the Linux work; historical macOS results are recorded below. Both GNOME light/dark background keys must be writable. Missing native libraries prevent launch; missing shell tray support instead shows fallback controls.

Debian build dependencies: `clang cmake ninja-build pkg-config libgtk-3-dev libayatana-appindicator3-dev`. Runtime dependencies include GTK 3, GLib/GIO (`libglib2.0-bin` supplies `gsettings` and `gdbus`), GNOME background schemas/dconf, `libayatana-appindicator3-1`, its DBusMenu libraries, and CA certificates. GNOME needs an AppIndicator shell extension for the tray; this machine has `ubuntu-appindicators@ubuntu.com`.

### Build dependencies on Debian and Ubuntu

Install Flutter separately, then install the native build dependencies:

```sh
sudo apt update
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libayatana-appindicator3-dev
```

For the `tray_manager` error requiring `ayatana-appindicator3-0.1` or `appindicator3-0.1`, use **`libayatana-appindicator3-dev`**. These are pkg-config module names, not apt package names. The `-dev` package supplies headers and build metadata; the runtime-only `libayatana-appindicator3-1` package is insufficient for compilation. The plugin accepts either implementation, so installing both is unnecessary.

If Ubuntu cannot locate the Ayatana development package, enable Universe:

```sh
sudo add-apt-repository universe
sudo apt update
sudo apt install libayatana-appindicator3-dev
```

Confirm detection before rebuilding:

```sh
pkg-config --modversion ayatana-appindicator3-0.1
```

The alternative development package is `libappindicator3-dev`, providing `appindicator3-0.1`; the plugin can use it when Ayatana is unavailable. Which implementation is linked determines the corresponding runtime library required on the destination machine. The dependency setup does not require an OS upgrade. Use sudo for system package installation, not for Flutter builds or application execution.

### Build and install the complete bundle

```sh
flutter pub get
flutter analyze
flutter test
flutter build linux --release
./build/linux/x64/release/bundle/comfer_wallpaper --show
# For login startup, quit Comfer and copy the COMPLETE bundle to a stable path:
mkdir -p "$HOME/.local/opt/comfer-wallpaper"
cp -a build/linux/x64/release/bundle/. "$HOME/.local/opt/comfer-wallpaper/"
"$HOME/.local/opt/comfer-wallpaper/comfer_wallpaper"
```

Alternatively, the existing helper installs the bundle into `${XDG_DATA_HOME:-$HOME/.local/share}/comfer-wallpaper` and adds an application launcher. It leaves startup consent to the app:

```sh
bash packaging/linux/install.sh
# After choosing Quit, uninstall that helper-managed copy:
bash packaging/linux/uninstall.sh
```

The helper path is different from the manual `~/.local/opt/comfer-wallpaper` example. Use the uninstall method corresponding to the installation you chose; both preserve application data.

### Startup, upgrades, and uninstall

First launch offers **Start at login** or **Not now**, and remembers the choice. Build/temporary copies cannot register startup. The per-user entry is `${XDG_CONFIG_HOME:-$HOME/.config}/autostart/com.jeerovan.comfer.desktop`. Its quoted absolute executable path supports spaces and does not use sudo or a shell. `--startup-status`, `--enable-startup`, and `--disable-startup` explicitly manage registration; these commands still need a graphical session for the GTK runner. Normal launches respect deleted entries, `Hidden=true` and `X-GNOME-Autostart-enabled=false`.

Upgrades at the same executable path preserve startup/preferences. After moving the whole bundle, run the new executable with `--enable-startup` only if wanted; it replaces the same entry rather than duplicating it. Quit stops the process without restarting it. The next enabled login can start it again. `--show` applies to a stopped app; duplicate launches exit rather than forwarding commands.

Writable data lives separately under `${XDG_DATA_HOME:-$HOME/.local/share}/com.example.comfer_wallpaper/`, including preferences, wallpaper journal/images, lock and bounded logs. The path-provider plugin may retain a legacy `comfer_wallpaper/` directory. Keep the signed-in graphical session's XDG/dconf environment intact.

Uninstall a manually copied bundle after Quit: run its executable with `--disable-startup`, remove the per-user autostart entry, then remove only the installed bundle directory. Preserve wallpaper/application data until another wallpaper is selected. The existing helper's uninstall command handles its own different bundle location and refuses to remove a running copy.

## Ubuntu troubleshooting: installation into /usr/local

A release build may fail with an error like:

```text
file INSTALL cannot copy file
.../build/linux/x64/release/intermediates_do_not_run/comfer_wallpaper
to /usr/local/comfer_wallpaper: Permission denied
```

This indicates the generated CMake install destination is wrong for the Flutter bundle. A cached or explicitly configured `CMAKE_INSTALL_PREFIX` is a likely cause. In `linux/CMakeLists.txt`, the bundle prefix is selected only when `CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT` is true. The Ubuntu report establishes the incorrect destination, but its precise cache/environment source has not been inspected remotely.

From the repository root, clear the environment override and regenerate the build:

```sh
cd /home/vipi/repos/comfer_wallpaper  # Adjust to your checkout.
unset CMAKE_INSTALL_PREFIX
flutter clean
flutter pub get
flutter build linux --release
```

`flutter clean` removes generated build output; it does not edit application source. Do not work around this error with `sudo flutter build` or by changing permissions on `/usr/local`. The intended executable is:

```text
build/linux/x64/release/bundle/comfer_wallpaper
```

If the build still targets `/usr/local`, correct the generated configuration explicitly from the repository root:

```sh
cmake -S linux -B build/linux/x64/release \
  -DCMAKE_INSTALL_PREFIX="$PWD/build/linux/x64/release/bundle"
flutter build linux --release
```

Inspect the active cache if needed:

```sh
grep '^CMAKE_INSTALL_PREFIX:' build/linux/x64/release/CMakeCache.txt
```

Its value should end with your checkout's `build/linux/x64/release/bundle`, not `/usr/local`. Correct any build wrapper or toolchain that keeps overriding it. Run AppImage packaging only after the release build succeeds. See CMake's [install-prefix documentation](https://cmake.org/cmake/help/latest/variable/CMAKE_INSTALL_PREFIX.html) and [default-prefix initialization rule](https://cmake.org/cmake/help/latest/variable/CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT.html).

## Build an x86-64 AppImage

After building the release, run the packaging script. It works from any working directory and does **not** rebuild Flutter, install packages, register startup, or alter the input bundle.

```sh
flutter build linux --release
APPIMAGETOOL=/absolute/path/to/appimagetool-x86_64.AppImage \
  bash packaging/linux/build-appimage.sh
```

Output: `dist/Comfer_Wallpaper-<pubspec-version>-x86_64.AppImage` (currently `Comfer_Wallpaper-0.2.0+2-x86_64.AppImage`). Existing outputs are never overwritten; remove the previous artifact explicitly or supply `--output`. Only Linux **x86-64 hosts and x86-64 release payloads** are accepted. ARM and cross-packaging are unsupported.

Packaging prerequisites: Bash, Python 3, GNU coreutils and an executable x86-64 [appimagetool](https://github.com/AppImage/appimagetool/releases). For example, download the `appimagetool-x86_64.AppImage` asset from release **1.9.1**, make it executable with `chmod +x`, and set `APPIMAGETOOL` as above. Alternatively, put `appimagetool` on `PATH`. The script uses extraction mode for the packaging tool, so packaging does not require FUSE. The tool may download its type-2 runtime; pass `--runtime-file /path/to/runtime-x86_64` to use a separately downloaded, pinned runtime offline. Pin both tool and runtime for repeatable release tooling.

```sh
bash packaging/linux/build-appimage.sh --help
APPIMAGETOOL=/absolute/path/to/appimagetool-x86_64.AppImage \
  bash packaging/linux/build-appimage.sh \
  --bundle build/linux/x64/release/bundle \
  --app-icon /path/to/app-icon.png \
  --tray-icon /path/to/tray-icon.png \
  --output "$PWD/dist/Comfer Wallpaper-x86_64.AppImage"
```

Icon requirements:

| Use | Script input and default | Required format | Artwork guidance |
|---|---|---|---|
| Application launcher / AppImage file | `--app-icon`; defaults to `assets/comfer_launcher.png` | Square **8-bit RGB or RGBA PNG**, 256×256, **512×512 recommended**, or 1024×1024 | Full-color app identity; transparent background/padding recommended. Avoid tiny text. Embedded as `com.jeerovan.comfer.png` in the AppDir root and hicolor icon directory. |
| System tray / GNOME indicator | `--tray-icon`; defaults to the **built bundle's** `data/flutter_assets/assets/comfer_launcher.png` | Square **8-bit RGB or RGBA PNG**, 32, **64 recommended**, 128, 256 or 512 px | Prefer a dedicated transparent, simple silhouette, legible when scaled to roughly 16–24 logical pixels. Use sufficient contrast on both light and dark panels. This is a normal PNG, not an automatically recolored symbolic/template icon. |

The existing 512×512 RGBA `assets/comfer_launcher.png` satisfies both format requirements. A dedicated tray design is recommended for legibility but is optional. ICO, ICNS, SVG, JPEG, indexed PNG and non-square images are not accepted by this script. Icon dimensions/format are checked; visual contrast and legibility still need review. `--tray-icon` replaces only the staged Linux Flutter asset, leaving the source/build and macOS/Windows icons unchanged. Without an override, changing source icons requires rebuilding Flutter before packaging.

By default the script packages the Flutter bundle only, so host GTK/GLib/AppIndicator libraries are required. Add **`--bundle-deps`** to include GTK 3, GLib, the linked AppIndicator implementation, DBusMenu, GTK/Pixbuf resources, schemas, and GIO backends using linuxdeploy and its GTK plugin. The source release bundle is not modified. Both modes preserve the existing icon overrides and x86-64 checks.

### Bundle GTK and native dependencies

On the Ubuntu/Debian build machine, install these additional packaging dependencies alongside the Flutter build dependencies above:

```sh
sudo apt install file findutils patchelf dpkg-dev librsvg2-dev libgirepository1.0-dev
```

Provide executable copies of [linuxdeploy-x86_64.AppImage](https://github.com/linuxdeploy/linuxdeploy/releases) and the official [linuxdeploy-plugin-gtk.sh](https://github.com/linuxdeploy/linuxdeploy-plugin-gtk). For example, download them into a tools directory:

```sh
mkdir -p tools/appimage
curl -fL https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage \
  -o tools/appimage/linuxdeploy-x86_64.AppImage
curl -fL https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/master/linuxdeploy-plugin-gtk.sh \
  -o tools/appimage/linuxdeploy-plugin-gtk.sh
chmod +x tools/appimage/linuxdeploy-x86_64.AppImage tools/appimage/linuxdeploy-plugin-gtk.sh
```

These download URLs move with upstream releases. For repeatable releases, retain and record the exact linuxdeploy/plugin revisions and checksums along with appimagetool and the type-2 runtime. The script itself downloads or installs no packaging tools. The GTK plugin is experimental upstream, so test every release artifact on the target desktop.

After `flutter build linux --release`:

```sh
APPIMAGETOOL=/absolute/path/to/appimagetool-x86_64.AppImage \
LINUXDEPLOY="$PWD/tools/appimage/linuxdeploy-x86_64.AppImage" \
LINUXDEPLOY_GTK_PLUGIN="$PWD/tools/appimage/linuxdeploy-plugin-gtk.sh" \
  bash packaging/linux/build-appimage.sh --bundle-deps \
  --output "$PWD/dist/Comfer_Wallpaper-x86_64-bundled.AppImage"
```

Alternatively supply `--linuxdeploy /path/to/tool` and `--gtk-plugin /path/to/script`; otherwise the script searches `PATH`. Packaging uses extraction mode and does not require FUSE. The image is larger because native libraries and GTK resources are included. linuxdeploy determines transitive dependencies and applies its standard system-library exclusions; this is not a fully independent Linux filesystem.

The custom launcher sources the GTK plugin's runtime hooks, preserves the user's X11/Wayland backend selection, and uses bundled GIO modules. The `gsettings`, `gdbus`, `dbus-send`, and `xdg-open` commands run from the host's original PATH with its original library/schema environment. This avoids mixing bundled GLib with GNOME's desktop settings tools. Their host packages (`libglib2.0-bin`, `dbus`, `xdg-utils` as applicable) still need to be available.

**Still required on the destination:** a compatible Linux/glibc baseline, the display server and graphics drivers, fonts and excluded low-level libraries, the signed-in GNOME session, session D-Bus/dconf services, and an AppIndicator/StatusNotifier tray host for a visible icon. GNOME Shell/extensions and the user's desktop services cannot be supplied by copying GTK libraries into the image. A missing tray host still shows fallback controls. Bundling dependencies does not add KDE wallpaper support.

Build on the oldest base you intend to support (for example your Ubuntu 20.04 build machine), and test on each target distribution. Packaging on a newer distribution cannot lower the compiled binaries' glibc requirements. Normal FUSE mounting and cross-distribution compatibility are separate checks from successfully building the image.

To run, move the finished file to a stable location such as `~/Applications/Comfer Wallpaper.AppImage`, keep it executable, and launch it in the signed-in GNOME session. First-launch setup offers login startup. Registration uses the **outer AppImage file**, never `/tmp/.mount_*`. Keep the same filename for upgrades; after moving or renaming it, explicitly use `--enable-startup` from its new path if desired. Disabled startup remains disabled. To uninstall, Quit, use `--disable-startup`, remove the per-user startup entry and delete the AppImage; preserve wallpaper data as described above.

On hosts without a usable FUSE setup, use the runtime's extraction fallback:

```sh
APPIMAGE_EXTRACT_AND_RUN=1 "$HOME/Applications/Comfer Wallpaper.AppImage" --show
```

For login startup in that environment, the login session must also provide `APPIMAGE_EXTRACT_AND_RUN=1`, or the host must support normal AppImage mounting. The generated autostart entry runs the outer file directly. Extracting manually with `--appimage-extract` is another diagnostic option, but launching an extracted AppDir is a separate bundle installation rather than the original AppImage.

Packaging regression tests (stub packer/deployment tools; no network), including bundled layout, hook execution, Wayland selection, host-command environment restoration and failure cleanup:

```sh
/usr/bin/python3 integration_test/appimage_packaging_test.py
```

Earlier AppImage validation: 31 Flutter tests, 5 packaging contract tests, clean Flutter analysis, a Linux release build, and actual AppImage creation using appimagetool 1.9.1. The generated image launched from `/` using extraction mode; startup enable/status/disable targeted the outer image, and extracted launcher/tray icons and desktop metadata validated.

Dependency-bundling validation on Debian 12 x86-64 / GNOME Wayland: **7 packaging contract tests passed**, including explicit tool-flag precedence, bundled layout, host-command isolation, and failure cleanup. Shell syntax and whitespace checks passed. A real approximately 47 MiB bundled AppImage was created with linuxdeploy commit `07333c6`, the GTK plugin, and appimagetool 1.9.1. Launched from `/` in extraction mode, its process mappings confirmed bundled GTK, AppIndicator and GIO libraries. Outer-image startup enable/status/disable, native tray Hourly/Daily selection and saved frequency, duplicate prevention, and native Quit passed with isolated application data. The smoke test disabled wallpaper changes through unsupported-desktop detection; it did not repeat real wallpaper replacement. GTK emitted a cursor-theme warning, but the checked controls worked. Flutter code was unchanged and its tests/build were not rerun for this packaging-only change.

Normal FUSE mounting, Ubuntu 20.04, and compatibility on other distribution bases remain untested. This build verifies bundling on the development host, not a universal Linux binary.

The layout follows the [AppDir specification](https://docs.appimage.org/reference/appdir.html); stable startup uses the runtime's documented [APPIMAGE and APPDIR variables](https://docs.appimage.org/packaging-guide/environment-variables.html).

## macOS build and installation (macOS 13+)

For a downloaded release, open the DMG, drag **Comfer Wallpaper** into **Applications**, and open the installed app. Version **0.2.0 (build 2)** offers **Start at login** or **Not now** on first launch. If macOS requires approval, the setup provides **Open System Settings** and **Check again**. Once you choose, setup will not prompt again or override a later change in System Settings. Existing installations with startup already enabled skip setup.

Opening an uninstalled copy shows instructions to move it into Applications first. Close that copy and launch the installed app to continue. Closing an unfinished setup quits Comfer; the choice remains available next launch. No Terminal command is needed for drag-and-drop installation.

Build with Flutter, Xcode, and CocoaPods installed:

```sh
flutter pub get
flutter build macos --release
bash packaging/macos/install.sh
```

The installer copies the application to `~/Applications/Comfer Wallpaper.app`, registers it with `SMAppService`, and starts it. Pass a built `.app` and optional installation directory as arguments to install elsewhere. Quit the existing instance before an upgrade. Normal launches never re-enable startup if you disabled it in System Settings.

If macOS says approval is required, open **System Settings → General → Login Items & Extensions** and enable Comfer. Startup registration is per user and requires no root service. The current release uses the primary screen/current desktop; other displays and Spaces are not synchronized.

To inspect or change registration explicitly:

```sh
"$HOME/Applications/Comfer Wallpaper.app/Contents/MacOS/Comfer Wallpaper" --startup-status
"$HOME/Applications/Comfer Wallpaper.app/Contents/MacOS/Comfer Wallpaper" --disable-startup
"$HOME/Applications/Comfer Wallpaper.app/Contents/MacOS/Comfer Wallpaper" --enable-startup
```

Status values follow Apple's API: 0 not registered, 1 enabled, 2 requires approval, 3 not found. After Quit, launching the executable with `--change-now` requests an immediate change; `--show` opens the fallback controls. The login startup commands do not start Flutter or download images.

Uninstall after choosing Quit:

```sh
bash packaging/macos/uninstall.sh
```

Uninstall preserves application data so the desktop never points to a deleted wallpaper. A distributable release still needs the publisher's normal signing/notarization process; building locally is not notarization.

## Windows build and installation

Native Windows validation remains outstanding. Build on a Windows host:

```powershell
flutter pub get
flutter build windows --release
.\packaging\windows\install.ps1
```

The existing helper installs into LocalAppData and registers the executable in the current user's Run key. `packaging/windows/uninstall.ps1` removes the app and startup entry while preserving data. The wallpaper setter uses the Win32 API directly and checks its return value. This is an interactive signed-in-user application, not a Windows system service.

## Release validation and known limitations

The application controller owns scheduling and tray state independently of widgets. Core code is in `lib/services/`; native adapters are in `lib/platform/` and desktop runner files. `macos/Podfile` is included for reproducible builds; Flutter may generate additional Swift Package Manager integration with newer SDKs.

```sh
flutter analyze
flutter test
# On macOS, with the normal Comfer instance stopped:
flutter test integration_test/desktop_test.dart -d macos
flutter test integration_test/login_startup_test.dart -d macos
flutter build macos --release
```

The native test temporarily applies two fixture wallpapers, verifies cleanup, and restores the original; it refuses to run if the starting wallpaper file is unavailable. It also creates a real status-bar item and verifies persisted frequency selection. Unit tests cover successful replacement, failed HTTP/apply/image validation, overlapping requests, recovery, invalid paths/symlinks, missing current files, scheduler boundaries, retry timing, and preference failure. Setup tests cover enabling, declining, duplicate-click prevention, approval, retry, uninstalled copies, and respecting previous decisions.

Historical macOS implementation: managed replacement/recovery, persistent scheduling, background engine/tray lifecycle, and installation scripts. Native Windows builds, KDE support, full multi-display/Spaces coverage, login after reboot, and physical sleep/wake verification remain outside the historical macOS checks. Native menu mouse/keyboard interaction also needs manual verification if desktop automation is unavailable.

Previously recorded on macOS 26.7 with Flutter 3.41.9 and Xcode 26.6:

- `flutter analyze`: no issues. Version 0.2.0 passes 22 unit/widget tests and the native login-startup guard test; the 2 wallpaper/tray integration tests passed during the earlier implementation.
- Release build and strict/deep code-signature verification passed.
- Installed app applied a real downloaded wallpaper; the manifest and native desktop API agreed on its path, with one managed image remaining.
- Duplicate launch exited without creating a second running instance.
- Graceful termination used the same shutdown function as the Quit menu action.
- Install, upgrade, uninstall, and reinstall completed; startup status changed from enabled to unregistered and back to enabled. Active wallpaper data survived uninstall.

Those native tests establish status-item creation and preference persistence, but do not simulate clicking every native menu item. Desktop UI automation timed out on that macOS host. Earlier live tests exposed and resolved hidden-engine startup and delayed desktop-path confirmation; an initial integration restoration failed, so the test now requires an existing original image before changing it. Later native runs passed. The isolated fixture left by that failed run was removed after a real wallpaper was confirmed active.

### Recorded Linux validation

The earlier Linux implementation passed analysis, 30 unit/widget tests and the Linux release build. The later AppImage change increased the Flutter test count to 31; its results are recorded in the AppImage section. Earlier native integration tests verified tray/frequency and reversible wallpaper replacement; the compiled runtime harness verifies real API replacements/cleanup, native DBusMenu actions, checked frequency and persistence, hidden startup, fallback accessibility, duplicate prevention, Quit, and startup registration/relocation/removal outside the repository. A separate helper regression verifies running-process guards, disabled-startup preservation and uninstall data preservation.

```sh
flutter test integration_test/desktop_test.dart -d linux
/usr/bin/python3 integration_test/linux_runtime_test.py build/linux/x64/release/bundle
/usr/bin/python3 integration_test/linux_helpers_test.py
```

The runtime harness requires `python3-gi` and AT-SPI introspection, temporarily changes wallpaper, isolates application data, and restores original GNOME settings. Actual logout/login, physical suspend/resume, physical mouse/keyboard tray interaction, and other desktop/session combinations remain untested. Sleep/retry behavior has deterministic scheduler coverage. Native actions are tested through DBusMenu, not simulated mouse clicks.
