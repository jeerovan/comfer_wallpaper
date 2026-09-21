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
