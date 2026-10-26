import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'screens/home_screen.dart';
import 'screens/auth_gate.dart';
import 'screens/auth_screens.dart';
import 'services/account_service.dart';
import 'services/bank_sync.dart';
import 'services/db.dart';
import 'services/notification_service.dart';
import 'services/plus_service.dart';
import 'screens/contracts_screen.dart';
import 'screens/connections_screen.dart';
import 'screens/goals_screen.dart';
import 'screens/subscription_screen.dart';
import 'screens/weekly_report_screen.dart';
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
  await Hive.openBox('goals');

  // generate any recurring transactions that came due while the app was closed
  await RecurringService.process();
  // monthly budgets continue into the new month
  await DB.rollOverBudgets();

  // fetch new bookings from a linked bank in the background
  BankSync.refreshIfStale();

  // apply the saved theme mode
  ThemeController.isDark.value = Settings.darkMode;
  Settings.loadHideAmounts();
  Settings.loadGuest();
  PlusService.load();
  await AccountService.restore();

  // the Inter font ships with the app, so its licence belongs on the licences page
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['Inter'], await rootBundle.loadString('assets/fonts/Inter-OFL.txt'));
  });

  // reminders: open the matching page on tap, then bring them up to date
  NotificationService.onTap = _openFromNotification;
  await NotificationService.init();
  NotificationService.sync();

  // start the app
  runApp(const BudgetBuddyApp());
}

final navigatorKey = GlobalKey<NavigatorState>();

void _openFromNotification(String payload) {
  final Widget? page = switch (payload) {
    'weekly' => const WeeklyReportScreen(),
    'contracts' || 'hint:contracts' => const ContractsScreen(),
    'subscription' || 'hint:subscription' => const SubscriptionScreen(),
    'connections' || 'hint:connections' => const ConnectionsScreen(),
    'goals' || 'hint:goals' => const GoalsScreen(),
    _ => null, // budgets and bookings: the start screen is the right place
  };
  if (page != null) navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => page));
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
        navigatorKey: navigatorKey,
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

// Decides what to show: the welcome screen until someone signs in or chooses
// to try the app without an account, then the app behind the lock gate.
class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([AccountService.current, Settings.guest]),
      builder: (context, _) {
        final inApp = AccountService.current.value != null || Settings.guest.value;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: inApp ? const AuthGate(child: HomeScreen()) : const WelcomeScreen(),
        );
      },
    );
  }
}
