#!/bin/bash
set -euo pipefail
TARGET_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/comfer-wallpaper"
# Match /proc executable paths: Linux truncates process names to 15 bytes.
python3 - "$TARGET_DIR/comfer_wallpaper" <<'PYTHON'
import os, pathlib, sys
target = os.path.realpath(sys.argv[1])
for proc in pathlib.Path('/proc').glob('[0-9]*'):
    try:
        if proc.stat().st_uid == os.getuid() and os.readlink(proc / 'exe').removesuffix(' (deleted)') == target:
            sys.exit('Quit Comfer before replacing or removing its bundle.')
    except (FileNotFoundError, PermissionError, ProcessLookupError):
        pass
PYTHON
rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/autostart/com.jeerovan.comfer.desktop" \
      "${XDG_DATA_HOME:-$HOME/.local/share}/applications/com.jeerovan.comfer.desktop"
rm -rf "${XDG_DATA_HOME:-$HOME/.local/share}/comfer-wallpaper"
echo 'Removed. The active wallpaper and preferences are preserved.'
