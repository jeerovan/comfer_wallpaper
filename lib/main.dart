import 'dart:io';
import 'package:comfer_wallpaper/downloader.dart';
import 'package:comfer_wallpaper/service_logger.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  // Ensure Flutter bindings are initialized before using plugins.
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();

  WindowOptions windowOptions = WindowOptions(
    size: Size(480, 512),
    minimumSize: Size(480, 512),
    center: true,
    title: "Comfer Wallpaper",
    //backgroundColor: Colors.transparent,
    //skipTaskbar: false,
    //titleBarStyle: TitleBarStyle.hidden,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  //windowManager.setPreventClose(true); // Prevents closing the app completely
  // Start downloader timer
  Downloader().startTimer();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Comfer Wallpaper',
      theme: ThemeData(
        primarySwatch: Colors.red,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blueAccent,
            foregroundColor: Colors.white,
          ),
        ),
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WindowListener, TrayListener {
  final AppLogger logger = AppLogger(prefixes: ["Home"]);
  bool _hideOnClose = false;

  @override
  void initState() {
    super.initState();
    _loadHideOnClose();
    _initTray();
    windowManager.addListener(this);
  }

  @override
  void onWindowClose() async {
    windowManager.hide();
  }

  @override
  void onTrayIconMouseDown() {
    _showWindow();
  }

  Future<void> _loadHideOnClose() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      // Get the saved value, or default to 'Hourly' if nothing is stored.
      _hideOnClose = prefs.getBool('hide_on_close') ?? false;
    });
    windowManager.setPreventClose(_hideOnClose);
  }

  Future<void> _saveHideOnClose(bool? newValue) async {
    if (newValue == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hide_on_close', newValue);
    setState(() {
      _hideOnClose = newValue;
      windowManager.setPreventClose(newValue);
    });
  }

  Future<void> _initTray() async {
    trayManager.addListener(this);
    await trayManager.setIcon(
      Platform.isWindows
          ? 'assets/comfer_launcher.ico'
          : 'assets/comfer_launcher.png',
    ); // Set tray icon
    if (!Platform.isLinux) {
      await trayManager.setToolTip("Comfer Wallpaper"); // Tooltip
    }
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(
              label: "Change Now", onClick: (menuItem) => _changeWallpaper()),
          MenuItem(label: "Show App", onClick: (menuItem) => _showWindow()),
          MenuItem(label: "Quit", onClick: (menuItem) => _exitApp()),
        ],
      ),
    );
  }

  void _changeWallpaper() {
    Downloader().runWallpaperScript();
  }

  void _showWindow() {
    windowManager.show(); // Restore window
    windowManager.focus();
  }

  void _exitApp() {
    trayManager.destroy();
    windowManager.destroy();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  // Function to launch the website URL.
  void _launchURL() async {
    final Uri url = Uri.parse('https://comfer.jeerovan.com');
    if (!await launchUrl(url)) {
      // You can show a snackbar or dialog if the URL fails to launch
      logger.error('Could not launch $url');
    }
  }

  @override
  void dispose() {
    Downloader().stopTimer();
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              // Use a Spacer to push content to the center, leaving top space.
              const Spacer(),

              // Icon at the top
              Image.asset(
                'assets/comfer_launcher.png',
                width: 64.0,
                height: 64.0,
              ),
              const SizedBox(height: 16.0),

              // App Name
              const Text(
                'Comfer Wallpaper',
                style: TextStyle(
                  fontSize: 24.0,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 48.0),
              Center(
                child: ListTile(
                  leading: const Icon(Icons.close, color: Colors.grey),
                  title: const Text("Hide on close"),
                  subtitle: const Text("If you see icon in system tray"),
                  trailing: Transform.scale(
                    scale: 0.7,
                    child: Switch(
                        value: _hideOnClose, onChanged: _saveHideOnClose),
                  ),
                  horizontalTitleGap: 16.0,
                ),
              ),
              const SizedBox(height: 32.0),

              // "Change now" button
              ElevatedButton(
                onPressed: () {
                  Downloader().runWallpaperScript();
                },
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                  textStyle: const TextStyle(fontSize: 16),
                ),
                child: const Text('Change Now'),
              ),

              // Use a Spacer to push the footer to the bottom.
              const Spacer(),

              // "Powered by" footer link
              InkWell(
                onTap: _launchURL,
                borderRadius: BorderRadius.circular(8.0),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.flash_on, size: 16.0, color: Colors.amber),
                      SizedBox(width: 8.0),
                      Text(
                        'Powered by Comfer Launcher',
                        style: TextStyle(
                          fontSize: 12.0,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
