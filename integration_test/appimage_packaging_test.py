#!/usr/bin/python3
"""Packaging contract tests with a stub packer; native image smoke test is separate."""
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest
import zlib

REPO = Path(__file__).resolve().parents[1]
SCRIPT = REPO / 'packaging/linux/build-appimage.sh'

class PackagingTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='comfer packaging ')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.bundle = self.root / 'release bundle'
        (self.bundle / 'lib').mkdir(parents=True)
        (self.bundle / 'data/flutter_assets/assets').mkdir(parents=True)
        for name in ('comfer_wallpaper', 'lib/libapp.so', 'lib/libflutter_linux_gtk.so'):
            shutil.copy('/bin/true', self.bundle / name)
        (self.bundle / 'data/icudtl.dat').write_bytes(b'fixture')
        shutil.copy(REPO / 'assets/comfer_launcher.png', self.bundle / 'data/flutter_assets/assets/comfer_launcher.png')
        self.tool = self.root / 'stub packer'
        self.tool.write_text('#!/usr/bin/python3\nimport os, pathlib, shutil, sys\n'
                            'shutil.copytree(sys.argv[-2], os.environ["CAPTURE"], symlinks=True)\n'
                            'pathlib.Path(sys.argv[-1]).write_bytes(b"test image")\n')
        self.tool.chmod(0o755)
        self.capture = self.root / 'captured AppDir'
        self.output = self.root / 'output with spaces.AppImage'
        self.env = dict(os.environ, CAPTURE=str(self.capture))

    def run_script(self, *args):
        return subprocess.run(['bash', str(SCRIPT), '--bundle', str(self.bundle),
                               '--appimagetool', str(self.tool), '--output', str(self.output), *args],
                              cwd='/', env=self.env, text=True, capture_output=True)

    def test_layout_icons_arguments_and_source_unchanged(self):
        original = (self.bundle / 'data/flutter_assets/assets/comfer_launcher.png').read_bytes()
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(os.access(self.output, os.X_OK))
        self.assertEqual((self.capture / '.DirIcon').read_bytes(), original)
        self.assertEqual((self.capture / 'usr/bin/data/flutter_assets/assets/comfer_launcher.png').read_bytes(), original)
        self.assertTrue((self.capture / 'usr/bin/lib/libapp.so').exists())
        self.assertIn('Icon=com.jeerovan.comfer', (self.capture / 'com.jeerovan.comfer.desktop').read_text())
        # Substitute a recorder to verify AppRun forwards paths/arguments unchanged.
        runner = self.capture / 'usr/bin/comfer_wallpaper'
        runner.write_text('#!/usr/bin/python3\nimport json,sys\nprint(json.dumps(sys.argv[1:]))\n')
        runner.chmod(0o755)
        r = subprocess.run([str(self.capture / 'AppRun'), '--show', 'a space'], cwd='/', text=True, capture_output=True)
        self.assertEqual(r.stdout.strip(), '["--show", "a space"]')
        self.assertEqual((self.bundle / 'data/flutter_assets/assets/comfer_launcher.png').read_bytes(), original)
        self.assertFalse(list(self.root.glob('.comfer-appimage.*')))
        self.assertNotEqual(self.run_script().returncode, 0)
        self.assertEqual(self.output.read_bytes(), b'test image')

    def test_separate_app_and_tray_icons(self):
        def png(size):
            def chunk(kind, data):
                return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
            return (b'\x89PNG\r\n\x1a\n' +
                    chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0)) +
                    chunk(b'IDAT', zlib.compress((b'\x00' + b'\xff\xff\xff\xff' * size) * size)) +
                    chunk(b'IEND', b''))
        app, tray = self.root / 'launcher.png', self.root / 'tray.png'
        app.write_bytes(png(256))
        tray.write_bytes(png(64))
        result = self.run_script('--app-icon', str(app), '--tray-icon', str(tray))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.capture / '.DirIcon').read_bytes(), app.read_bytes())
        self.assertEqual((self.capture / 'usr/bin/data/flutter_assets/assets/comfer_launcher.png').read_bytes(), tray.read_bytes())
        self.assertNotEqual((self.bundle / 'data/flutter_assets/assets/comfer_launcher.png').read_bytes(), tray.read_bytes())

    def dependency_tools(self):
        tools = self.root / 'tools'
        tools.mkdir()
        modules = self.root / 'gio-modules'
        modules.mkdir()
        (modules / 'giomodule.cache').write_text('fixture')
        pkgconfig = tools / 'pkg-config'
        pkgconfig.write_text('#!/usr/bin/python3\nimport sys\n'
                             'if "--variable=giomoduledir" in sys.argv: print(' + repr(str(modules)) + ')\n')
        pkgconfig.chmod(0o755)
        deploy = tools / 'linuxdeploy'
        deploy.write_text('#!/usr/bin/python3\nimport pathlib,sys,shutil\n'
                          'root=pathlib.Path(sys.argv[sys.argv.index("--appdir")+1])\n'
                          'for name in ["libgtk-3.so.0", "libayatana-appindicator3.so.1"]:\n'
                          ' shutil.copy("/bin/true", root/"usr/lib"/name)\n')
        deploy.chmod(0o755)
        plugin = tools / 'linuxdeploy-plugin-gtk.sh'
        plugin.write_text('#!/usr/bin/python3\nimport pathlib,sys\n'
                          'root=pathlib.Path(sys.argv[2]); (root/"apprun-hooks").mkdir(exist_ok=True)\n'
                          '(root/"apprun-hooks/linuxdeploy-plugin-gtk.sh").write_text('
                          + repr('export GDK_BACKEND=x11\nexport GSETTINGS_SCHEMA_DIR="$APPDIR/schemas"\nexport XDG_DATA_DIRS="$APPDIR/usr/share"\n') + ')\n')
        plugin.chmod(0o755)
        self.env['PATH'] = str(tools) + os.pathsep + os.environ['PATH']
        # Explicit flags must override environment defaults, not just find tools on PATH.
        self.env['LINUXDEPLOY'] = '/missing/default-linuxdeploy'
        self.env['LINUXDEPLOY_GTK_PLUGIN'] = '/missing/default-gtk-plugin'
        return deploy, plugin

    def test_bundled_layout_hooks_and_clean_host_commands(self):
        deploy, plugin = self.dependency_tools()
        result = self.run_script('--bundle-deps', '--linuxdeploy', str(deploy), '--gtk-plugin', str(plugin))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.capture / 'usr/bin/lib').is_symlink())
        self.assertTrue((self.capture / 'usr/lib/libapp.so').exists())
        self.assertTrue((self.capture / 'usr/lib/gio/modules/giomodule.cache').exists())
        # Probe the app environment and a host tool launched from it.
        host = self.root / 'host-tools'; host.mkdir()
        command = host / 'gsettings'
        command.write_text('#!/usr/bin/python3\nimport os,json\n'
                           'print(json.dumps({k:os.environ.get(k) for k in ["LD_LIBRARY_PATH","GSETTINGS_SCHEMA_DIR","XDG_DATA_DIRS","GDK_BACKEND"]}))\n')
        command.chmod(0o755)
        runner = self.capture / 'usr/bin/comfer_wallpaper'
        runner.write_text('#!/usr/bin/python3\nimport os,json,subprocess\n'
                          'print(json.dumps({"schema":os.environ.get("GSETTINGS_SCHEMA_DIR"),'
                          '"backend":os.environ.get("GDK_BACKEND"),'
                          '"host":json.loads(subprocess.check_output(["gsettings"],text=True))}))\n')
        runner.chmod(0o755)
        import json
        for backend in (None, 'wayland'):
            env = dict(os.environ, PATH=str(host)+os.pathsep+os.environ['PATH'],
                       LD_LIBRARY_PATH='/host/libraries', GSETTINGS_SCHEMA_DIR='/host/schemas',
                       XDG_DATA_DIRS='/host/share')
            env.pop('GDK_BACKEND', None)
            if backend: env['GDK_BACKEND'] = backend
            run = subprocess.run([str(self.capture / 'AppRun')], cwd='/', env=env, text=True, capture_output=True)
            self.assertEqual(run.returncode, 0, run.stderr)
            value = json.loads(run.stdout)
            self.assertEqual(value['schema'], str(self.capture / 'schemas'))
            self.assertEqual(value['backend'], backend)
            self.assertEqual(value['host'], {'LD_LIBRARY_PATH':'/host/libraries',
                             'GSETTINGS_SCHEMA_DIR':'/host/schemas', 'XDG_DATA_DIRS':'/host/share',
                             'GDK_BACKEND':backend})

    def test_dependency_failure_does_not_publish(self):
        deploy, plugin = self.dependency_tools()
        deploy.write_text('#!/bin/sh\nexit 42\n')
        result = self.run_script('--bundle-deps', '--linuxdeploy', str(deploy), '--gtk-plugin', str(plugin))
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.output.exists())
        self.assertFalse(list(self.root.glob('.comfer-appimage.*')))

    def test_missing_release_fails_without_output(self):
        (self.bundle / 'lib/libapp.so').unlink()
        self.assertNotEqual(self.run_script().returncode, 0)
        self.assertFalse(self.output.exists())

    def test_arm_payload_is_rejected(self):
        executable = self.bundle / 'comfer_wallpaper'
        data = bytearray(executable.read_bytes())
        struct.pack_into('<H', data, 18, 183)
        executable.write_bytes(data)
        self.assertNotEqual(self.run_script().returncode, 0)
        self.assertFalse(self.output.exists())

    def test_invalid_icon_and_packer_failure_leave_no_output(self):
        bad = self.root / 'bad.png'
        bad.write_text('not a PNG')
        self.assertNotEqual(self.run_script('--app-icon', str(bad)).returncode, 0)
        self.tool.write_text('#!/bin/sh\nexit 42\n')
        self.assertNotEqual(self.run_script().returncode, 0)
        self.assertFalse(self.output.exists())
        self.assertFalse(list(self.root.glob('.comfer-appimage.*')))

if __name__ == '__main__':
    unittest.main()
