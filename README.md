# Comfer Wallpaper

A background desktop wallpaper app with three status-bar controls: **Change now**, **Frequency → Hourly / Daily**, and **Quit**. Hourly is the default. Wallpapers come from the existing Comfer API.

## Behavior

- Starts in the signed-in user's desktop session when login startup is enabled. After first-launch setup, no normal window is shown on macOS or Windows when tray initialization succeeds.
- Keeps one managed wallpaper after a successful replacement and cleanup. The previous image remains available until the replacement is validated and confirmed by the desktop.
- Stores images and a recovery journal in the app's application-support directory, rather than Downloads. Unknown files and legacy Downloads images are never automatically deleted.
- Persists Hourly/Daily across restarts. Daily means 24 hours after the last successful change. A manual change resets the interval.
- Retries failures after 1, 5, 15, then 60 minutes. Sleep/resume performs at most one overdue change. It cannot change wallpaper while the computer is asleep, logged out, or powered off.
- Quit stops the process and scheduling. It remains registered for the next login; uninstall removes registration.
- Multiple launches share an OS file lock, preventing competing schedulers.

A temporary image and previous image may coexist during replacement or recovery. Cleanup failures block further downloads until resolved, preventing unbounded accumulation. A file still reported as being used on another display is retained for safety.

## macOS installation (macOS 13+)

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

## Windows and Linux

Platform adapters and per-user installation scripts are included, but their native builds and installers have **not been verified on Windows/Linux in this macOS implementation session**.

**Windows:** build with `flutter build windows --release`; run `packaging/windows/install.ps1` from the repository root. The script installs into LocalAppData and registers the executable in the current user's Run key. `uninstall.ps1` removes the app and startup entry, preserving data. The wallpaper setter uses the Win32 API directly and checks its return value.

**Linux:** build with `flutter build linux --release`; run `bash packaging/linux/install.sh`. Startup uses the user's XDG autostart directory. `uninstall.sh` removes the installed bundle and launch entries, preserving preferences and the active wallpaper. The current adapter targets GNOME with both light/dark wallpaper settings and uses the existing graphical-session environment without sudo. KDE and other desktop adapters remain future work. GNOME needs a functioning AppIndicator host/extension; tray_manager 0.5.1 also requires its AppIndicator native library. Linux keeps the fallback controls visible because creating an indicator alone does not prove the shell displays it.

These are interactive desktop agents, not machine-level services. They need a logged-in graphical session.

## Storage, recovery, and diagnostics

On sandboxed macOS builds, application data is normally under:

```text
~/Library/Containers/com.jeerovan.comfer/Data/Library/Application Support/com.jeerovan.comfer/
  wallpapers/state.json
  wallpapers/comfer-<id>.jpg or .png
  instance.lock
  comfer.log
  comfer.log.previous
```

The journal is written before applying a candidate. After interruption, Comfer confirms or reapplies that candidate before committing it and cleaning up. Corrupt manifests or unsafe file paths stop replacement rather than deleting files. The log is capped at approximately 256 KiB plus one rotated file and avoids logging identity/API URLs.

Legacy timestamp-named Downloads images and `wallpaper_file_name.txt` are left untouched because the old version did not maintain a trustworthy ownership record. After the new app successfully sets a wallpaper, manually remove only legacy files you recognize as Comfer downloads. Comfer does not scan or delete arbitrary images.

## Development and validation

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

Implementation phases completed on macOS: managed replacement/recovery, persistent scheduling, background engine/tray lifecycle, and installation scripts. Native Windows/Linux builds, KDE support, full multi-display/Spaces coverage, login after reboot, and physical sleep/wake verification remain outside the checks performed on this host. Native menu mouse/keyboard interaction also needs manual verification if desktop automation is unavailable.

Verified on macOS 26.7 with Flutter 3.41.9 and Xcode 26.6:

- `flutter analyze`: no issues. Version 0.2.0 passes 22 unit/widget tests and the native login-startup guard test; the 2 wallpaper/tray integration tests passed during the earlier implementation.
- Release build and strict/deep code-signature verification passed.
- Installed app applied a real downloaded wallpaper; the manifest and native desktop API agreed on its path, with one managed image remaining.
- Duplicate launch exited without creating a second running instance.
- Graceful termination used the same shutdown function as the Quit menu action.
- Install, upgrade, uninstall, and reinstall completed; startup status changed from enabled to unregistered and back to enabled. Active wallpaper data survived uninstall.

The native tests establish status-item creation and preference persistence, but do not simulate clicking every native menu item. Desktop UI automation timed out on this host. Earlier live tests exposed and resolved hidden-engine startup and delayed desktop-path confirmation; an initial integration restoration failed, so the test now requires an existing original image before changing it. Later native runs passed. The isolated fixture left by that failed run was removed after a real wallpaper was confirmed active.

## License

MIT; see [LICENSE.md](LICENSE.md). Images are provided through the API used by [Comfer Launcher](https://comfer.jeerovan.com).
