import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginStartupInfo {
  const LoginStartupInfo({required this.status, required this.installed});
  final int status;
  final bool installed;
  bool get enabled => status == 1;
  bool get needsApproval => status == 2;
}

class LoginStartup {
  LoginStartup(this.preferences);
  final SharedPreferences preferences;
  static const completionKey = 'login_setup_completed';
  static const channel = MethodChannel('comfer.jeerovan.com/wallpaper');

  Future<LoginStartupInfo> info() async {
    final value =
        await channel.invokeMapMethod<String, dynamic>('getLoginStartup');
    if (value == null) throw StateError('Startup status unavailable');
    return LoginStartupInfo(
        status: value['status'] as int, installed: value['installed'] as bool);
  }

  Future<bool> needsSetup() async {
    // A previous decision is authoritative, even if startup was later disabled
    // in System Settings. Never silently re-register during a normal launch.
    if (preferences.getBool(completionKey) == true) return false;
    try {
      if ((await info()).enabled) {
        await complete();
        return false;
      }
    } catch (_) {/* Show a retryable setup screen if status cannot be read. */}
    return true;
  }

  Future<void> enable() => channel.invokeMethod<void>('enableLoginStartup');
  Future<void> openSettings() =>
      channel.invokeMethod<void>('openLoginSettings');

  Future<void> complete() async {
    if (!await preferences.setBool(completionKey, true)) {
      throw StateError('Could not save setup preference');
    }
  }
}
