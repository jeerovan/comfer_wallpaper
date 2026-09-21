import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/wallpaper_scheduler.dart';
import 'services/wallpaper_service.dart';

class AppController extends ChangeNotifier {
  AppController(this.service, this.preferences) {
    scheduler = WallpaperScheduler(
      frequency: Frequency.parse(preferences.getString('frequency')),
      lastSuccess: () => service.store.lastSuccess,
      change: _change,
      onError: report,
      saveFrequency: (value) async {
        if (!await preferences.setString('frequency', value.name)) {
          throw StateError('Could not save frequency');
        }
      },
    );
  }
  final WallpaperService service;
  final SharedPreferences preferences;
  late final WallpaperScheduler scheduler;
  bool busy = false;
  bool stopping = false;
  bool selecting = false;
  String? error;
  void Function(String)? log;
  Future<void> start() async {
    try {
      await service.initialize();
    } catch (e) {
      report(e);
    }
    scheduler.start();
  }

  Future<void> _change() async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await service.change();
      error = service.cleanupWarning;
      log?.call(error ?? 'Wallpaper applied successfully');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void report(Object value) {
    error = value is UnsupportedError
        ? value.message
        : 'Could not change wallpaper. Check your connection or desktop settings; Comfer will retry.';
    log?.call(
        'Wallpaper operation failed: ${value is StateError ? value.message : value.runtimeType}');
    notifyListeners();
  }

  Future<void> select(Frequency value) async {
    if (selecting || stopping) return;
    selecting = true;
    notifyListeners();
    try {
      await scheduler.select(value);
    } catch (_) {
      error = 'Could not save frequency. Your previous selection is unchanged.';
    } finally {
      selecting = false;
      notifyListeners();
    }
  }

  Future<void> close() async {
    stopping = true;
    scheduler.stop();
    notifyListeners();
    await service.close();
  }
}
