# Comfer Wallpaper

A background desktop wallpaper app with three status-bar controls: **Change now**, **Frequency → Hourly / Daily**, and **Quit**. Hourly is the default. Wallpapers come from the existing Comfer API.

Build and packaging instructions, dependencies, icon requirements, platform restrictions, validation results, and Ubuntu troubleshooting are in **[Release.md](Release.md)**.

## Behavior

- Starts in the signed-in user's desktop session when login startup is enabled. After first-launch setup, no normal window is shown when the tray and desktop integration are usable.
- Keeps one managed wallpaper after a successful replacement and cleanup. The previous image remains available until the replacement is validated and confirmed by the desktop.
- Stores images and a recovery journal in the app's application-support directory, rather than Downloads. Unknown files and legacy Downloads images are never automatically deleted.
- Persists Hourly/Daily across restarts. Daily means 24 hours after the last successful change. A manual change resets the interval.
- Retries failures after 1, 5, 15, then 60 minutes. Sleep/resume performs at most one overdue change. It cannot change wallpaper while the computer is asleep, logged out, or powered off.
- Quit stops the process and scheduling. It remains registered for the next login; uninstall removes registration.
- Multiple launches share an OS file lock, preventing competing schedulers.

A temporary image and previous image may coexist during replacement or recovery. Cleanup failures block further downloads until resolved, preventing unbounded accumulation. A file still reported as being used on another display is retained for safety.

## Desktop use

Comfer runs in the signed-in user's graphical session; it is not a machine-level service.

- **macOS:** open the installed app from Applications. First-launch setup offers **Start at login** or **Not now**; macOS may require approval in Login Items.
- **Linux:** the wallpaper adapter targets GNOME. First launch offers login startup from a stable installed path. Missing tray support or an unsupported desktop keeps a control window visible with an explanation. KDE is not currently supported.
- **Windows:** the per-user installer registers login startup, preserves disabled startup on upgrades, and adds an Installed Apps uninstall entry. Wallpaper changes target the primary monitor; files used by other monitors remain protected. See the [Windows release instructions](Release.md#windows-build-and-installation).

The release guide contains [Linux setup and uninstall instructions](Release.md#startup-upgrades-and-uninstall), [AppImage usage](Release.md#build-an-x86-64-appimage), and [macOS installation/startup commands](Release.md#macos-build-and-installation-macos-13). Quit before replacing or removing application binaries. Preserve the active wallpaper data when uninstalling.

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

On Linux, application data normally lives under `${XDG_DATA_HOME:-$HOME/.local/share}/com.example.comfer_wallpaper/`. The path-provider plugin may retain the legacy `comfer_wallpaper/` directory. Preferences, the wallpaper journal/images, instance lock and bounded logs are separate from application binaries; per-user startup registration uses XDG config.

## Code organization

The application controller owns scheduling and tray state independently of widgets. Core code is in `lib/services/`; platform adapters are in `lib/platform/` and desktop runner files. See [release validation](Release.md#release-validation-and-known-limitations) for test commands and verified versus untested behavior.

## License

MIT; see [LICENSE.md](LICENSE.md). Images are provided through the API used by [Comfer Launcher](https://comfer.jeerovan.com).
