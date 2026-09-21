import 'package:flutter/material.dart';
import 'platform/login_startup.dart';

class StartupSetup extends StatefulWidget {
  const StartupSetup(
      {super.key,
      required this.startup,
      required this.onDone,
      required this.onQuit});
  final LoginStartup startup;
  final Future<void> Function() onDone;
  final Future<void> Function() onQuit;

  @override
  State<StartupSetup> createState() => _StartupSetupState();
}

class _StartupSetupState extends State<StartupSetup>
    with WidgetsBindingObserver {
  LoginStartupInfo? _info;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _perform(_refresh);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _info?.needsApproval == true) {
      _perform(_refresh);
    }
  }

  Future<void> _refresh() async {
    final info = await widget.startup.info();
    if (!mounted) return;
    setState(() => _info = info);
    if (info.enabled) await _finish();
  }

  Future<void> _finish() async {
    await widget.startup.complete();
    if (mounted) await widget.onDone();
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Could not update login startup. Try again, or continue without it.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final installed = _info?.installed ?? true;
    final approval = _info?.needsApproval ?? false;
    return FocusTraversalGroup(
        child: ListView(padding: const EdgeInsets.all(24), children: [
      Text('Welcome to Comfer',
          style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 12),
      Text(!installed
          ? 'Drag Comfer Wallpaper into Applications, then open that copy to finish setup.'
          : approval
              ? 'macOS needs your approval. Enable Comfer in Login Items to start it automatically when you sign in.'
              : 'Start Comfer when you sign in so your wallpaper keeps changing automatically. You can change this later in System Settings → General → Login Items.'),
      const SizedBox(height: 12),
      const Text(
          'Comfer lives in your menu bar. Use its icon to change the wallpaper, choose Hourly or Daily, or quit.'),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Semantics(
            liveRegion: true,
            child: Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ],
      const SizedBox(height: 20),
      if (!installed)
        FilledButton(
            onPressed: _busy ? null : widget.onQuit,
            child: const Text('Quit and install'))
      else ...[
        FilledButton(
            onPressed: _busy
                ? null
                : () => _perform(() async {
                      if (_info == null || _info!.enabled) {
                        await _refresh();
                      } else if (approval) {
                        await widget.startup.openSettings();
                      } else {
                        await widget.startup.enable();
                        await _refresh();
                        if (_info?.enabled != true &&
                            _info?.needsApproval != true) {
                          throw StateError('Startup was not registered');
                        }
                      }
                    }),
            child: Text(_busy
                ? 'Please wait…'
                : _info == null
                    ? 'Try again'
                    : approval
                        ? 'Open System Settings'
                        : _info!.enabled
                            ? 'Continue'
                            : 'Start at login')),
        if (approval)
          TextButton(
              onPressed: _busy ? null : () => _perform(_refresh),
              child: const Text('Check again')),
        TextButton(
            onPressed: _busy ? null : () => _perform(_finish),
            child: const Text('Not now')),
      ],
    ]));
  }
}
