import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/settings_service.dart';
import '../utils/theme.dart';
import '../widgets/brand.dart';

// Wraps the app and enforces the biometric / PIN lock when it is enabled.
// Re-locks automatically when the app is sent to the background.
//
// It sits above the Navigator (MaterialApp.builder), so the lock and the
// app-switcher cover hide every open page, not only the home screen, and a
// page opened from a notification waits behind the lock. The app stays
// mounted underneath, so unlocking returns to exactly where the user was.
class AuthGate extends StatefulWidget {
  final Widget child;
  const AuthGate({super.key, required this.child});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  bool _unlocked = false;
  bool _authenticating = false;
  bool _bioAvailable = true;
  // the app switcher shows a snapshot of the app: covered while not in front
  bool _covered = false;
  DateTime? _leftAt;
  // a quick switch (copying a code from a text) does not lock
  static const _grace = Duration(seconds: 60);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _evaluateLock();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // the auth dialog itself briefly takes the app out of front: ignore that
    if (_authenticating) return;
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _leftAt ??= DateTime.now();
        if (Settings.appLockEnabled && !_covered) setState(() => _covered = true);
      case AppLifecycleState.resumed:
        final away = _leftAt == null ? Duration.zero : DateTime.now().difference(_leftAt!);
        _leftAt = null;
        setState(() {
          _covered = false;
          if (Settings.appLockEnabled && away > _grace) _unlocked = false;
        });
        if (!_unlocked) _authenticate();
      case AppLifecycleState.detached:
        break;
    }
  }

  // decide whether a lock is needed, and prompt if so
  Future<void> _evaluateLock() async {
    if (!Settings.appLockEnabled) {
      setState(() => _unlocked = true);
      return;
    }
    // fail closed: show the lock screen; user can retry or explicitly continue
    final available = await AuthService.isAvailable();
    if (!available) {
      if (mounted) setState(() {
        _bioAvailable = false;
        _unlocked = false;
      });
      return;
    }
    if (mounted) setState(() => _bioAvailable = true);
    _authenticate();
  }

  Future<void> _authenticate() async {
    if (_authenticating) return;
    setState(() => _authenticating = true);
    final ok = await AuthService.authenticate('BudgetBuddy entsperren');
    if (mounted) {
      setState(() {
        _unlocked = ok;
        _authenticating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = !_unlocked;
    // the app fills the whole window, exactly as without the gate
    return Stack(fit: StackFit.expand, children: [
      // nothing underneath is readable or tappable while locked or covered
      ExcludeSemantics(
        excluding: locked || _covered,
        child: TickerMode(enabled: !locked, child: widget.child),
      ),
      if (locked)
        Positioned.fill(child: _lockScreen())
      else if (_covered)
        // privacy cover for the app switcher: the logo instead of the balance
        Positioned.fill(
          child: ColoredBox(
            color: AppColors.bg,
            child: const Center(child: BrandMark(size: 72)),
          ),
        ),
    ]);
  }

  // shown until the user unlocks; the app keeps its place underneath
  Widget _lockScreen() => Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const BrandMark(size: 72),
                const SizedBox(height: 24),
                const Text('BudgetBuddy ist gesperrt',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                    _bioAvailable
                        ? 'Entsperr die App mit Face ID, Fingerabdruck oder deinem Code.'
                        : 'Dieses Gerät kann gerade nicht biometrisch entsperren. '
                            'Tippe auf Entsperren zum erneuten Versuch oder fahre '
                            'ohne Sperre fort (Sperre bleibt in den Einstellungen an).',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textDim, height: 1.35)),
                const SizedBox(height: 32),
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(200, 50)),
                  onPressed: _authenticating
                      ? null
                      : () async {
                          if (_bioAvailable) {
                            _authenticate();
                            return;
                          }
                          if (await AuthService.isAvailable()) {
                            if (mounted) setState(() => _bioAvailable = true);
                            _authenticate();
                            return;
                          }
                          if (mounted) setState(() => _unlocked = true);
                        },
                  icon: const Icon(Icons.lock_open_rounded),
                  label: Text(_bioAvailable ? 'Entsperren' : 'Erneut versuchen'),
                ),
                if (!_bioAvailable) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => setState(() => _unlocked = true),
                    child: const Text('Ohne Biometrie fortfahren'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}
