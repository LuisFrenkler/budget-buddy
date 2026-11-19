// The reduction pass: every screen fits a small phone with the sample data,
// and what answers a finger or a changed number comes to rest.
import 'dart:io';
import 'package:budget_buddy/screens/account_screen.dart';
import 'package:budget_buddy/screens/depot_screen.dart';
import 'package:budget_buddy/screens/overview_screen.dart';
import 'package:budget_buddy/screens/profile_screen.dart';
import 'package:budget_buddy/services/db.dart';
import 'package:budget_buddy/services/demo_data.dart';
import 'package:budget_buddy/services/tax_estimate.dart';
import 'package:budget_buddy/utils/motion.dart';
import 'package:budget_buddy/utils/theme.dart';
import 'package:budget_buddy/widgets/agent_feed.dart';
import 'package:budget_buddy/widgets/finance_stand.dart';
import 'package:budget_buddy/widgets/settings_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
    }
    await inter.load();
    Hive.init(Directory.systemTemp.createTempSync('designpass').path);
    for (final name in ['transactions', 'settings', 'recurring', 'badges', 'budgets', 'holdings', 'goals', 'splits']) {
      await Hive.openBox(name);
    }
    await DemoData.load();
    // a tax find with money in it, so the feed has a card to press and put away
    await TaxEstimate.saveProfile(const TaxProfile(grossMonth: 3000, monthsWorked: 4, km: 20),
        year: DateTime.now().year - 1);
  });

  // 375 px wide, like a small iPhone; [height] in logical px
  Future<void> pump(WidgetTester tester, Widget home, {double height = 812}) async {
    tester.view.physicalSize = Size(750, height * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.theme(true),
      locale: const Locale('de', 'DE'),
      supportedLocales: const [Locale('de', 'DE')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: home,
    ));
    await tester.pump(const Duration(milliseconds: 500));
  }

  // the screens' own debounce timers run out before the test ends
  Future<void> settle(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  }

  // a text overflow or a RenderFlex overflow would have thrown by now
  void fits(WidgetTester tester) => expect(tester.takeException(), isNull);

  testWidgets('Überblick fits 375 px with the sample data', (tester) async {
    await pump(tester, Scaffold(body: OverviewScreen(onOpen: (_, {segment}) {})));
    fits(tester);
    await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
    await tester.pump(const Duration(milliseconds: 500));
    fits(tester);
    await settle(tester);
  });

  testWidgets('Konto fits 375 px with the sample data, in every section', (tester) async {
    final segment = ValueNotifier(0);
    await pump(tester, Scaffold(body: AccountScreen(segment: segment)));
    fits(tester);
    for (final s in [1, 2]) {
      segment.value = s;
      await tester.pump(const Duration(milliseconds: 500));
      fits(tester);
    }
    await settle(tester);
  });

  testWidgets('Depot fits 375 px with the sample data', (tester) async {
    await pump(tester, const DepotScreen());
    fits(tester);
    await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
    await tester.pump(const Duration(milliseconds: 500));
    fits(tester);
    await settle(tester);
  });

  testWidgets('Profil fits 375 px: a header and four short groups, no scrolling through settings', (tester) async {
    await pump(tester, const ProfileScreen(), height: 1200);
    fits(tester);
    // the rows that stay; the rest is reached through Ahead
    for (final row in ['Alle Bereiche', 'Ahead Plus', 'Banken & Depots', 'Mitteilungen', 'App-Sperre', 'Beträge verbergen', 'Ahead mit KI', 'Wo deine Daten liegen', 'Dunkler Modus', 'Sprache', 'Hilfe & Rechtliches']) {
      expect(find.text(row), findsOneWidget, reason: row);
    }
    expect(find.byType(SettingsRow).evaluate().length, lessThanOrEqualTo(13));
    await settle(tester);
  });

  // a tax find from setUpAll gives the feed a card with a main button
  Future<void> feed(WidgetTester tester, {bool reduce = false}) async {
    tester.view.physicalSize = const Size(750, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) =>
            MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: reduce), child: child!),
        home: Scaffold(body: SingleChildScrollView(child: AgentFeed(onAsk: (_) {})))));
    await tester.pump();
  }

  Finder go() => find.byWidgetPredicate(
      (w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('go-tax-'));
  double scale(WidgetTester tester) => tester
      .widget<AnimatedScale>(find.ancestor(of: go().first, matching: find.byType(AnimatedScale)).first)
      .scale;

  testWidgets('a held card sinks, comes back up and then rests', (tester) async {
    await feed(tester);
    expect(tester.hasRunningAnimations, isFalse); // the first paint stays still
    final finger = await tester.startGesture(tester.getCenter(go().first));
    await tester.pump(const Duration(milliseconds: 20));
    expect(scale(tester), Motion.pressScale);
    await tester.pump(Motion.press);
    // let go beside the button: nothing opens, the card comes back
    await finger.cancel();
    await tester.pump();
    expect(scale(tester), 1);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('with reduced motion the card does not move under the finger', (tester) async {
    await feed(tester, reduce: true);
    final finger = await tester.startGesture(tester.getCenter(go().first));
    await tester.pump(const Duration(milliseconds: 20));
    expect(scale(tester), 1);
    await finger.cancel();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('a changed figure fades in once, never two numbers at a time, then rests', (tester) async {
    Widget stand(String free) =>
        MaterialApp(home: Scaffold(body: FinanceStand(tx: DB.getTx(), free: free, cashCents: 500000)));
    await tester.pumpWidget(stand('412,00 €'));
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pumpWidget(stand('300,00 €'));
    await tester.pump();
    expect(find.text('412,00 €'), findsNothing);
    expect(find.text('300,00 €'), findsOneWidget);
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pump(Motion.fast * 2);
    expect(tester.hasRunningAnimations, isFalse);
  });
}
