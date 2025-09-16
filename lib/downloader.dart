import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:comfer_wallpaper/service_logger.dart';

class Downloader {
  // Singleton setup
  static final Downloader _instance = Downloader._internal();
  factory Downloader() => _instance;
  Downloader._internal();

  Timer? _downloadTimer;
  static final logger = AppLogger(prefixes: [
    "downloader",
  ]);

  void startTimer() {
    // Starts the interval sync
    _downloadTimer?.cancel();
    _downloadTimer = Timer.periodic(Duration(hours: 1), (timer) {
      runWallpaperScript();
    });
  }

  void stopTimer() {
    _downloadTimer?.cancel();
    _downloadTimer = null;
  }

  Future<void> runWallpaperScript() async {
    try {
      // Get the path to the executable script
      final scriptPath = await getScriptPath();

      String command;
      List<String> args;

      if (Platform.isWindows) {
        command = 'powershell.exe';
        args = ['-File', scriptPath];
      } else if (Platform.isMacOS) {
        command = 'zsh';
        args = [scriptPath];
      } else if (Platform.isLinux) {
        command = 'bash';
        args = [scriptPath];
      } else {
        return; // Unsupported platform
      }

      // Execute the process
      final result = await Process.run(command, args);

      if (result.exitCode == 0) {
        logger.info('Script executed successfully from: $scriptPath');
        logger.debug(result.stdout);
      } else {
        logger.error('Script failed with exit code: ${result.exitCode}');
        logger.error(result.stderr);
      }
    } catch (e, s) {
      logger.error('An error occurred while running the script',
          error: e, stackTrace: s);
    }
  }

  Future<String> getScriptPath() async {
    String scriptAssetPath;
    String scriptFileName;

    if (Platform.isWindows) {
      scriptAssetPath = 'assets/script.ps1';
      scriptFileName = 'script.ps1';
    } else if (Platform.isMacOS) {
      scriptAssetPath = 'assets/script.zsh';
      scriptFileName = 'script.zsh';
    } else if (Platform.isLinux) {
      scriptAssetPath = 'assets/script.sh';
      scriptFileName = 'script.sh';
    } else {
      throw Exception('Unsupported platform');
    }

    // Get a temporary directory
    final tempDir = await getTemporaryDirectory();
    final scriptFile = File(path.join(tempDir.path, scriptFileName));

    // Load the script from assets
    final byteData = await rootBundle.load(scriptAssetPath);

    // Write the script to the temporary file
    await scriptFile.writeAsBytes(byteData.buffer.asUint8List(), flush: true);

    // On macOS and Linux, make the script executable
    if (Platform.isMacOS || Platform.isLinux) {
      await Process.run('chmod', ['+x', scriptFile.path]);
    }
    return scriptFile.path;
  }
}
