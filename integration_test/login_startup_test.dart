import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comfer_wallpaper/platform/login_startup.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'native bridge reads status and refuses startup from build folder',
      (_) async {
    final startup = LoginStartup(await SharedPreferences.getInstance());
    final info = await startup.info();
    expect(info.status, inInclusiveRange(0, 3));
    expect(info.installed, isFalse);
    await expectLater(
        startup.enable(),
        throwsA(isA<PlatformException>()
            .having((error) => error.code, 'code', 'INSTALL_FIRST')));
    // This test must not register, unregister, or change the user's preferences.
  });
}
