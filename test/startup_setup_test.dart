import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comfer_wallpaper/platform/login_startup.dart';
import 'package:comfer_wallpaper/startup_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late LoginStartup startup;
  var status = 0;
  var installed = true;
  var registrations = 0;
  var settingsOpened = 0;
  var done = 0;
  var quit = 0;
  var fail = false;
  var approvalRequired = false;
  Completer<void>? registrationGate;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    startup = LoginStartup(prefs);
    status = 0;
    installed = true;
    registrations = 0;
    settingsOpened = 0;
    done = 0;
    quit = 0;
    fail = false;
    approvalRequired = false;
    registrationGate = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LoginStartup.channel, (call) async {
      if (fail) throw PlatformException(code: 'unavailable');
      switch (call.method) {
        case 'getLoginStartup':
          return {'status': status, 'installed': installed};
        case 'enableLoginStartup':
          registrations++;
          await registrationGate?.future;
          status = approvalRequired ? 2 : 1;
          return null;
        case 'openLoginSettings':
          settingsOpened++;
          return null;
      }
      throw MissingPluginException();
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LoginStartup.channel, null);
  });
  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StartupSetup(
                startup: startup,
                onDone: () async {
                  done++;
                },
                onQuit: () async {
                  quit++;
                }))));
    await tester.pumpAndSettle();
  }

  test('fresh user needs setup; enabled installer users do not', () async {
    expect(await startup.needsSetup(), isTrue);
    status = 1;
    expect(await startup.needsSetup(), isFalse);
    expect(prefs.getBool(LoginStartup.completionKey), isTrue);
    expect(registrations, 0);
  });
  test('completed choice is respected after OS startup is disabled', () async {
    await startup.complete();
    status = 2;
    expect(await startup.needsSetup(), isFalse);
    expect(registrations, 0);
  });
  testWidgets('enable registers once and remembers completion', (tester) async {
    await show(tester);
    expect(registrations, 0);
    registrationGate = Completer<void>();
    await tester.tap(find.text('Start at login'));
    await tester.pump();
    expect(find.text('Please wait…'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    registrationGate!.complete();
    await tester.pumpAndSettle();
    expect(registrations, 1);
    expect(done, 1);
    expect(await startup.needsSetup(), isFalse);
  });
  testWidgets('Not now dismisses without registering and persists',
      (tester) async {
    await show(tester);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(done, 1);
    expect(registrations, 0);
    expect(await startup.needsSetup(), isFalse);
  });
  testWidgets('approval stays visible until status is enabled', (tester) async {
    approvalRequired = true;
    await show(tester);
    await tester.tap(find.text('Start at login'));
    await tester.pumpAndSettle();
    expect(done, 0);
    expect(prefs.getBool(LoginStartup.completionKey), isNull);
    await tester.tap(find.text('Open System Settings'));
    await tester.pumpAndSettle();
    expect(settingsOpened, 1);
    expect(registrations, 1);
    status = 1;
    await tester.tap(find.text('Check again'));
    await tester.pumpAndSettle();
    expect(done, 1);
    expect(prefs.getBool(LoginStartup.completionKey), isTrue);
  });
  testWidgets('DMG launch asks to install without recording a decision',
      (tester) async {
    installed = false;
    await show(tester);
    expect(find.text('Start at login'), findsNothing);
    await tester.tap(find.text('Quit and install'));
    await tester.pumpAndSettle();
    expect(quit, 1);
    expect(registrations, 0);
    expect(prefs.getBool(LoginStartup.completionKey), isNull);
  });
  testWidgets('registration failure remains retryable', (tester) async {
    await show(tester);
    fail = true;
    await tester.tap(find.text('Start at login'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Could not update login startup'), findsOneWidget);
    expect(done, 0);
    expect(prefs.getBool(LoginStartup.completionKey), isNull);
    fail = false;
    await tester.tap(find.text('Start at login'));
    await tester.pumpAndSettle();
    expect(done, 1);
  });
}
