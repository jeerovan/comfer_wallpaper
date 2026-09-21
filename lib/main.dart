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
import 'services/tray_service.dart';
import 'services/wallpaper_scheduler.dart';
import 'services/wallpaper_service.dart';
import 'services/wallpaper_store.dart';

Future<void> main(List<String> arguments) async {
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
  var userId = prefs.getString('user_id');
  if (userId == null || userId.isEmpty) {
    userId = const Uuid().v4();
    if (!await prefs.setString('user_id', userId)) {
      throw StateError('Cannot save identity');
    }
  }
  final controller = AppController(
      WallpaperService(
          store: WallpaperStore(Directory(p.join(support.path, 'wallpapers'))),
          platform: DesktopPlatform(),
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
    await windowManager.show();
    await windowManager.focus();
  }

  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen((_) => unawaited(quit()));
    ProcessSignal.sigint.watch().listen((_) => unawaited(quit()));
  }

  final lifecycle = DesktopLifecycle(controller, quit);
  windowManager.addListener(lifecycle);
  WidgetsBinding.instance.addObserver(lifecycle);
  runApp(ComferApp(controller: controller, quit: quit));
  await windowManager.waitUntilReadyToShow(const WindowOptions(
      size: Size(440, 340),
      minimumSize: Size(400, 320),
      center: true,
      skipTaskbar: true,
      title: 'Comfer Wallpaper'));
  await windowManager.setPreventClose(true);
  await windowManager.hide();
  try {
    tray = TrayService(controller, quit, show);
    await tray.initialize();
  } catch (_) {
    controller.error =
        'The tray icon is unavailable. Keep this window open to control Comfer.';
    lifecycle.hasTray = false;
    await show();
  }
  // GTK may create an indicator without a shell displaying it. Keep a fallback.
  if (Platform.isLinux || arguments.contains('--show')) {
    lifecycle.hasTray = !Platform.isLinux;
    await show();
  }
  await controller.start();
  if (arguments.contains('--change-now')) {
    await controller.scheduler.changeNow();
  }
}

class DesktopLifecycle with WindowListener, WidgetsBindingObserver {
  DesktopLifecycle(this.controller, this.quit);
  final AppController controller;
  final Future<void> Function() quit;
  bool hasTray = true;
  @override
  void onWindowClose() {
    if (hasTray) {
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
  const ComferApp({super.key, required this.controller, required this.quit});
  final AppController controller;
  final Future<void> Function() quit;
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Comfer Wallpaper',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
            colorSchemeSeed: const Color(0xff486b58), useMaterial3: true),
        home: Scaffold(
            body: SafeArea(
                child: Padding(
          padding: const EdgeInsets.all(24),
          child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Comfer Wallpaper',
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 12),
                      Text(controller.error ??
                          'Wallpapers change automatically. Use the status-bar icon to control Comfer.'),
                      const SizedBox(height: 16),
                      SegmentedButton<Frequency>(
                          segments: const [
                            ButtonSegment(
                                value: Frequency.hourly, label: Text('Hourly')),
                            ButtonSegment(
                                value: Frequency.daily, label: Text('Daily')),
                          ],
                          selected: {
                            controller.scheduler.frequency
                          },
                          onSelectionChanged: controller.selecting ||
                                  controller.stopping
                              ? null
                              : (values) => controller.select(values.first)),
                      const Spacer(),
                      Row(children: [
                        FilledButton(
                            onPressed: controller.busy || controller.stopping
                                ? null
                                : controller.scheduler.changeNow,
                            child: Text(
                                controller.busy ? 'Changing…' : 'Change now')),
                        const Spacer(),
                        TextButton(
                            onPressed: controller.stopping ? null : quit,
                            child: const Text('Quit'))
                      ]),
                    ],
                  )),
        ))),
      );
}
