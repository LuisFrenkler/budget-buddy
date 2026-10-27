import 'dart:io';
import 'package:budget_buddy/screens/buddy_screen.dart';
import 'package:budget_buddy/screens/home_screen.dart';
import 'package:budget_buddy/utils/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    BuddyScreen.ask.value = '';
    await tester.pump(const Duration(milliseconds: 400));
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
    expect(find.byIcon(Icons.add_rounded), findsNothing); // the tab bar steps aside
    await settle(tester);
  });
}
