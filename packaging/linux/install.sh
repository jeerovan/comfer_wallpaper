#!/bin/bash
set -euo pipefail
SOURCE_DIR="${1:-build/linux/x64/release/bundle}"
TARGET_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/comfer-wallpaper"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
[[ -x "$SOURCE_DIR/comfer_wallpaper" ]] || { echo 'Build the Linux release first.' >&2; exit 1; }
mkdir -p "$TARGET_DIR" "$CONFIG_DIR/autostart" "${XDG_DATA_HOME:-$HOME/.local/share}/applications"
cp -a "$SOURCE_DIR/." "$TARGET_DIR/"
# Quote according to desktop-entry Exec syntax, not shell syntax.
python3 - "$TARGET_DIR" "$CONFIG_DIR" "${XDG_DATA_HOME:-$HOME/.local/share}" <<'PY'
import pathlib, sys
root, config, data = map(pathlib.Path, sys.argv[1:])
exe = str(root / 'comfer_wallpaper')
quoted = '"' + ''.join('\\' + c if c in '\\"`$' else c for c in exe).replace('%', '%%') + '"'
entry = '[Desktop Entry]\nType=Application\nName=Comfer Wallpaper\nExec=' + quoted + '\nTerminal=false\n'
(config / 'autostart/com.jeerovan.comfer.desktop').write_text(entry)
(data / 'applications/com.jeerovan.comfer.desktop').write_text(entry)
PY
echo 'Installed for the current user. Start Comfer from your application launcher; future logins start it automatically.'
