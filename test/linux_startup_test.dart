import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comfer_wallpaper/platform/login_startup.dart';
import 'package:comfer_wallpaper/platform/linux_startup.dart';

class InstalledStartup extends LinuxStartup {
  InstalledStartup(String config)
      : super(
            configHome: config,
            executable: '/home/test/App with spaces/comfer_wallpaper');
  @override
  bool get installed => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('AppImage startup uses the stable outer file, not the mount path', () {
    final startup = LinuxStartup(environment: {
      'APPIMAGE': '/home/test/Applications/Comfer Wallpaper.AppImage',
      'APPDIR': '/tmp/.mount_comfer',
    }, resolvedExecutable: '/tmp/.mount_comfer/usr/bin/comfer_wallpaper');
    expect(startup.executable,
        '/home/test/Applications/Comfer Wallpaper.AppImage');
    expect(
        LinuxStartup.appImagePath({
          'APPIMAGE': '/home/test/Comfer.AppImage',
          'APPDIR': '/tmp/other',
        }, '/usr/bin/comfer_wallpaper'),
        isNull);
    expect(
        LinuxStartup.appImagePath({
          'APPIMAGE': 'relative.AppImage',
          'APPDIR': '/tmp/mount',
        }, '/tmp/mount/usr/bin/comfer_wallpaper'),
        isNull);
    expect(
        LinuxStartup.appImagePath({
          'APPIMAGE': '/home/test/Comfer.AppImage',
          'APPDIR': '/tmp/mount',
        }, '/tmp/mount-other/usr/bin/comfer_wallpaper'),
        isNull);
  });
  test(
      'Linux first-launch consent persists without overriding external disable',
      () async {
    final root = await Directory.systemTemp.createTemp('comfer-consent-');
    addTearDown(() => root.delete(recursive: true));
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final linux = InstalledStartup(root.path);
    final startup = LoginStartup(prefs, linux: linux);
    expect(await startup.needsSetup(), true);
    await startup.enable();
    expect((await startup.info()).enabled, true);
    await startup.complete();
    await linux.disable();
    expect(await startup.needsSetup(), false);
    expect(await linux.enabled(), false);
    await linux.entry.delete();
    expect(await startup.needsSetup(), false);
    expect(await linux.entry.exists(), false);
  });
  test('Linux Not now remembers choice without creating an entry', () async {
    final root = await Directory.systemTemp.createTemp('comfer-decline-');
    addTearDown(() => root.delete(recursive: true));
    SharedPreferences.setMockInitialValues({});
    final linux = InstalledStartup(root.path);
    final startup =
        LoginStartup(await SharedPreferences.getInstance(), linux: linux);
    await startup.complete();
    expect(await startup.needsSetup(), false);
    expect(await linux.entry.exists(), false);
  });
  test('Exec quotes spaces and both escaping layers without shell expansion',
      () {
    expect(
        LinuxStartup.quoteExec('/home/me/My App/bin'), '"/home/me/My App/bin"');
    expect(LinuxStartup.quoteExec(r'/home/me/$cash%/bin'),
        r'"/home/me/\\$cash%%/bin"');
    expect(() => LinuxStartup.quoteExec('/bad\npath'), throwsFormatException);
  });
  test('disabled entry remains disabled and repeated disable uses one entry',
      () async {
    final root = await Directory.systemTemp.createTemp('comfer-startup-');
    addTearDown(() => root.delete(recursive: true));
    final startup = LinuxStartup(
        configHome: root.path, executable: '/tmp/bundle/comfer_wallpaper');
    expect(await startup.enabled(), false);
    await startup.disable();
    await startup.disable();
    expect(await startup.enabled(), false);
    expect(await startup.entry.parent.list().length, 1);
    await startup.entry.writeAsString(
        '[Desktop Entry]\nExec="/old path/app"\nX-GNOME-Autostart-enabled=false\n');
    expect(await startup.enabled(), false);
    expect(startup.installed, false);
    await expectLater(startup.enable(), throwsStateError);
  });
}
