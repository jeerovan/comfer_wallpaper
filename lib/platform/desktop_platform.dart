import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import '../services/wallpaper_service.dart';

class DesktopPlatform implements WallpaperPlatform {
  static const channel = MethodChannel('comfer.jeerovan.com/wallpaper');
  Future<ProcessResult> _run(List<String> arguments) async {
    final process = await Process.start('gsettings', arguments);
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.transform(utf8.decoder).join();
    final code = await process.exitCode.timeout(const Duration(seconds: 15),
        onTimeout: () {
      process.kill();
      throw const ProcessException(
          'gsettings', [], 'Desktop command timed out');
    });
    final result = ProcessResult(process.pid, code, await output, await errors);
    if (code != 0) {
      throw ProcessException(
          'gsettings', arguments, 'Desktop command failed', code);
    }
    return result;
  }

  void _requireGnome() {
    final desktop =
        (Platform.environment['XDG_CURRENT_DESKTOP'] ?? '').toLowerCase();
    if (!desktop.contains('gnome') && !desktop.contains('unity')) {
      throw UnsupportedError(
          'This Linux build supports GNOME. Your desktop needs a verified wallpaper adapter.');
    }
  }

  @override
  Future<Set<String>> currentPaths() async {
    if (Platform.isLinux) {
      _requireGnome();
      final paths = <String>{};
      for (final key in ['picture-uri', 'picture-uri-dark']) {
        final result = await _run(['get', 'org.gnome.desktop.background', key]);
        var value = (result.stdout as String).trim();
        if (value.startsWith("'") && value.endsWith("'")) {
          value = value.substring(1, value.length - 1);
        }
        final uri = Uri.tryParse(value);
        if (uri?.scheme == 'file') paths.add(uri!.toFilePath());
      }
      return paths;
    }
    return (await channel.invokeListMethod<String>('getWallpaperPaths') ?? [])
        .toSet();
  }

  @override
  Future<void> apply(String path) async {
    if (Platform.isLinux) {
      _requireGnome();
      for (final key in ['picture-uri', 'picture-uri-dark']) {
        await _run([
          'set',
          'org.gnome.desktop.background',
          key,
          File(path).uri.toString()
        ]);
      }
      return;
    }
    if (await channel.invokeMethod<bool>('setWallpaper', {'path': path}) !=
        true) {
      throw StateError('The desktop refused the wallpaper');
    }
  }
}
