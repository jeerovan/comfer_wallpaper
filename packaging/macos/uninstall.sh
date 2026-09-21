#!/bin/bash
set -euo pipefail
TARGET_APP="${1:-$HOME/Applications/Comfer Wallpaper.app}"
if [[ ! -d "$TARGET_APP/Contents" ]]; then
  echo 'Comfer is not installed at that path.' >&2
  exit 1
fi
if pgrep -x 'Comfer Wallpaper' >/dev/null; then
  echo 'Quit Comfer from its status-bar menu before uninstalling.' >&2
  exit 1
fi
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$TARGET_APP/Contents/Info.plist")
[[ "$BUNDLE_ID" == 'com.jeerovan.comfer' ]] || { echo 'Refusing to remove an unrelated application.' >&2; exit 1; }
"$TARGET_APP/Contents/MacOS/Comfer Wallpaper" --disable-startup
rm -rf "$TARGET_APP"
echo 'Comfer removed. Preferences and the active wallpaper were preserved to keep the desktop image valid.'
