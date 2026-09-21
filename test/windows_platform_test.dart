import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comfer_wallpaper/platform/desktop_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
      () => messenger.setMockMethodCallHandler(DesktopPlatform.channel, null));

  test('secondary wallpaper cannot confirm a primary change', () {
    final desktop = DesktopPlatform();
    expect(
        desktop.confirms({'old.jpg', 'candidate.jpg'}, 'candidate.jpg'), false);
    expect(
        desktop.confirms({'candidate.jpg', 'secondary.jpg'}, 'candidate.jpg'),
        true);
    expect(desktop.confirms({}, 'candidate.jpg'), false);
  }, skip: !Platform.isWindows);

  test('native failure propagates instead of reporting success', () async {
    messenger.setMockMethodCallHandler(DesktopPlatform.channel, (_) async {
      throw PlatformException(code: 'APPLY_FAILED', message: 'HRESULT -1');
    });
    await expectLater(
        DesktopPlatform().apply(r'C:\Images\wallpaper.jpg'),
        throwsA(isA<PlatformException>()
            .having((e) => e.code, 'code', 'APPLY_FAILED')));
  }, skip: !Platform.isWindows);

  test('native adapter preserves Unicode paths and display order', () async {
    const primary = r'C:\Images with spaces\山.jpg';
    messenger.setMockMethodCallHandler(DesktopPlatform.channel, (call) async {
      if (call.method == 'getWallpaperPaths') {
        return [primary, r'C:\second.png'];
      }
      expect(call.arguments, {'path': primary});
      return true;
    });
    final desktop = DesktopPlatform();
    expect((await desktop.currentPaths()).first, primary);
    await desktop.apply(primary);
  }, skip: !Platform.isWindows);
}
