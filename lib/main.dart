import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';

void main() async {
  // Ensure Flutter bindings are initialized before using plugins.
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();

  WindowOptions windowOptions = WindowOptions(
    size: Size(480, 512),
    minimumSize: Size(480, 512),
    center: true,
    //backgroundColor: Colors.transparent,
    //skipTaskbar: false,
    //titleBarStyle: TitleBarStyle.hidden,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

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
  String _selectedInterval = 'Hourly'; // Default value

  @override
  void initState() {
    super.initState();
    _loadInterval();
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
          MenuItem(label: "Show App", onClick: (menuItem) => _showWindow()),
          MenuItem(label: "Quit", onClick: (menuItem) => _exitApp()),
        ],
      ),
    );
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

  // Load the saved interval from local storage.
  Future<void> _loadInterval() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      // Get the saved value, or default to 'Hourly' if nothing is stored.
      _selectedInterval = prefs.getString('wallpaper_interval') ?? 'Hourly';
    });
  }

  // Save the selected interval to local storage.
  Future<void> _saveInterval(String? newValue) async {
    if (newValue == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('wallpaper_interval', newValue);
    setState(() {
      _selectedInterval = newValue;
    });
  }

  // Function to launch the website URL.
  void _launchURL() async {
    final Uri url = Uri.parse('https://comfer.jeerovan.com');
    if (!await launchUrl(url)) {
      // You can show a snackbar or dialog if the URL fails to launch
      print('Could not launch $url');
    }
  }

  @override
  void dispose() {
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

              // Interval selection dropdown
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Interval:', style: TextStyle(fontSize: 16.0)),
                  const SizedBox(width: 20),
                  DropdownButton<String>(
                    value: _selectedInterval,
                    onChanged: _saveInterval,
                    items: <String>['Hourly', 'Daily']
                        .map<DropdownMenuItem<String>>((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                  ),
                ],
              ),
              const SizedBox(height: 32.0),

              // "Change now" button
              ElevatedButton(
                onPressed: () async {
                  print('Change Now button pressed!');
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
