#!/bin/bash
set -euo pipefail
SOURCE_DIR="${1:-build/linux/x64/release/bundle}"
TARGET_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/comfer-wallpaper"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
[[ -x "$SOURCE_DIR/comfer_wallpaper" ]] || { echo 'Build the Linux release first.' >&2; exit 1; }
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
mkdir -p "$TARGET_DIR" "${XDG_DATA_HOME:-$HOME/.local/share}/applications"
cp -a "$SOURCE_DIR/." "$TARGET_DIR/"
# Quote according to desktop-entry Exec syntax, not shell syntax.
python3 - "$TARGET_DIR" "$CONFIG_DIR" "${XDG_DATA_HOME:-$HOME/.local/share}" <<'PY'
import pathlib, sys
root, config, data = map(pathlib.Path, sys.argv[1:])
exe = str(root / 'comfer_wallpaper')
quoted = '"' + ''.join('\\' + c if c in '\\"`$' else c for c in exe).replace('%', '%%') + '"'
quoted = quoted.replace('\\', '\\\\')
entry = '[Desktop Entry]\nType=Application\nName=Comfer Wallpaper\nExec=' + quoted + '\nTerminal=false\n'
# Startup is offered by the application; never overwrite a user's disabled entry.
(data / 'applications/com.jeerovan.comfer.desktop').write_text(entry)
PY
echo 'Installed for the current user. Start Comfer from your application launcher; choose Start at login in first-launch setup if desired.'
