import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:window_manager/window_manager.dart';
import 'app_controller.dart';
import 'platform/desktop_platform.dart';
import 'platform/login_startup.dart';
import 'platform/linux_startup.dart';
import 'startup_setup.dart';
import 'services/tray_service.dart';
import 'services/wallpaper_scheduler.dart';
import 'services/wallpaper_service.dart';
import 'services/wallpaper_store.dart';

Future<void> main(List<String> arguments) async {
  if (Platform.isLinux) {
    try {
      final startup = LinuxStartup();
      if (arguments.contains('--startup-status')) {
        stdout.writeln(await startup.enabled() ? 'enabled' : 'disabled');
        exit(0);
      }
      if (arguments.contains('--disable-startup')) {
        await startup.disable();
        exit(0);
      }
      if (arguments.contains('--enable-startup')) {
        await startup.enable();
        exit(0);
      }
    } catch (error) {
      stderr.writeln('Could not update login startup: $error');
      exit(1);
    }
  }

  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  final support = await getApplicationSupportDirectory();
  await support.create(recursive: true);
  final lock = await File(p.join(support.path, 'instance.lock'))
      .open(mode: FileMode.append);
  try {
    await lock.lock(FileLock.exclusive);
  } on FileSystemException {
    await lock.close();
    exit(0);
  }
  final prefs = await SharedPreferences.getInstance();
  final startup = (Platform.isMacOS || Platform.isLinux)
      ? LoginStartup(prefs, linux: Platform.isLinux ? LinuxStartup() : null)
      : null;
  final setupVisible = ValueNotifier(await startup?.needsSetup() ?? false);
  var userId = prefs.getString('user_id');
  if (userId == null || userId.isEmpty) {
    userId = const Uuid().v4();
    if (!await prefs.setString('user_id', userId)) {
      throw StateError('Cannot save identity');
    }
  }
  final desktop = DesktopPlatform();
  final controller = AppController(
      WallpaperService(
          store: WallpaperStore(Directory(p.join(support.path, 'wallpapers'))),
          platform: desktop,
          userId: userId,
          client: http.Client()),
      prefs);
  final logFile = File(p.join(support.path, 'comfer.log'));
  controller.log = (message) {
    try {
      if (logFile.existsSync() && logFile.lengthSync() > 256 * 1024) {
        logFile.renameSync('${logFile.path}.previous');
      }
      logFile.writeAsStringSync(
          '${DateTime.now().toUtc().toIso8601String()} $message\n',
          mode: FileMode.append);
    } catch (_) {/* Logging cannot stop the wallpaper service. */}
  };
  var quitting = false;
  controller.log?.call('Startup: preferences and controller ready');
  TrayService? tray;
  Future<void> quit() async {
    if (quitting) return;
    quitting = true;
    await controller.close();
    try {
      await tray?.close();
    } finally {
      await lock.close();
      exit(0);
    }
  }

  Future<void> show() async {
    if (Platform.isLinux || Platform.isWindows) {
      await windowManager.setSkipTaskbar(false);
    }
    await windowManager.show();
    await windowManager.focus();
  }

  if (Platform.isWindows) {
    DesktopPlatform.channel.setMethodCallHandler((call) async {
      if (call.method == 'quitRequested') await quit();
      if (call.method == 'resume') controller.scheduler.reconcile();
    });
    await DesktopPlatform.channel.invokeMethod<void>('controllerReady');
    controller.log?.call('Startup: Windows lifecycle ready');
  }

  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen((_) => unawaited(quit()));
    ProcessSignal.sigint.watch().listen((_) => unawaited(quit()));
  }

  final lifecycle = DesktopLifecycle(controller, quit,
      desktopSupported: desktop.supported,
      isSettingUp: () => setupVisible.value);
  windowManager.addListener(lifecycle);
  WidgetsBinding.instance.addObserver(lifecycle);
  Future<void> finishSetup() async {
    setupVisible.value = false;
    if (lifecycle.canHide) await windowManager.hide();
  }

  runApp(ValueListenableBuilder<bool>(
    valueListenable: setupVisible,
    builder: (context, visible, _) => ComferApp(
      controller: controller,
      quit: quit,
      setup: visible && startup != null
          ? StartupSetup(startup: startup, onDone: finishSetup, onQuit: quit)
          : null,
    ),
  ));
  await windowManager.waitUntilReadyToShow(const WindowOptions(
      size: Size(460, 430),
      minimumSize: Size(400, 320),
      center: true,
      skipTaskbar: true,
      title: 'Comfer Wallpaper'));
  controller.log?.call('Startup: window ready');
  await windowManager.setPreventClose(true);
  await windowManager.hide();
  void updateFallback() {
    controller.setFallbackReason(!desktop.supported
        ? 'This desktop is unsupported. Linux wallpaper changes require GNOME. You can still change frequency or quit here.'
        : !lifecycle.hasTray
            ? 'The tray icon is unavailable. Keep this window open to control Comfer.'
            : null);
  }

  try {
    tray = TrayService(controller, quit, show);
    await tray.initialize();
    controller.log?.call('Startup: tray initialized');
    lifecycle.hasTray = await tray.usable();
    updateFallback();
    if (!lifecycle.canHide) await show();
  } catch (_) {
    lifecycle.hasTray = false;
    updateFallback();
    await show();
  }
  if (arguments.contains('--show')) {
    await show();
    controller.log?.call('Startup: control window shown');
  }
  if (Platform.isLinux) {
    Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (quitting) {
        timer.cancel();
        return;
      }
      final usable = await tray?.usable() ?? false;
      final wasHiddenEligible = lifecycle.canHide;
      lifecycle.hasTray = usable;
      updateFallback();
      if (wasHiddenEligible && !lifecycle.canHide) await show();
    });
  }
  if (setupVisible.value) await show();
  await controller.start();
  controller.log?.call('Startup: scheduler started');
  if (arguments.contains('--change-now')) {
    await controller.scheduler.changeNow();
  }
}

class DesktopLifecycle with WindowListener, WidgetsBindingObserver {
  DesktopLifecycle(this.controller, this.quit,
      {this.isSettingUp, this.desktopSupported = true});
  final bool desktopSupported;
  bool get canHide => hasTray && desktopSupported;
  final AppController controller;
  final Future<void> Function() quit;
  final bool Function()? isSettingUp;
  bool hasTray = true;
  @override
  void onWindowClose() {
    if (canHide && isSettingUp?.call() != true) {
      windowManager.hide();
    } else {
      unawaited(quit());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) controller.scheduler.reconcile();
  }
}

class ComferApp extends StatelessWidget {
  const ComferApp(
      {super.key, required this.controller, required this.quit, this.setup});
  final AppController controller;
  final Future<void> Function() quit;
  final Widget? setup;
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Comfer Wallpaper',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
            colorSchemeSeed: const Color(0xff486b58), useMaterial3: true),
        home: Scaffold(
            body: SafeArea(
                child: setup ??
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: ListenableBuilder(
                          listenable: controller,
                          builder: (context, _) => ListView(
                                children: [
                                  Text('Comfer Wallpaper',
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall),
                                  const SizedBox(height: 12),
                                  if (controller.fallbackReason != null) ...[
                                    Text(controller.fallbackReason!),
                                    const SizedBox(height: 8),
                                  ],
                                  Text(controller.error ??
                                      (controller.fallbackReason == null
                                          ? 'Wallpapers change automatically. Use the status-bar icon to control Comfer.'
                                          : 'Use the controls below.')),
                                  const SizedBox(height: 16),
                                  SegmentedButton<Frequency>(
                                      segments: const [
                                        ButtonSegment(
                                            value: Frequency.hourly,
                                            label: Text('Hourly')),
                                        ButtonSegment(
                                            value: Frequency.daily,
                                            label: Text('Daily')),
                                      ],
                                      selected: {
                                        controller.scheduler.frequency
                                      },
                                      onSelectionChanged: controller
                                                  .selecting ||
                                              controller.stopping
                                          ? null
                                          : (values) =>
                                              controller.select(values.first)),
                                  const SizedBox(height: 24),
                                  Row(children: [
                                    FilledButton(
                                        onPressed: controller.busy ||
                                                controller.stopping
                                            ? null
                                            : controller.scheduler.changeNow,
                                        child: Text(controller.busy
                                            ? 'Changing…'
                                            : 'Change now')),
                                    const Spacer(),
                                    TextButton(
                                        onPressed:
                                            controller.stopping ? null : quit,
                                        child: const Text('Quit'))
                                  ]),
                                ],
                              )),
                    ))),
      );
}
