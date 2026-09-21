#!/usr/bin/python3
"""Regression checks for the pre-existing Linux helpers; no real install."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]


class HelpersTest(unittest.TestCase):
    def test_running_guard_consent_upgrade_and_uninstall(self):
        with tempfile.TemporaryDirectory(prefix='comfer helper ') as temporary:
            root = Path(temporary)
            source = root / 'bundle'
            source.mkdir()
            shutil.copy('/bin/sleep', source / 'comfer_wallpaper')
            data, config = root / 'data', root / 'config'
            env = dict(os.environ, XDG_DATA_HOME=str(data), XDG_CONFIG_HOME=str(config))
            entry = config / 'autostart' / 'com.jeerovan.comfer.desktop'
            entry.parent.mkdir(parents=True)
            entry.write_text('[Desktop Entry]\nHidden=true\n')
            original = entry.read_bytes()
            preserved = data / 'com.example.comfer_wallpaper' / 'wallpapers' / 'active.jpg'
            preserved.parent.mkdir(parents=True)
            preserved.write_bytes(b'keep active wallpaper')
            def run(name):
                return subprocess.run(['bash', str(REPO / 'packaging/linux' / name), str(source)],
                                      env=env, capture_output=True, text=True)
            self.assertEqual(run('install.sh').returncode, 0)
            self.assertEqual(entry.read_bytes(), original)
            executable = data / 'comfer-wallpaper' / 'comfer_wallpaper'
            process = subprocess.Popen([str(executable), '30'])
            try:
                self.assertNotEqual(run('install.sh').returncode, 0)
                self.assertNotEqual(run('uninstall.sh').returncode, 0)
                self.assertTrue(executable.exists())
                self.assertEqual(entry.read_bytes(), original)
            finally:
                process.terminate()
                process.wait(timeout=5)
            self.assertEqual(run('install.sh').returncode, 0)
            self.assertEqual(entry.read_bytes(), original)
            self.assertEqual(run('uninstall.sh').returncode, 0)
            self.assertFalse(entry.exists())
            self.assertFalse(executable.exists())
            self.assertEqual(preserved.read_bytes(), b'keep active wallpaper')


if __name__ == '__main__':
    unittest.main()
