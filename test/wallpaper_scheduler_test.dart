import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comfer_wallpaper/services/wallpaper_scheduler.dart';

void main() {
  test('hourly default, manual reset, daily persistence and restart deadline',
      () {
    fakeAsync((time) {
      final epoch = DateTime.utc(2026);
      DateTime now() => epoch.add(time.elapsed);
      DateTime? success;
      var count = 0;
      String? saved;
      final scheduler = WallpaperScheduler(
          now: now,
          change: () async {
            count++;
            success = now();
          },
          lastSuccess: () => success,
          onError: (_) {},
          saveFrequency: (f) async {
            saved = f.name;
          });
      scheduler.start();
      time.flushMicrotasks();
      expect(count, 1);
      time.elapse(const Duration(minutes: 59));
      expect(count, 1);
      scheduler.changeNow();
      time.flushMicrotasks();
      expect(count, 2);
      time.elapse(const Duration(minutes: 1));
      expect(count, 2);
      time.elapse(const Duration(minutes: 59));
      expect(count, 3);
      scheduler.select(Frequency.daily);
      time.flushMicrotasks();
      expect(saved, 'daily');
      time.elapse(const Duration(hours: 23));
      expect(count, 3);
      time.elapse(const Duration(hours: 1));
      expect(count, 4);
      scheduler.stop();
      time.elapse(const Duration(days: 3));
      expect(count, 4);
      scheduler.start();
      time.flushMicrotasks();
      expect(count, 5);
      scheduler.stop();
    });
  });
  test('failed changes use backoff, do not spin, and stop cancels retry', () {
    fakeAsync((time) {
      var attempts = 0;
      final scheduler = WallpaperScheduler(
          now: () => DateTime.utc(2026).add(time.elapsed),
          change: () async {
            attempts++;
            throw StateError('offline');
          },
          lastSuccess: () => null,
          onError: (_) {},
          saveFrequency: (_) async {});
      scheduler.start();
      time.flushMicrotasks();
      expect(attempts, 1);
      time.elapse(const Duration(minutes: 1));
      expect(attempts, 2);
      time.elapse(const Duration(minutes: 4));
      expect(attempts, 2);
      time.elapse(const Duration(minutes: 1));
      expect(attempts, 3);
      scheduler.stop();
      time.elapse(const Duration(days: 2));
      expect(attempts, 3);
    });
  });
  test('failed preference write preserves selection', () async {
    final scheduler = WallpaperScheduler(
        change: () async {},
        lastSuccess: () => null,
        onError: (_) {},
        saveFrequency: (_) async => throw StateError('disk full'));
    await expectLater(scheduler.select(Frequency.daily), throwsStateError);
    expect(scheduler.frequency, Frequency.hourly);
    expect(Frequency.parse('invalid'), Frequency.hourly);
  });
}
