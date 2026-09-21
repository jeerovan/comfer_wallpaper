import 'dart:io';
import 'package:path/path.dart' as p;

/// One per-user registration, shared by upgrades and explicitly relocated copies.
class LinuxStartup {
  LinuxStartup(
      {String? configHome,
      String? executable,
      Map<String, String>? environment,
      String? resolvedExecutable})
      : configHome = configHome ?? xdg('XDG_CONFIG_HOME', '.config'),
        _appImage = executable == null
            ? appImagePath(environment ?? Platform.environment,
                resolvedExecutable ?? Platform.resolvedExecutable)
            : null,
        executable = executable ??
            appImagePath(environment ?? Platform.environment,
                resolvedExecutable ?? Platform.resolvedExecutable) ??
            resolvedExecutable ??
            Platform.resolvedExecutable;
  final String? _appImage;

  /// Only use APPIMAGE when this process actually runs inside its APPDIR.
  static String? appImagePath(
      Map<String, String> environment, String executable) {
    final image = environment['APPIMAGE'];
    final directory = environment['APPDIR'];
    if (image == null ||
        directory == null ||
        !p.isAbsolute(image) ||
        !p.isAbsolute(directory) ||
        !p.isWithin(directory, executable)) {
      return null;
    }
    return image;
  }

  final String configHome;
  final String executable;
  static const desktopId = 'com.jeerovan.comfer.desktop';
  static String xdg(String key, String fallback) {
    final value = Platform.environment[key];
    return value != null && p.isAbsolute(value)
        ? value
        : p.join(Platform.environment['HOME']!, fallback);
  }

  File get entry => File(p.join(configHome, 'autostart', desktopId));
  bool get installed =>
      p.isAbsolute(executable) &&
      !p.split(executable).contains('build') &&
      !p.isWithin(Directory.systemTemp.path, executable) &&
      (_appImage != null
          ? File(executable).existsSync()
          : Directory(p.join(p.dirname(executable), 'data')).existsSync() &&
              Directory(p.join(p.dirname(executable), 'lib')).existsSync());

  Future<bool> enabled() async {
    if (!await entry.exists()) return false;
    final text = await entry.readAsString();
    return !RegExp(
                r'^\s*(Hidden\s*=\s*true|X-GNOME-Autostart-enabled\s*=\s*false)\s*$',
                multiLine: true)
            .hasMatch(text) &&
        RegExp(r'^Exec=.+$', multiLine: true).hasMatch(text);
  }

  // Exec quoting is followed by desktop-entry string escaping (two layers).
  static String quoteExec(String value) {
    if (value.contains('\n') ||
        value.contains('\r') ||
        value.contains('\u0000')) {
      throw const FormatException('Unsupported executable path');
    }
    final quoted = value
        .replaceAllMapped(RegExp(r'[\\"`$]'), (m) => '\\${m[0]}')
        .replaceAll('%', '%%');
    return '"${quoted.replaceAll('\\', '\\\\')}"';
  }

  Future<void> enable() async {
    if (!installed) {
      throw StateError(
          'Move the complete bundle to a stable installation directory first');
    }
    await _write('[Desktop Entry]\nType=Application\nName=Comfer Wallpaper\n'
        'Exec=${quoteExec(executable)}\nTerminal=false\nHidden=false\n');
  }

  Future<void> disable() => _write('[Desktop Entry]\nType=Application\n'
      'Name=Comfer Wallpaper\nExec=${quoteExec(executable)}\nHidden=true\n');

  Future<void> _write(String text) async {
    await entry.parent.create(recursive: true);
    final staging = await entry.parent.createTemp('.comfer-startup-');
    try {
      final temporary = File(p.join(staging.path, desktopId));
      await temporary.writeAsString(text, flush: true);
      await temporary.rename(entry.path);
    } finally {
      await staging.delete(recursive: true);
    }
  }
}
