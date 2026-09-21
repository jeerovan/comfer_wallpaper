import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:comfer_wallpaper/platform/desktop_platform.dart';
import 'package:comfer_wallpaper/services/wallpaper_service.dart';
import 'package:comfer_wallpaper/services/wallpaper_store.dart';
import 'package:comfer_wallpaper/app_controller.dart';
import 'package:comfer_wallpaper/services/tray_service.dart';
import 'package:comfer_wallpaper/services/wallpaper_scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native status item and persistent frequency', (_) async {
    final prefs = await SharedPreferences.getInstance();
    final previous = prefs.getString('frequency');
    final service = WallpaperService(
        store: WallpaperStore(await getTemporaryDirectory()),
        platform: DesktopPlatform(),
        userId: 'unused',
        client: http.Client());
    final controller = AppController(service, prefs);
    final tray = TrayService(controller, () async {}, () async {});
    try {
      await tray.initialize();
      final bounds = await trayManager.getBounds();
      expect(bounds, isNotNull);
      expect(bounds!.width, greaterThan(0));
      await controller.select(Frequency.daily);
      await prefs.reload();
      expect(prefs.getString('frequency'), 'daily');
      await controller.select(Frequency.hourly);
      await prefs.reload();
      expect(prefs.getString('frequency'), 'hourly');
    } finally {
      await tray.close();
      await controller.close();
      controller.dispose();
      if (previous == null) {
        await prefs.remove('frequency');
      } else {
        await prefs.setString('frequency', previous);
      }
    }
  });
  testWidgets('native wallpaper replacement, cleanup, and restoration',
      (_) async {
    final platform = DesktopPlatform();
    final original = await platform.currentPaths();
    expect(original, isNotEmpty);
    expect(await File(original.first).exists(), isTrue,
        reason:
            'The original wallpaper must exist before a reversible native test');
    final parent = await Directory(p.join(
            (await getApplicationSupportDirectory()).path, 'integration-test'))
        .create(recursive: true);
    final directory = await parent.createTemp('wallpapers-');
    final image = (await rootBundle.load('assets/comfer_launcher.png'))
        .buffer
        .asUint8List();
    final service = WallpaperService(
        store: WallpaperStore(directory),
        platform: platform,
        userId: 'local-test-only',
        client: MockClient((request) async => request.url.path == '/api'
            ? http.Response(
                jsonEncode({'imageUrl': 'https://example.com/test.png'}), 200)
            : http.Response.bytes(image, 200)));
    var restored = false;
    try {
      await service.initialize();
      await service.change();
      final old = service.store.file(service.store.current!);
      await service.change();
      expect(await old.exists(), isFalse);
      expect(service.store.owned, [service.store.current]);
      expect(await platform.currentPaths(),
          contains(service.store.file(service.store.current!).path));
    } catch (error, stack) {
      // Keep the original test failure visible even if restoration also fails.
      // ignore: avoid_print
      print('Native change failed: $error\n$stack');
      rethrow;
    } finally {
      await service.close();
      // NSScreen order is preserved by the native adapter; first is primary.
      await platform.apply(original.first);
      for (var i = 0; i < 20; i++) {
        if ((await platform.currentPaths()).contains(original.first)) {
          restored = true;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      if (restored) await directory.delete(recursive: true);
      expect(restored, isTrue,
          reason: 'Keep fixture files until desktop restoration is confirmed');
    }
  });
}
