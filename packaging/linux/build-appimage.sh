#!/usr/bin/env bash
# Package an existing Flutter Linux release. Does not build Flutter or install tools.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
BUNDLE="$REPO_DIR/build/linux/x64/release/bundle"
APP_ICON="$REPO_DIR/assets/comfer_launcher.png"
TRAY_ICON=''
OUTPUT=''
TOOL="${APPIMAGETOOL:-appimagetool}"
RUNTIME=''
BUNDLE_DEPS=0
DEPLOY="${LINUXDEPLOY:-linuxdeploy}"
GTK_PLUGIN="${LINUXDEPLOY_GTK_PLUGIN:-linuxdeploy-plugin-gtk.sh}"
usage() {
  cat <<'HELP'
Usage: packaging/linux/build-appimage.sh [options]
Run flutter build linux --release first. Linux x86_64 only.
  --bundle DIR         Existing release bundle (default: build/linux/x64/release/bundle)
  --output FILE        Output (default: dist/Comfer_Wallpaper-<version>-x86_64.AppImage)
  --app-icon PNG       Square launcher PNG, 256/512/1024 px (default: assets/comfer_launcher.png)
  --tray-icon PNG      Square tray PNG, 32/64/128/256/512 px (default: built bundle's icon)
  --appimagetool FILE  appimagetool executable (or set APPIMAGETOOL)
  --bundle-deps        Bundle GTK 3/AppIndicator with linuxdeploy and its GTK plugin
  --linuxdeploy FILE   linuxdeploy executable (or set LINUXDEPLOY)
  --gtk-plugin FILE    GTK plugin script (or set LINUXDEPLOY_GTK_PLUGIN)
  --runtime-file FILE Optional x86_64 type-2 runtime for offline/repeatable packaging
  -h, --help           Show this help
Requires bash, Python 3, GNU coreutils, and appimagetool. No sudo or Flutter rebuild.
With --bundle-deps, GTK/AppIndicator libraries are included; desktop services remain on the host.
Without it, host GTK/AppIndicator are required. See Release.md.
HELP
}
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
while (($#)); do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --bundle-deps) BUNDLE_DEPS=1; shift ;;
    --bundle|--output|--app-icon|--tray-icon|--appimagetool|--runtime-file|--linuxdeploy|--gtk-plugin)
      (($# >= 2)) && [[ -n "$2" ]] || die "Missing value for $1"
      case "$1" in
        --bundle) BUNDLE="$2" ;; --output) OUTPUT="$2" ;;
        --app-icon) APP_ICON="$2" ;; --tray-icon) TRAY_ICON="$2" ;;
        --appimagetool) TOOL="$2" ;; --runtime-file) RUNTIME="$2" ;;
        --linuxdeploy) DEPLOY="$2" ;; --gtk-plugin) GTK_PLUGIN="$2" ;;
      esac
      shift 2 ;;
    *) die "Unknown option: $1 (use --help)" ;;
  esac
done
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || die 'Only Linux x86_64 packaging is supported.'
command -v python3 >/dev/null || die 'Python 3 is required.'
TOOL="$(command -v -- "$TOOL")" || die 'Set APPIMAGETOOL to an executable from https://github.com/AppImage/appimagetool/releases'
TOOL="$(realpath -- "$TOOL")"
[[ -x "$TOOL" ]] || die 'appimagetool is not executable.'
if ((BUNDLE_DEPS)); then
  DEPLOY="$(command -v -- "$DEPLOY")" || die 'Set LINUXDEPLOY to the x86_64 linuxdeploy AppImage.'
  GTK_PLUGIN="$(command -v -- "$GTK_PLUGIN")" || die 'Set LINUXDEPLOY_GTK_PLUGIN to linuxdeploy-plugin-gtk.sh.'
  DEPLOY="$(realpath -- "$DEPLOY")"
  GTK_PLUGIN="$(realpath -- "$GTK_PLUGIN")"
  [[ -x "$DEPLOY" && -x "$GTK_PLUGIN" ]] || die 'linuxdeploy and the GTK plugin must be executable.'
  for requirement in pkg-config file find patchelf; do
    command -v "$requirement" >/dev/null || die "Missing dependency bundling tool: $requirement"
  done
  pkg-config --exists gtk+-3.0 librsvg-2.0 gobject-introspection-1.0 ||
    die 'GTK plugin needs libgtk-3-dev, librsvg2-dev and libgirepository1.0-dev (Debian/Ubuntu).'
fi
BUNDLE="$(realpath -m -- "$BUNDLE")"
APP_ICON="$(realpath -m -- "$APP_ICON")"
[[ -n "$TRAY_ICON" ]] || TRAY_ICON="$BUNDLE/data/flutter_assets/assets/comfer_launcher.png"
TRAY_ICON="$(realpath -m -- "$TRAY_ICON")"
VERSION="$(python3 - "$REPO_DIR/pubspec.yaml" <<'PY'
import re, sys
match = re.search(r'^version:\s*([0-9A-Za-z.+-]+)\s*$', open(sys.argv[1]).read(), re.M)
if not match:
    sys.exit('Cannot read version from pubspec.yaml')
print(match[1])
PY
)"
[[ -n "$OUTPUT" ]] || OUTPUT="$REPO_DIR/dist/Comfer_Wallpaper-$VERSION-x86_64.AppImage"
OUTPUT="$(realpath -m -- "$OUTPUT")"
[[ ! -e "$OUTPUT" && ! -L "$OUTPUT" ]] || die "Output already exists; choose another --output or remove it explicitly: $OUTPUT"
[[ "$OUTPUT" != "$BUNDLE/"* ]] || die 'Output must be outside the input bundle.'
# Check the payload, not just the build host's architecture.
ICON_SIZE="$(python3 - "$BUNDLE" "$APP_ICON" "$TRAY_ICON" <<'PY'
import os, pathlib, struct, sys
bundle, app, tray = map(pathlib.Path, sys.argv[1:])
required = ['comfer_wallpaper', 'lib/libapp.so', 'lib/libflutter_linux_gtk.so',
            'data/icudtl.dat', 'data/flutter_assets/assets/comfer_launcher.png']
for name in required:
    if not (bundle / name).is_file():
        sys.exit(f'Missing {name}; run flutter build linux --release first')
if not os.access(bundle / 'comfer_wallpaper', os.X_OK):
    sys.exit('Bundle executable lacks execute permission')
for path in [bundle / 'comfer_wallpaper', *bundle.rglob('*.so')]:
    with path.open('rb') as file:
        header = file.read(20)
    if len(header) < 20 or header[:6] != b'\x7fELF\x02\x01' or struct.unpack_from('<H', header, 18)[0] != 62:
        sys.exit(f'Expected an x86_64 ELF binary: {path}')
for role, path, sizes in [('app', app, (256, 512, 1024)), ('tray', tray, (32, 64, 128, 256, 512))]:
    try:
        with path.open('rb') as file:
            header = file.read(26)
        if header[:8] != b'\x89PNG\r\n\x1a\n' or header[12:16] != b'IHDR' or len(header) < 26:
            raise ValueError('expected PNG')
        width, height = struct.unpack_from('>II', header, 16)
        if width != height or width not in sizes or header[24] != 8 or header[25] not in (2, 6):
            raise ValueError(f'expected square 8-bit RGB/RGBA PNG, size in {sizes}')
    except (OSError, ValueError) as error:
        sys.exit(f'Invalid {role} icon {path}: {error}')
    if role == 'app':
        print(width)
PY
)"
RUNTIME_ARGS=()
if [[ -n "$RUNTIME" ]]; then
  [[ -f "$RUNTIME" ]] || die "Missing runtime: $RUNTIME"
  python3 - "$RUNTIME" <<'PYTHON'
import struct, sys
with open(sys.argv[1], 'rb') as file:
    header = file.read(20)
if len(header) < 20 or header[:6] != b'\x7fELF\x02\x01' or struct.unpack_from('<H', header, 18)[0] != 62:
    sys.exit('The supplied runtime must be x86_64 ELF')
PYTHON
  RUNTIME_ARGS=(--runtime-file "$(realpath -- "$RUNTIME")")
fi
mkdir -p -- "$(dirname -- "$OUTPUT")"
# Stage on the output filesystem, publish only a successful completed image.
WORK="$(mktemp -d "$(dirname -- "$OUTPUT")/.comfer-appimage.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT
APPDIR="$WORK/Comfer_Wallpaper.AppDir"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/share/applications" \
  "$APPDIR/usr/share/icons/hicolor/${ICON_SIZE}x${ICON_SIZE}/apps" "$APPDIR/usr/share/licenses/comfer-wallpaper"
cp -a -- "$BUNDLE/." "$APPDIR/usr/bin/"
cp -- "$TRAY_ICON" "$APPDIR/usr/bin/data/flutter_assets/assets/comfer_launcher.png"
cp -- "$APP_ICON" "$APPDIR/usr/share/icons/hicolor/${ICON_SIZE}x${ICON_SIZE}/apps/com.jeerovan.comfer.png"
cp -- "$REPO_DIR/LICENSE.md" "$APPDIR/usr/share/licenses/comfer-wallpaper/"
cat > "$APPDIR/usr/share/applications/com.jeerovan.comfer.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Comfer Wallpaper
Comment=Automatic desktop wallpapers
Exec=comfer_wallpaper
Icon=com.jeerovan.comfer
Terminal=false
Categories=Utility;
StartupWMClass=com.example.comfer_wallpaper
X-AppImage-Version=$VERSION
DESKTOP
ln -s usr/share/applications/com.jeerovan.comfer.desktop "$APPDIR/com.jeerovan.comfer.desktop"
ln -s "usr/share/icons/hicolor/${ICON_SIZE}x${ICON_SIZE}/apps/com.jeerovan.comfer.png" "$APPDIR/com.jeerovan.comfer.png"
ln -s com.jeerovan.comfer.png "$APPDIR/.DirIcon"
cat > "$APPDIR/AppRun" <<'APPRUN'
#!/bin/sh
# Retain the graphical session's XDG, D-Bus and GSettings environment.
APPDIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export APPDIR
exec "$APPDIR/usr/bin/comfer_wallpaper" "$@"
APPRUN
chmod +x "$APPDIR/AppRun"
if ((BUNDLE_DEPS)); then
  # Flutter expects lib/ beside its executable; share one copy with linuxdeploy.
  mv "$APPDIR/usr/bin/lib" "$APPDIR/usr/lib"
  ln -s ../lib "$APPDIR/usr/bin/lib"
  export APPIMAGE_EXTRACT_AND_RUN=1
  # Preserve Flutter's prebuilt AOT/engine binaries; they are already stripped.
  export NO_STRIP=1
  "$DEPLOY" --appdir "$APPDIR"
  DEPLOY_GTK_VERSION=3 LINUXDEPLOY="$DEPLOY" "$GTK_PLUGIN" --appdir "$APPDIR"
  # GIO backends are loaded dynamically, so normal ELF dependency scanning misses them.
  GIO_MODULES="$(pkg-config --variable=giomoduledir gio-2.0)"
  [[ -d "$GIO_MODULES" ]] || die 'Cannot find the build host GIO modules.'
  mkdir -p "$APPDIR/usr/lib/gio/modules"
  cp -a "$GIO_MODULES/." "$APPDIR/usr/lib/gio/modules/"
  # Process the extra dynamically loaded modules copied by the GTK plugin.
  "$DEPLOY" --appdir "$APPDIR"
  [[ -f "$APPDIR/apprun-hooks/linuxdeploy-plugin-gtk.sh" ]] || die 'GTK plugin did not produce its runtime hook.'
  [[ -f "$APPDIR/usr/lib/libgtk-3.so.0" ]] || die 'GTK library was not bundled.'
  [[ -f "$APPDIR/usr/lib/libayatana-appindicator3.so.1" || -f "$APPDIR/usr/lib/libappindicator3.so.1" ]] ||
    die 'AppIndicator library was not bundled; check tray_manager and the release payload.'
  mkdir -p "$APPDIR/usr/lib/comfer/host-bin"
  cp "$SCRIPT_DIR/appimage-environment.sh" "$APPDIR/usr/lib/comfer/"
  for command_name in gsettings gdbus dbus-send xdg-open; do
    cp "$SCRIPT_DIR/appimage-host-command" "$APPDIR/usr/lib/comfer/host-bin/$command_name"
    chmod +x "$APPDIR/usr/lib/comfer/host-bin/$command_name"
  done
  # Replace linuxdeploy's generic launcher, keeping and sourcing GTK hooks.
  rm -f "$APPDIR/AppRun"
  cp "$SCRIPT_DIR/AppRun-bundled" "$APPDIR/AppRun"
  chmod +x "$APPDIR/AppRun"
fi
ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$TOOL" "${RUNTIME_ARGS[@]}" "$APPDIR" "$WORK/output.AppImage"
[[ -s "$WORK/output.AppImage" ]] || die 'appimagetool did not create an image.'
chmod +x "$WORK/output.AppImage"
# Hard-link publication fails safely if another packaging process won the race.
ln -- "$WORK/output.AppImage" "$OUTPUT"
printf 'Created %s\n' "$OUTPUT"
if ((BUNDLE_DEPS)); then
  printf 'GTK 3 and AppIndicator libraries bundled. Host GNOME/session D-Bus, tray host, graphics drivers and compatible glibc are still required.\n'
else
  printf 'Host GTK 3, AppIndicator and GNOME session services are required (use --bundle-deps to include libraries).\n'
fi
