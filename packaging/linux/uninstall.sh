#!/bin/bash
set -euo pipefail
if pgrep -x comfer_wallpaper >/dev/null; then
  echo 'Quit Comfer before uninstalling.' >&2; exit 1
fi
rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/autostart/com.jeerovan.comfer.desktop" \
      "${XDG_DATA_HOME:-$HOME/.local/share}/applications/com.jeerovan.comfer.desktop"
rm -rf "${XDG_DATA_HOME:-$HOME/.local/share}/comfer-wallpaper"
echo 'Removed. The active wallpaper and preferences are preserved.'
