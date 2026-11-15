import 'dart:io';
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/screens/account_screen.dart';
import 'package:budget_buddy/screens/buddy_screen.dart';
import 'package:budget_buddy/screens/depot_screen.dart';
import 'package:budget_buddy/screens/overview_screen.dart';
import 'package:budget_buddy/l10n/l10n.dart';
import 'package:budget_buddy/screens/home_screen.dart';
import 'package:budget_buddy/utils/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  setUpAll(() async {
    // the real font: the test font's square glyphs make every line far too wide
    final inter = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
    }
    await inter.load();
    Hive.init(Directory.systemTemp.createTempSync('buddytab').path);
    for (final name in ['transactions', 'settings', 'recurring', 'badges', 'budgets', 'holdings', 'goals', 'splits']) {
      await Hive.openBox(name);
    }
  });

  // the app's own debounce timers (notifications, autosave) run out first
  Future<void> settle(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  }

  Future<void> pumpShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(780, 1688); // 390 x 844, an iPhone
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.theme(true),
      locale: Locale('de', 'DE'),
      supportedLocales: [Locale('de', 'DE')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const HomeScreen(),
    ));
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('Buddy is a tab, and asking from elsewhere lands in it', (tester) async {
    await pumpShell(tester);
    expect(find.text('Buddy'), findsWidgets); // the tab label
    // adding by hand moved to the Konto tab: Buddy adds from the chat
    expect(find.bySemanticsLabel(RegExp('^Schnell erfassen')), findsNothing);
    expect(HomeScreen.addMenu, isNotNull);
    BuddyScreen.ask.value = '';
    // the tab is built when first opened, then takes the question a frame later
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(BuddyScreen.ask.value, isNull); // the tab took it
    expect(tester.takeException(), isNull);
    await settle(tester);
  });

  testWidgets('with the keyboard open the question field sits right above it', (tester) async {
    await pumpShell(tester);
    BuddyScreen.ask.value = '';
    await tester.pump(const Duration(milliseconds: 400));
    tester.view.viewInsets = const FakeViewPadding(bottom: 600); // 300 pt keyboard
    addTearDown(tester.view.resetViewInsets);
    await tester.pump(const Duration(milliseconds: 400));
    final field = find.byType(TextField).hitTestable();
    expect(field, findsOneWidget);
    final bottom = tester.getBottomLeft(field).dy;
    expect(bottom, lessThanOrEqualTo(844 - 300));
    expect(bottom, greaterThan(844 - 300 - 90)); // no gap of a hidden tab bar
    expect(find.text('Überblick'), findsNothing); // the tab bar steps aside
    await settle(tester);
  });

  testWidgets('a screen reader hears who speaks in the chat', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpShell(tester);
    BuddyScreen.ask.value = '';
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField), 'Was kannst du alles?');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Senden'));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(seconds: 1));
    // the answer: who speaks, read out when it arrives
    final buddy = find.bySemanticsLabel(RegExp(r'^Buddy\nIch rechne'));
    expect(buddy, findsOneWidget);
    expect(tester.getSemantics(buddy).getSemanticsData().flagsCollection.isLiveRegion, isTrue);
    // the question above it: scroll back up to it
    await tester.drag(find.ancestor(of: buddy, matching: find.byType(Scrollable)).first, const Offset(0, 2000));
    await tester.pump(const Duration(milliseconds: 500));
    final mine = find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Du', skipOffstage: false);
    expect(mine, findsOneWidget);
    expect((tester.widget(mine) as Semantics).properties.hintOverrides?.onLongPressHint, 'Kopieren und mehr');
    handle.dispose();
    await settle(tester);
  });

  testWidgets('switching the language switches the chat', (tester) async {
    await pumpShell(tester);
    BuddyScreen.ask.value = '';
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField), 'Was kannst du alles?');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Senden'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(seconds: 1));
    L10n.lang.value = 'en';
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.textContaining("from now on I'll answer in English", findRichText: true), findsOneWidget);
    // the chips under the answer are the app's own texts: they follow
    expect(find.textContaining('Wie viel', findRichText: true), findsNothing);
    L10n.lang.value = 'de';
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.textContaining('ab jetzt antworte ich auf Deutsch', findRichText: true, skipOffstage: false), findsOneWidget);
    expect(find.textContaining("from now on I'll answer in English", findRichText: true, skipOffstage: false), findsNothing);
    await settle(tester);
  });

  testWidgets('cold start mounts Buddy only', (tester) async {
    await pumpShell(tester);
    expect(find.byType(BuddyScreen), findsOneWidget);
    expect(find.byType(OverviewScreen), findsNothing);
    expect(find.byType(AccountScreen), findsNothing);
    expect(find.byType(DepotScreen), findsNothing);
    expect(tester.takeException(), isNull);
    await settle(tester);
  });

  testWidgets('Monatsrückblick in the chat opens the story chip', (tester) async {
    final now = DateTime.now();
    final tx = Transaction(
      id: 'recap-now',
      amountCents: 1299,
      category: 'Lebensmittel',
      date: DateTime(now.year, now.month, now.day),
      isIncome: false,
      note: 'REWE',
    );
    // in memory at once; awaiting the flush deadlocks the test clock
    Hive.box('transactions').put(tx.id, tx.toMap());
    await pumpShell(tester);
    await tester.enterText(find.byType(TextField), 'Monatsrückblick');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Senden'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.textContaining('Dein Monatsrückblick als Story', findRichText: true), findsOneWidget);
    expect(find.text('Deine Story'), findsOneWidget);
    Navigator.of(tester.element(find.text('Deine Story'))).pop();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Monats-Story teilen'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Story teilen'), findsOneWidget);
    expect(tester.takeException(), isNull);
    Hive.box('transactions').delete(tx.id);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }, timeout: const Timeout(Duration(seconds: 20)));
}
