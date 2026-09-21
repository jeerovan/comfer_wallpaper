import 'dart:async';

enum Frequency {
  hourly(Duration(hours: 1)),
  daily(Duration(days: 1));

  const Frequency(this.interval);
  final Duration interval;
  static Frequency parse(String? value) => value == 'daily' ? daily : hourly;
}

/// The timer is only a wake-up hint. Persisted successful time is authoritative.
class WallpaperScheduler {
  WallpaperScheduler(
      {required this.change,
      required this.lastSuccess,
      required this.onError,
      required this.saveFrequency,
      this.frequency = Frequency.hourly,
      DateTime Function()? now})
      : now = now ?? DateTime.now;
  final Future<void> Function() change;
  final DateTime? Function() lastSuccess;
  final void Function(Object) onError;
  final Future<void> Function(Frequency) saveFrequency;
  final DateTime Function() now;
  Frequency frequency;
  Timer? _timer;
  bool _running = false;
  bool _busy = false;
  int _failures = 0;
  DateTime? _retryAt;
  Future<void>? _selection;

  DateTime get nextDue =>
      _retryAt ?? lastSuccess()?.add(frequency.interval) ?? now();

  void start() {
    _running = true;
    reconcile();
  }

  void stop() {
    _running = false;
    _timer?.cancel();
  }

  Future<void> select(Frequency value) {
    return _selection ??= _select(value).whenComplete(() => _selection = null);
  }

  Future<void> _select(Frequency value) async {
    await saveFrequency(value);
    frequency = value;
    _retryAt = null;
    _failures = 0;
    reconcile();
  }

  void reconcile() {
    _timer?.cancel();
    if (!_running || _busy) return;
    final remaining = nextDue.difference(now());
    if (remaining <= Duration.zero) {
      unawaited(changeNow());
    } else {
      // Also reconciles after sleep and wall-clock changes without catch-up bursts.
      _timer = Timer(
          remaining < const Duration(minutes: 1)
              ? remaining
              : const Duration(minutes: 1),
          reconcile);
    }
  }

  Future<void> changeNow() async {
    if (_busy || !_running) return;
    _busy = true;
    _timer?.cancel();
    try {
      await change();
      _retryAt = null;
      _failures = 0;
    } catch (error) {
      const delays = [1, 5, 15, 60];
      final delay = Duration(minutes: delays[_failures.clamp(0, 3)]);
      _failures++;
      _retryAt = now().add(delay);
      onError(error);
    } finally {
      _busy = false;
      reconcile();
    }
  }
}
