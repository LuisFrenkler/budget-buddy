import 'dart:async';
import 'l10n/l10n.dart';
import 'legal/legal_lang.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'screens/buddy_screen.dart';
import 'services/buddy_tasks.dart';
import 'screens/home_screen.dart';
import 'screens/auth_gate.dart';
import 'screens/auth_screens.dart';
import 'services/cloud_sync.dart';
import 'services/account_service.dart';
import 'services/bank_sync.dart';
import 'services/auto_save.dart';
import 'services/db.dart';
import 'services/depot_sync.dart';
import 'services/notification_service.dart';
import 'services/plus_service.dart';
import 'services/product_events.dart';
import 'services/split_service.dart';
import 'services/store_purchases.dart';
import 'screens/contracts_screen.dart';
import 'screens/connections_screen.dart';
import 'screens/goals_screen.dart';
import 'screens/subscription_screen.dart';
import 'screens/weekly_report_screen.dart';
import 'services/recurring_service.dart';
import 'services/settings_service.dart';
import 'services/note_scrub.dart';
import 'utils/theme.dart';
import 'services/invite_service.dart';

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
  await Hive.openBox('splits');

  // apply the saved theme mode
  ThemeController.isDark.value = Settings.darkMode;
  Settings.loadHideAmounts();
  L10n.load();
  // the legal texts follow the app's language (they stay plain Dart for the server)
  LegalLang.isDe = () => L10n.isDe;
  // guest mode removed, clear any leftover flag from older installs
  await Settings.setGuest(false);
  PlusService.load();
  await ProductEvents.noteOpen();
  // App Store / Google Play: purchases, renewals and ones left from a crash
  StorePurchases.init();
  // session + wipe before any finance mutation (recurring / budgets / autosave)
  await AccountService.restore();
  // vault first, otherwise Recurring/AutoSave mutate local, the UI paints that
  // Kontostand, then cloud restore overwrites it and the number jumps
  await CloudSync.start();
  // generate any recurring transactions that came due while the app was closed
  await RecurringService.process();
  // monthly budgets continue into the new month
  await DB.rollOverBudgets();
  // goals on autopilot (a Plus feature, so after Plus is known)
  await AutoSave.run();
  // Mandats-/Mandantenreferenz titles → readable (once)
  await NoteScrub.runOnce();
  PlusService.watchAccount();
  PlusService.syncWithServer();
  // bank/depot after first frame. LedgerBusy freezes Konto while they write
  unawaited(BankSync.refreshIfStale());
  unawaited(DepotSync.refreshIfStale());

  // fonts ship with the app, so their licences belong on the licences page
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
        ['Inter'], await rootBundle.loadString('assets/fonts/Inter-OFL.txt'));
    yield LicenseEntryWithLineBreaks(['Bricolage Grotesque'],
        await rootBundle.loadString('assets/fonts/BricolageGrotesque-OFL.txt'));
  });

  // reminders: open the matching page on tap, then bring them up to date
  // an opened invite link (…/?join=CODE): remembered until the user is in
  final join = Uri.base.queryParameters['join'];
  final code = join?.trim().toUpperCase() ?? '';
  // a reload of the same link after joining asks nothing
  if (code.isNotEmpty && !SplitService.all().any((g) => g.code == code))
    await SplitService.setPendingJoin(code);
  // a friend's invite link (…/?ref=CODE): sent along when this person signs up
  await InviteService.rememberRef(Uri.base.queryParameters['ref']);
  // what the others added in shared groups since last time
  SplitService.refreshAll();

  NotificationService.onTap = _openFromNotification;
  BuddyTasks.onDated = NotificationService.syncSoon;
  await NotificationService.init();
  NotificationService.sync();

  // start the app
  runApp(AheadApp());
}

final navigatorKey = GlobalKey<NavigatorState>();

void _openFromNotification(String payload) {
  // Buddy's moments open his chat with the question that fits
  if (payload.startsWith('buddy:')) {
    navigatorKey.currentState?.popUntil((r) => r.isFirst);
    BuddyScreen.ask.value = payload.substring(6);
    return;
  }
  final Widget? page = switch (payload) {
    'weekly' => WeeklyReportScreen(),
    'contracts' || 'hint:contracts' => ContractsScreen(),
    'subscription' || 'hint:subscription' => SubscriptionScreen(),
    'connections' || 'hint:connections' => ConnectionsScreen(),
    'goals' || 'hint:goals' => GoalsScreen(),
    _ => null, // budgets and bookings: the start screen is the right place
  };
  if (page != null)
    navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => page));
}

class AheadApp extends StatefulWidget {
  AheadApp({super.key});

  @override
  State<AheadApp> createState() => _AheadAppState();
}

class _AheadAppState extends State<AheadApp> {
  @override
  void initState() {
    super.initState();
    ThemeController.isDark.addListener(_repaintEverything);
    Settings.hideAmounts.addListener(_repaintEverything);
    L10n.lang.addListener(_languageChanged);
  }

  // the locale is a MaterialApp parameter, so this widget rebuilds too
  void _languageChanged() {
    setState(() {});
    _repaintEverything();
  }

  @override
  void dispose() {
    ThemeController.isDark.removeListener(_repaintEverything);
    Settings.hideAmounts.removeListener(_repaintEverything);
    L10n.lang.removeListener(_languageChanged);
    super.dispose();
  }

  // The colours and the privacy mask are read straight from AppColors and
  // Money, not passed down the tree, so widgets Flutter considers unchanged
  // (ones, tabs kept alive, open pages below the current one) would keep
  // the old state. After a switch every element is rebuilt once, so light and
  // dark, hidden and shown amounts apply everywhere at the same moment.
  void _repaintEverything() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      void mark(Element e) {
        e.markNeedsBuild();
        e.visitChildren(mark);
      }

      if (mounted) (context as Element).visitChildren(mark);
    });
  }

  @override
  Widget build(BuildContext context) {
    // rebuild the whole app when the theme mode is toggled
    return ValueListenableBuilder<bool>(
      valueListenable: ThemeController.isDark,
      builder: (_, dark, __) => MaterialApp(
        title: 'Ahead',
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false, // hide debug banner
        theme: AppTheme.theme(dark), // reactive light/dark theme
        // date pickers, tooltips and dialogs follow the app language; en_IE
        // keeps euros and weeks starting on Monday
        locale: L10n.isDe ? Locale('de', 'DE') : Locale('en', 'IE'),
        supportedLocales: [Locale('de', 'DE'), Locale('en', 'IE')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: RootGate(), // onboarding -> lock -> app
        // the lock sits above the Navigator, so it covers every open page;
        // on wide screens (desktop browser, Mac) keep a phone-width column
        // in the middle instead of stretching every screen edge to edge
        builder: (context, child) => ColoredBox(
          color: dark ? Color(0xFF05070A) : Color(0xFFE6EAF0),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 480),
              child: AuthGate(child: child ?? SizedBox.shrink()),
            ),
          ),
        ),
      ),
    );
  }
}

// Welcome until signed in, then the app (the lock wraps it all).
class RootGate extends StatelessWidget {
  RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Account?>(
      valueListenable: AccountService.current,
      builder: (context, account, _) {
        return AnimatedSwitcher(
          duration: Duration(milliseconds: 350),
          child: account != null ? HomeScreen() : WelcomeScreen(),
        );
      },
    );
  }
}
