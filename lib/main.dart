import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'screens/home_screen.dart';
import 'screens/auth_gate.dart';
import 'screens/onboarding_screen.dart';
import 'services/recurring_service.dart';
import 'services/settings_service.dart';
import 'utils/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // initialize hive database
  await Hive.initFlutter();
  
  // open all hive boxes
  await Hive.openBox('transactions');
  await Hive.openBox('budgets');
  await Hive.openBox('badges');
  await Hive.openBox('holdings');
  await Hive.openBox('recurring');
  await Hive.openBox('settings');

  // generate any recurring transactions that came due while the app was closed
  await RecurringService.process();

  // apply the saved theme mode
  ThemeController.isDark.value = Settings.darkMode;

  // start the app
  runApp(const BudgetBuddyApp());
}

class BudgetBuddyApp extends StatelessWidget {
  const BudgetBuddyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // rebuild the whole app when the theme mode is toggled
    return ValueListenableBuilder<bool>(
      valueListenable: ThemeController.isDark,
      builder: (_, dark, __) => MaterialApp(
        title: 'BudgetBuddy',
        debugShowCheckedModeBanner: false,  // hide debug banner
        theme: AppTheme.theme(dark),        // reactive light/dark theme
        home: const RootGate(),             // onboarding -> lock -> app
        // on wide screens (desktop browser, Mac) keep a phone-width column
        // in the middle instead of stretching every screen edge to edge
        builder: (context, child) => ColoredBox(
          color: dark ? const Color(0xFF05070A) : const Color(0xFFE6EAF0),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

// Decides what to show first: onboarding on the very first launch, then the
// lock gate wrapping the app.
class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  bool _onboarded = Settings.onboardingDone;

  @override
  Widget build(BuildContext context) {
    if (!_onboarded) {
      return OnboardingScreen(onFinish: () async {
        await Settings.setOnboardingDone(true);
        if (mounted) setState(() => _onboarded = true);
      });
    }
    return const AuthGate(child: HomeScreen());
  }
}
