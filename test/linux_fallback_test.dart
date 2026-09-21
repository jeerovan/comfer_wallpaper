import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:comfer_wallpaper/app_controller.dart';
import 'package:comfer_wallpaper/main.dart';
import 'package:comfer_wallpaper/platform/desktop_platform.dart';
import 'package:comfer_wallpaper/services/wallpaper_service.dart';
import 'package:comfer_wallpaper/services/wallpaper_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('desktop detection checks whole session identifiers', () {
    expect(DesktopPlatform.supportsLinuxDesktop('ubuntu:GNOME'), true);
    expect(DesktopPlatform.supportsLinuxDesktop('KDE'), false);
    expect(DesktopPlatform.supportsLinuxDesktop('not-gnome'), false);
  });
  testWidgets('fallback explains missing tray and retains all controls',
      (tester) async {
    tester.view.physicalSize = const Size(400, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final controller = AppController(
        WallpaperService(
            store: WallpaperStore(Directory.systemTemp),
            platform: DesktopPlatform(),
            userId: 'unused',
            client: http.Client()),
        await SharedPreferences.getInstance());
    addTearDown(() async {
      await controller.close();
      controller.dispose();
    });
    controller.setFallbackReason(
        'The tray icon is unavailable. Keep this window open to control Comfer.');
    controller.report(StateError('operation failed'));
    await tester
        .pumpWidget(ComferApp(controller: controller, quit: () async {}));
    expect(find.textContaining('tray icon is unavailable'), findsOneWidget);
    for (final label in ['Hourly', 'Daily', 'Change now', 'Quit']) {
      await tester.scrollUntilVisible(find.text(label), 80);
      expect(find.text(label).hitTestable(), findsOneWidget);
    }
    await tester.ensureVisible(find.text('Quit'));
    expect(find.text('Quit').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    final lifecycle =
        DesktopLifecycle(controller, () async {}, desktopSupported: false);
    expect(lifecycle.hasTray, true);
    expect(lifecycle.canHide, false);
  });
}
