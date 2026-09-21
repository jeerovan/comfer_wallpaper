import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:comfer_wallpaper/platform/desktop_platform.dart';

void main() {
  test('partial GNOME failure restores both previous settings', () async {
    final values = {
      'picture-uri': "'file:///old-light.jpg'",
      'picture-uri-dark': "'file:///old-dark.jpg'"
    };
    final before = Map.of(values);
    var failed = false;
    final platform = DesktopPlatform(run: (args) async {
      if (args.first == 'writable') return ProcessResult(0, 0, 'true', '');
      if (args.first == 'get') return ProcessResult(0, 0, values[args[2]], '');
      if (args[2] == 'picture-uri-dark' && !failed) {
        failed = true;
        throw const ProcessException('gsettings', [], 'injected failure');
      }
      values[args[2]] = args[3];
      return ProcessResult(0, 0, '', '');
    });
    await expectLater(
        platform.apply('/new image.jpg'), throwsA(isA<ProcessException>()));
    expect(values, before);
  }, skip: !Platform.isLinux);
}
