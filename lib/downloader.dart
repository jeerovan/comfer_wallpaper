import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle, MethodChannel, PlatformException;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:comfer_wallpaper/service_logger.dart';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class Downloader {
  // Singleton setup
  static final Downloader _instance = Downloader._internal();
  factory Downloader() => _instance;
  Downloader._internal();
  final platform = MethodChannel('comfer.jeerovan.com/wallpaper');

  Timer? _downloadTimer;
  bool settingWallpaper = false;
  static final logger = AppLogger(prefixes: [
    "downloader",
  ]);

  void startTimer() {
    //oneshot on start
    downloadAndSetWallpaper();
    // Starts the interval sync
    _downloadTimer?.cancel();
    _downloadTimer = Timer.periodic(Duration(hours: 1), (timer) {
      downloadAndSetWallpaper();
    });
  }

  void stopTimer() {
    _downloadTimer?.cancel();
    _downloadTimer = null;
  }

  Future<void> downloadAndSetWallpaper() async {
    await downloadWallpaperFromApi();
    if(Platform.isLinux || Platform.isWindows){
      runWallpaperScript();
    }
  }

  Future<void> downloadWallpaperFromApi() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString("user_id");
    if (userId == null || userId.isEmpty) {
      logger.error("user_id not found in preferences.");
      return;
    }

    // Get downloads directory
    Directory? downloadsDir = await getDownloadsDirectory();
    if (downloadsDir == null) {
      logger.error(" Could not get downloads directory.");
      return;
    }

    // Construct API URL
    final now = DateTime.now().toUtc();
    final hour = now.hour.toString().padLeft(2, '0');
    final apiUrl =
        "https://comfer.jeerovan.com/api?view=landscape&name=$userId&hour=$hour";

    try {
      final response = await http.get(Uri.parse(apiUrl));
      if (response.statusCode != 200) {
        logger.error("API request failed with code: ${response.statusCode}");
        return;
      }

      final jsonResponse = json.decode(response.body);
      final imageUrl = jsonResponse['imageUrl'];
      if (imageUrl == null || imageUrl == 'null' || imageUrl.isEmpty) {
        logger.error("Failed to fetch imageUrl from API response.");
        return;
      }

      final utcSeconds = now.millisecondsSinceEpoch ~/ 1000;
      final imageName = "$utcSeconds.jpg";
      final imagePath = downloadsDir.path + Platform.pathSeparator + imageName;

      // Download wallpaper image
      final imageResponse = await http.get(Uri.parse(imageUrl));
      if (imageResponse.statusCode != 200 || imageResponse.bodyBytes.isEmpty) {
        logger.error("Failed to download image: $imageUrl");
        return;
      }

      // Save wallpaper to file
      final imageFile = File(imagePath);
      await imageFile.writeAsBytes(imageResponse.bodyBytes, flush: true);

      if(Platform.isMacOS){
        setWallpaperMacOS(imagePath);
      } else {
        // Update wallpaper_file_name.txt
        final txtFilePath =
            '${downloadsDir.path}${Platform.pathSeparator}wallpaper_file_name.txt';
        final txtFile = File(txtFilePath);
        await txtFile.writeAsString(imageName, flush: true);
      }
    } catch (e,s) {
      logger.error("Error occurred",error: e,stackTrace: s);
    }
  }

  Future<bool> setWallpaperMacOS(String imagePath) async {
    try {
      final bool result = await platform.invokeMethod('setWallpaper', {'path': imagePath});
      return result;
    } on PlatformException catch (e) {
      logger.error("Failed to set wallpaper: '${e.message}'.");
      return false;
    }
  }

  Future<void> runWallpaperScript() async {
    try {
      // Get the path to the executable script
      final scriptPath = await getScriptPath();

      String command;
      List<String> args;

      if (Platform.isWindows) {
        command = 'powershell.exe';
        args = ['-ExecutionPolicy', 'Bypass', '-File', scriptPath];
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
      scriptAssetPath = 'assets/windows.ps1';
      scriptFileName = 'windows.ps1';
    } else if (Platform.isMacOS) {
      scriptAssetPath = 'assets/osx.sh';
      scriptFileName = 'osx.sh';
    } else if (Platform.isLinux) {
      scriptAssetPath = 'assets/debian.sh';
      scriptFileName = 'debian.sh';
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
