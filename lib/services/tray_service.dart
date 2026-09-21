import 'dart:async';
import 'dart:io';
import 'package:tray_manager/tray_manager.dart';
import '../app_controller.dart';
import 'wallpaper_scheduler.dart';

class TrayService with TrayListener {
  TrayService(this.controller, this.quit, this.showFallback);
  final AppController controller;
  final Future<void> Function() quit;
  final Future<void> Function() showFallback;
  Future<void> _updates = Future.value();
  bool _closed = false;
  Future<void> initialize() async {
    trayManager.addListener(this);
    await trayManager.setIcon(Platform.isWindows
        ? 'assets/comfer_launcher.ico'
        : 'assets/comfer_launcher.png');
    await _render();
    controller.addListener(_refresh);
  }

  void _refresh() {
    _updates = _updates.then((_) async {
      if (!_closed) await _render();
    }).catchError((Object _) async {
      if (!_closed) await showFallback();
    });
  }

  Future<void> _render() async {
    if (!Platform.isLinux) {
      await trayManager.setToolTip(controller.error ??
          'Comfer Wallpaper — ${controller.scheduler.frequency.name}');
    }
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(
          label: controller.busy ? 'Changing…' : 'Change now',
          disabled: controller.busy || controller.stopping,
          onClick: (_) => unawaited(controller.scheduler.changeNow())),
      MenuItem.submenu(
          label: 'Frequency',
          disabled: controller.selecting || controller.stopping,
          submenu: Menu(items: [
            for (final frequency in Frequency.values)
              MenuItem.checkbox(
                  label: frequency == Frequency.hourly ? 'Hourly' : 'Daily',
                  checked: controller.scheduler.frequency == frequency,
                  onClick: (_) => unawaited(controller.select(frequency))),
          ])),
      if (controller.error != null)
        MenuItem(
            label: 'Last change needs attention…',
            onClick: (_) => unawaited(showFallback())),
      MenuItem.separator(),
      MenuItem(
          label: 'Quit',
          disabled: controller.stopping,
          onClick: (_) => unawaited(quit())),
    ]));
  }

  @override
  void onTrayIconMouseDown() => trayManager.popUpContextMenu();
  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();
  Future<void> close() async {
    _closed = true;
    controller.removeListener(_refresh);
    trayManager.removeListener(this);
    await _updates;
    await trayManager.destroy();
  }
}
