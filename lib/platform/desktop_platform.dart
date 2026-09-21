import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import '../services/wallpaper_service.dart';

class DesktopPlatform implements WallpaperPlatform, WallpaperConfirmation {
  DesktopPlatform({Future<ProcessResult> Function(List<String>)? run})
      : _command = run;
  final Future<ProcessResult> Function(List<String>)? _command;
  static const channel = MethodChannel('comfer.jeerovan.com/wallpaper');
  Future<ProcessResult> _run(List<String> arguments) async {
    if (_command != null) return _command(arguments);
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

  static bool supportsLinuxDesktop(String desktop) => desktop
      .toLowerCase()
      .split(':')
      .any((name) => name == 'gnome' || name == 'unity');

  bool get supported =>
      !Platform.isLinux ||
      supportsLinuxDesktop(Platform.environment['XDG_CURRENT_DESKTOP'] ?? '');

  void _requireGnome() {
    if (!supported) {
      throw UnsupportedError(
          'This Linux build supports GNOME. Your desktop needs a verified wallpaper adapter.');
    }
  }

  @override
  bool confirms(Set<String> paths, String candidate) => Platform.isWindows
      ? paths.isNotEmpty && paths.first == candidate
      : paths.contains(candidate) && (!Platform.isLinux || paths.length == 1);

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
      final previous = <String, String>{};
      for (final key in ['picture-uri', 'picture-uri-dark']) {
        previous[key] =
            (await _run(['get', 'org.gnome.desktop.background', key]))
                .stdout
                .toString()
                .trim();
        final writable =
            await _run(['writable', 'org.gnome.desktop.background', key]);
        if (writable.stdout.toString().trim() == 'false') {
          throw StateError('GNOME wallpaper settings are locked');
        }
      }
      try {
        for (final key in previous.keys) {
          await _run([
            'set',
            'org.gnome.desktop.background',
            key,
            File(path).uri.toString()
          ]);
        }
        final paths = await currentPaths();
        if (paths.length != 1 || !paths.contains(path)) {
          throw StateError('GNOME did not confirm both wallpaper settings');
        }
      } catch (_) {
        // Preserve each original value, including distinct light/dark images.
        // The journal retains both files if the session also refuses rollback.
        for (final entry in previous.entries) {
          try {
            await _run([
              'set',
              'org.gnome.desktop.background',
              entry.key,
              entry.value
            ]);
          } catch (_) {/* Recovery retries the journal on the next attempt. */}
        }
        rethrow;
      }
      return;
    }
    if (await channel.invokeMethod<bool>('setWallpaper', {'path': path}) !=
        true) {
      throw StateError('The desktop refused the wallpaper');
    }
  }
}
