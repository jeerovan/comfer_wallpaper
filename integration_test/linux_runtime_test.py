#!/usr/bin/python3
"""Reversible GNOME session validation of a compiled bundle (requires python3-gi)."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import gi
gi.require_version('Atspi', '2.0')
from gi.repository import Gio, GLib, Atspi

bundle = Path(sys.argv[1]).resolve()
assert (bundle / 'comfer_wallpaper').is_file()
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)

def call(dest, path, interface, method, signature=None, args=()):
    return bus.call_sync(dest, path, interface, method,
                         GLib.Variant(signature, args) if signature else None,
                         None, Gio.DBusCallFlags.NONE, 5000, None).unpack()

def items():
    return call('org.kde.StatusNotifierWatcher', '/StatusNotifierWatcher',
                'org.freedesktop.DBus.Properties', 'Get', '(ss)',
                ('org.kde.StatusNotifierWatcher', 'RegisteredStatusNotifierItems'))[0]

def wait(check, seconds=40):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        try:
            result = check()
        except (StopIteration, json.JSONDecodeError):
            result = None
        if result:
            return result
        time.sleep(.2)
    raise AssertionError('Timed out: ' + str(check))

def setting(key, value=None):
    return subprocess.check_output(['gsettings', 'get' if value is None else 'set',
                                   'org.gnome.desktop.background', key] +
                                  ([] if value is None else [value]), text=True).strip()

original = {key: setting(key) for key in ('picture-uri', 'picture-uri-dark')}
parent = Path.home() / '.local' / 'opt'
parent.mkdir(parents=True, exist_ok=True)
process = None
restored = False
root = Path(tempfile.mkdtemp(prefix='Comfer validation ', dir=parent))
try:
    installed = root / 'App with spaces'
    shutil.copytree(bundle, installed)
    exe = installed / 'comfer_wallpaper'
    data = root / 'xdg data'
    config = root / 'xdg config'
    env = dict(os.environ, XDG_DATA_HOME=str(data), XDG_CONFIG_HOME=str(config))
    # Keep wallpaper commands on the real signed-in session's dconf database.
    # XDG_CONFIG_HOME above isolates only the app's autostart registration.
    command_dir = root / 'commands'
    command_dir.mkdir()
    wrapper = command_dir / 'gsettings'
    wrapper.write_text('#!/usr/bin/python3\nimport os, sys\n' +
                       'os.environ["XDG_CONFIG_HOME"] = ' + repr(os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config'))) + '\n' +
                       'os.execv("/usr/bin/gsettings", ["gsettings"] + sys.argv[1:])\n')
    wrapper.chmod(0o755)
    env['PATH'] = str(command_dir) + os.pathsep + os.environ['PATH']
    prefs = data / 'com.example.comfer_wallpaper' / 'shared_preferences.json'
    prefs.parent.mkdir(parents=True)
    prefs.write_text(json.dumps({'flutter.login_setup_completed': True,
                                'flutter.user_id': 'linux-runtime-validation'}))
    entry = config / 'autostart' / 'com.jeerovan.comfer.desktop'
    if 'build' in bundle.parts:
        rejected = subprocess.run([str(bundle / 'comfer_wallpaper'), '--enable-startup'],
                                  env=env, cwd='/', capture_output=True, timeout=20)
        assert rejected.returncode == 1 and not entry.exists()
        print('PASS development-build startup rejection exits cleanly', flush=True)
    def command(flag):
        return subprocess.run([str(exe), flag], env=env, cwd='/',
                              capture_output=True, text=True, timeout=25, check=True)
    command('--enable-startup')
    assert str(exe) in entry.read_text()
    launch_command = Gio.DesktopAppInfo.new_from_filename(str(entry)).get_commandline()
    startup_argv = GLib.shell_parse_argv(launch_command)[1]
    assert startup_argv == [str(exe)]
    command('--enable-startup')
    assert len(list(entry.parent.glob('*.desktop'))) == 1
    assert command('--startup-status').stdout.strip() == 'enabled'
    command('--disable-startup')
    disabled = entry.read_text()
    assert command('--startup-status').stdout.strip() == 'disabled'
    print('PASS startup enable/repeat/status/disable; executable path has spaces', flush=True)

    def visible_window():
        desktop = Atspi.get_desktop(0)
        for index in range(desktop.get_child_count()):
            app = desktop.get_child_at_index(index)
            if app.get_process_id() == process.pid:
                for child_index in range(app.get_child_count()):
                    window = app.get_child_at_index(child_index)
                    if window.get_state_set().contains(Atspi.StateType.SHOWING):
                        return window
        return None
    before = set(items())
    log = (root / 'application.log').open('w')
    process = subprocess.Popen(startup_argv, env=env, cwd='/', stdout=log, stderr=log)
    item = wait(lambda: next(iter(set(items()) - before), None))
    print('Registered item:', item, flush=True)
    dest, _, item_path = item.partition('/')
    dest = dest.rstrip('@')
    item_path = '/' + item_path
    menu = call(dest, item_path, 'org.freedesktop.DBus.Properties', 'Get', '(ss)',
                ('org.kde.StatusNotifierItem', 'Menu'))[0]
    def layout():
        return call(dest, menu, 'com.canonical.dbusmenu', 'GetLayout', '(iias)', (0, -1, []))[1]
    def nodes(node):
        yield node
        for child in node[2]:
            yield from nodes(child)
    def find(label):
        return next(n for n in nodes(layout()) if n[1].get('label') == label)
    def click(label):
        for attempt in range(5):
            node = find(label)
            assert node[1].get('enabled', True)
            try:
                call(dest, menu, 'com.canonical.dbusmenu', 'Event', '(isvu)',
                     (node[0], 'clicked', GLib.Variant('i', 0), 0))
                return
            except GLib.GError as error:
                if 'does not refer to a menu item' not in str(error) or attempt == 4:
                    raise
                time.sleep(.2)
    wait(lambda: find('Hourly')[1].get('toggle-state') == 1)
    assert visible_window() is None
    print('PASS hidden startup with a usable tray', flush=True)
    click('Daily')
    wait(lambda: json.loads(prefs.read_text()).get('flutter.frequency') == 'daily')
    wait(lambda: find('Daily')[1].get('toggle-state') == 1 and find('Hourly')[1].get('toggle-state') == 0)
    print('PASS native menu selection and checked Daily state', flush=True)
    duplicate = subprocess.run([str(exe)], env=env, cwd='/', capture_output=True, timeout=20)
    assert duplicate.returncode == 0 and process.poll() is None
    assert set(items()) - before == {item}
    print('PASS duplicate launch exits; one tray/scheduler remains', flush=True)
    manifest = prefs.parent / 'wallpapers' / 'state.json'
    def current():
        if manifest.exists():
            state = json.loads(manifest.read_text())
            if state.get('current') and not state.get('pending'):
                return state['current']
        return None
    first = wait(current, 150)
    wait(lambda: find('Change now'))
    click('Change now')
    second = wait(lambda: current() if current() != first else None, 150)
    state = json.loads(manifest.read_text())
    assert state['owned'] == [second]
    assert not (manifest.parent / first).exists()
    assert all(str(manifest.parent / second).replace(' ', '%20') in setting(k) for k in original)
    assert entry.read_text() == disabled
    print('PASS two real API wallpapers, desktop confirmation, cleanup, disabled startup preserved', flush=True)
    time.sleep(.5)  # Allow queued native menu rebuilds to finish before the next action.
    click('Quit')
    assert process.wait(timeout=15) == 0
    time.sleep(2)
    assert not (set(items()) - before)
    print('PASS native Quit stops app without restart', flush=True)
    process = subprocess.Popen([str(exe)], env=env, cwd='/', stdout=log, stderr=log)
    item = wait(lambda: next(iter(set(items()) - before), None))
    print('Registered item:', item, flush=True)
    dest, _, item_path = item.partition('/')
    dest = dest.rstrip('@')
    item_path = '/' + item_path
    menu = call(dest, item_path, 'org.freedesktop.DBus.Properties', 'Get', '(ss)',
                ('org.kde.StatusNotifierItem', 'Menu'))[0]
    wait(lambda: find('Daily')[1].get('toggle-state') == 1)
    click('Hourly')
    wait(lambda: find('Hourly')[1].get('toggle-state') == 1)
    time.sleep(.5)  # Allow queued native menu rebuilds to finish before the next action.
    click('Quit')
    assert process.wait(timeout=15) == 0
    print('PASS frequency survives process restart; Hourly control works', flush=True)
    relocated = root / 'Relocated App'
    installed.rename(relocated)
    exe = relocated / 'comfer_wallpaper'
    assert command('--startup-status').stdout.strip() == 'disabled'
    command('--enable-startup')
    assert str(exe) in entry.read_text() and str(installed) not in entry.read_text()
    command('--disable-startup')
    entry.unlink()
    assert command('--startup-status').stdout.strip() == 'disabled'
    print('PASS relocation, explicit re-registration and uninstall registration removal', flush=True)
    # Force host detection failure without removing the user's GNOME extension.
    probe = command_dir / 'gdbus'
    probe.write_text('#!/bin/sh\nexit 1\n')
    probe.chmod(0o755)
    process = subprocess.Popen([str(exe)], env=env, cwd='/', stdout=log, stderr=log)
    wait(visible_window)
    process.terminate()
    assert process.wait(timeout=15) == 0
    print('PASS visible accessible fallback when tray host probe fails; graceful SIGTERM', flush=True)
    probe.unlink()
    unsupported_env = dict(env, XDG_CURRENT_DESKTOP='KDE')
    process = subprocess.Popen([str(exe)], env=unsupported_env, cwd='/', stdout=log, stderr=log)
    wait(visible_window)
    process.terminate()
    assert process.wait(timeout=15) == 0
    print('PASS unsupported desktop stays visible even with a real tray host', flush=True)
finally:
    if process and process.poll() is None:
        process.terminate()
        process.wait(timeout=15)
    for key, value in original.items():
        setting(key, value)
    restored = all(setting(k) == v for k, v in original.items())
    if sys.exc_info()[0] is not None:
        print((root / 'application.log').read_text() if (root / 'application.log').exists() else '')
    if restored:
        shutil.rmtree(root)
    else:
        print('Restoration failed; fixtures preserved at', root)
    assert restored
    print('Original wallpaper settings restored; isolated validation data removed', flush=True)
