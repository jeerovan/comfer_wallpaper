#!/bin/bash
set -euo pipefail
SOURCE_APP="${1:-build/macos/Build/Products/Release/Comfer Wallpaper.app}"
INSTALL_DIR="${2:-$HOME/Applications}"
TARGET_APP="$INSTALL_DIR/Comfer Wallpaper.app"
if [[ ! -d "$SOURCE_APP/Contents" ]]; then
  echo 'Build first: flutter build macos --release' >&2
  exit 1
fi
if pgrep -x 'Comfer Wallpaper' >/dev/null; then
  echo 'Quit Comfer from its status-bar menu before installing/upgrading.' >&2
  exit 1
fi
mkdir -p "$INSTALL_DIR"
STAGING_DIR=$(mktemp -d "$INSTALL_DIR/.comfer-install.XXXXXX")
trap 'rm -rf "$STAGING_DIR"' EXIT
ditto "$SOURCE_APP" "$STAGING_DIR/Comfer Wallpaper.app"
# Preserve the previous installation until the replacement has been copied.
if [[ -e "$TARGET_APP" ]]; then
  mv "$TARGET_APP" "$STAGING_DIR/previous.app"
fi
mv "$STAGING_DIR/Comfer Wallpaper.app" "$TARGET_APP"
"$TARGET_APP/Contents/MacOS/Comfer Wallpaper" --enable-startup
open "$TARGET_APP"
echo "Installed: $TARGET_APP"
echo 'If macOS requests approval, enable Comfer in System Settings > General > Login Items.'
