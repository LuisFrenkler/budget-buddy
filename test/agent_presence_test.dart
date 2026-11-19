import 'dart:io';
import 'package:budget_buddy/screens/account_screen.dart';
import 'package:budget_buddy/screens/buddy_screen.dart';
import 'package:budget_buddy/screens/depot_screen.dart';
import 'package:budget_buddy/screens/goals_screen.dart';
import 'package:budget_buddy/screens/home_screen.dart';
import 'package:budget_buddy/services/ahead_agent.dart';
import 'package:budget_buddy/services/app_nav.dart';
import 'package:budget_buddy/utils/theme.dart';
import 'package:budget_buddy/widgets/agent_bar.dart';
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
    Hive.init(Directory.systemTemp.createTempSync('agentpresence').path);
    for (final name in ['transactions', 'settings', 'recurring', 'badges', 'budgets', 'holdings', 'goals', 'splits']) {
      await Hive.openBox(name);
    }
  });

  Widget app(Widget home) => MaterialApp(
        theme: AppTheme.theme(true),
        locale: const Locale('de', 'DE'),
        supportedLocales: const [Locale('de', 'DE')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: home,
      );

  Future<void> pumpShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(const HomeScreen()));
    await tester.pump(const Duration(milliseconds: 500));
  }

  // the app's own debounce timers run out first
  Future<void> settle(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  }

  test('the shell knows every place the agent can ask for', () {
    for (final name in AppNav.places) {
      final p = HomeScreen.place(name, year: 2024);
      expect(p, isNotNull, reason: 'the shell cannot open "$name"');
      expect(p!.label, isNotEmpty);
      expect(p.tab != null || p.screen != null, isTrue, reason: '"$name" leads nowhere');
    }
    expect(HomeScreen.place('nirgendwo'), isNull);
    expect(AppNav.open('nirgendwo'), isFalse);
  });

  testWidgets('a tab place switches the tab, with the way back to Ahead', (tester) async {
    await pumpShell(tester);
    expect(find.byType(AccountScreen), findsNothing);
    expect(AppNav.open('budgets'), isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(AppNav.go.value, isNull); // the shell took it
    final konto = tester.widget<AccountScreen>(find.byType(AccountScreen));
    expect(konto.segment.value, 1);
    // Ahead is on the screen it opened
    expect(find.descendant(of: find.byType(AccountScreen), matching: find.byType(AgentBar)), findsOneWidget);
    expect(find.text('Ahead hat „Budgets“ geöffnet'), findsOneWidget);
    await tester.tap(find.text('Zurück zu Ahead'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    // the agent's page is in front again and takes the touch
    expect(find.byType(BuddyScreen).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await settle(tester);
  });

  testWidgets('any other place opens its screen on top', (tester) async {
    await pumpShell(tester);
    AppNav.open('ziele');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(GoalsScreen), findsOneWidget);
    expect(AppNav.go.value, isNull);
    // and a tab place from there closes it again
    AppNav.open('depot');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(GoalsScreen), findsNothing);
    expect(find.descendant(of: find.byType(DepotScreen), matching: find.byType(AgentBar)), findsOneWidget);
    expect(tester.takeException(), isNull);
    await settle(tester);
  });

  testWidgets('the agent bar sends its question through BuddyScreen.ask', (tester) async {
    BuddyScreen.ask.value = null;
    await tester.pumpWidget(app(const Scaffold(
        body: AgentBar(line: '**3 Buchungen** stecken noch in Sonstiges.', question: 'Sonstiges aufräumen'))));
    // nothing typed: the suggested question goes out
    await tester.tap(find.byKey(const Key('agent-bar-send')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(BuddyScreen.ask.value, 'Sonstiges aufräumen');
    // it is a real field: what the person writes is what Ahead gets
    BuddyScreen.ask.value = null;
    await tester.enterText(find.byKey(const Key('agent-bar-field')), 'Was kostet mich Netflix im Jahr?');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump(const Duration(milliseconds: 200));
    expect(BuddyScreen.ask.value, 'Was kostet mich Netflix im Jahr?');
    expect(find.text('Was kostet mich Netflix im Jahr?'), findsNothing);
    BuddyScreen.ask.value = null;
  });

  testWidgets('the orb counts the finds that wait for a yes, and nothing when none do', (tester) async {
    final box = Hive.box('settings');
    box.delete('agentSnoozed');
    List<AgentFind> waiting() => AheadAgent.run(tx: const [])
        .where((f) => f.kind == FindKind.tax || f.kind == FindKind.money)
        .toList();
    final finds = waiting();
    expect(finds, isNotEmpty, reason: 'a fresh install has the tax check waiting');
    await pumpShell(tester);
    expect(find.descendant(of: find.byKey(const Key('agent-count')), matching: find.text('${finds.length}')),
        findsOneWidget);
    // "Später" on every find: nothing waits any more
    final later = DateTime.now().add(const Duration(days: 7)).toIso8601String();
    box.put('agentSnoozed', {for (final f in finds) f.id: later});
    expect(waiting(), isEmpty);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const Key('agent-count')), findsNothing);
    box.delete('agentSnoozed');
    await settle(tester);
  });
}
