import 'dart:io';
import 'package:budget_buddy/models/holding.dart';
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/screens/account_screen.dart';
import 'package:budget_buddy/screens/buddy_screen.dart';
import 'package:budget_buddy/screens/depot_screen.dart';
import 'package:budget_buddy/screens/home_screen.dart';
import 'package:budget_buddy/services/buddy_history.dart';
import 'package:budget_buddy/services/db.dart';
import 'package:budget_buddy/services/settings_service.dart';
import 'package:budget_buddy/utils/money.dart';
import 'package:budget_buddy/utils/theme.dart';
import 'package:budget_buddy/widgets/buddy_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

// A question asked on Konto or Depot is answered with that screen's chart first.
void main() {
  const boxes = ['transactions', 'settings', 'recurring', 'badges', 'budgets', 'holdings', 'goals', 'splits'];

  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
    }
    await inter.load();
    Hive.init(Directory.systemTemp.createTempSync('answerchart').path);
    for (final name in boxes) {
      await Hive.openBox(name);
    }
  });

  // Hive is never awaited here: a write the app started under a test's fake
  // clock does not finish, and everything after it would wait forever
  void wipe(String name) => Hive.box(name).deleteAll(Hive.box(name).keys.toList());

  setUp(() {
    boxes.forEach(wipe);
    BuddyScreen.ask.value = null;
    BuddyScreen.askedFrom = null;
    Money.masked = false;
  });

  final today = DateTime.now();
  DateTime ago(int days) => DateTime(today.year, today.month, today.day - days);

  // 1.000 € to start with, a salary and a rent since: 2.400 € today
  void account() {
    Hive.box('settings').put('openingBalanceCents', 100000);
    DB.addTx(Transaction(id: 'a', amountCents: 200000, category: 'Gehalt', date: ago(40), isIncome: true));
    DB.addTx(Transaction(id: 'b', amountCents: 60000, category: 'Miete', date: ago(20), isIncome: false));
  }

  // a linked depot that went from 1.000 € to 1.100 €
  void depot() {
    DB.addHolding(Holding(
        id: 'depot_1', name: 'Welt-ETF', symbol: 'WELT', type: 'ETF', shares: 10, buyPriceCents: 10000, currentPriceCents: 11000));
    Settings.setDepotHistory([(ago(60), 100000), (ago(10), 105000), (ago(0), 110000)]);
  }

  Future<void> pumpShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.theme(true),
      locale: const Locale('de', 'DE'),
      supportedLocales: const [Locale('de', 'DE')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const HomeScreen(),
    ));
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  }

  // long enough for an offline answer to be written out
  Future<void> answered(WidgetTester tester) async {
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(seconds: 1));
  }

  // the pager slides over: one frame to start, one to arrive
  Future<void> go(WidgetTester tester, int tab) async {
    tab == 3 ? BuddyScreen.ask.value = '' : HomeScreen.goTab.value = tab;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  // writes into the agent bar of [T] and sends it
  Future<void> askOn<T extends Widget>(WidgetTester tester, int tab, String question) async {
    await go(tester, tab);
    final field = find.descendant(of: find.byType(T), matching: find.byKey(const Key('agent-bar-field')));
    await tester.enterText(field, question);
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await answered(tester);
  }

  Future<void> askInChat(WidgetTester tester, String question) async {
    await tester.enterText(find.byType(TextField).hitTestable(), question);
    await tester.pump();
    await tester.tap(find.byTooltip('Senden'));
    await answered(tester);
  }

  final chart = find.byType(PlaceChartCard);

  testWidgets('asked on Konto: the answer starts with the balance, once', (tester) async {
    account();
    await pumpShell(tester);
    await askOn<AccountScreen>(tester, 1, 'Wie steht es um mein Konto?');
    expect(find.text('Wie steht es um mein Konto?'), findsOneWidget); // in the chat now
    expect(chart, findsOneWidget);
    expect(find.descendant(of: chart, matching: find.text(Money.format(240000))), findsOneWidget);
    // a third of the chat at most, and above the answer's text
    expect(tester.getSize(chart).height, lessThan(160));
    expect(tester.getTopLeft(chart).dy, greaterThan(tester.getTopLeft(find.text('Wie steht es um mein Konto?')).dy));
    // the next question in the chat brings no second one
    await askInChat(tester, 'Was kannst du alles?');
    expect(find.text('Was kannst du alles?'), findsOneWidget);
    expect(chart, findsOneWidget);
    expect(tester.getTopLeft(chart).dy, lessThan(tester.getTopLeft(find.text('Was kannst du alles?')).dy));
    expect(tester.takeException(), isNull);
    await settle(tester);
  });

  testWidgets('asked on Depot: the answer starts with the change of 30 days', (tester) async {
    depot();
    await pumpShell(tester);
    await askOn<DepotScreen>(tester, 2, 'Wie läuft mein Depot gerade?');
    expect(chart, findsOneWidget);
    // 30 days ago the last known value was the 1.000 € of two months back
    expect(find.descendant(of: chart, matching: find.text(Money.signed(10000))), findsOneWidget);
    expect(tester.takeException(), isNull);
    await settle(tester);
  });

  testWidgets('the same question written in the chat has no chart', (tester) async {
    account();
    await pumpShell(tester);
    await askInChat(tester, 'Wie steht es um mein Konto?');
    expect(find.text('Wie steht es um mein Konto?'), findsOneWidget);
    expect(chart, findsNothing);
    await settle(tester);
  });

  testWidgets('nothing to draw, no chart: no balance, no holdings, hidden amounts', (tester) async {
    await pumpShell(tester);
    await askOn<AccountScreen>(tester, 1, 'Wie steht es um mein Konto?');
    expect(find.text('Wie steht es um mein Konto?'), findsOneWidget);
    expect(chart, findsNothing);
    await askOn<DepotScreen>(tester, 2, 'Lohnt sich ein Depot für mich?');
    expect(chart, findsNothing);
    await settle(tester);

    account();
    expect(await PlaceChart.of(AskPlace.account), isNotNull);
    expect(await PlaceChart.of(AskPlace.overview), isNotNull);
    Money.masked = true;
    expect(await PlaceChart.of(AskPlace.account), isNull);
    Money.masked = false;
    // a balance that never moved is a flat line
    wipe('transactions');
    expect(await PlaceChart.of(AskPlace.account), isNull);
  });

  // 30 messages, far longer than one screen
  void conversation() => BuddyHistory.save([
        for (var i = 1; i <= 30; i++)
          SavedMessage(i.isOdd, i.isOdd ? 'Frage $i' : 'Antwort $i mit ein paar Worten mehr, damit sie Platz braucht.', ago(1)),
      ]);

  // the chat's list is the one that starts at the bottom; found also while the pager shows another place
  final chat =
      find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.up, skipOffstage: false);

  // how far the chat is from its latest message
  double offset(WidgetTester tester) => tester.state<ScrollableState>(chat).position.pixels;

  final first = find.text('Frage 1');
  final latest = find.textContaining('Antwort 30', findRichText: true);

  testWidgets('a saved conversation opens at its latest message and is still there after coming back', (tester) async {
    conversation();
    await pumpShell(tester);
    await tester.tap(find.byKey(const Key('feed-toggle')));
    await tester.pump(); // the first frame of the chat
    expect(latest.hitTestable(), findsOneWidget);
    expect(first, findsNothing);
    expect(offset(tester), 0);
    // away to Konto and back
    await go(tester, 1);
    await go(tester, 3);
    expect(latest.hitTestable(), findsOneWidget);
    // asked for again while it is in front: still the latest message, not the top
    await go(tester, 3);
    expect(latest.hitTestable(), findsOneWidget);
    expect(first, findsNothing);
    expect(offset(tester), 0);
    await settle(tester);
  });

  // from sending until the answer is written: whenever the chat shows, it is
  // at its end, and the question is on screen from its first frame
  Future<void> follow(WidgetTester tester, String question) async {
    var seen = false;
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (chat.evaluate().isNotEmpty) expect(offset(tester), 0, reason: 'frame $i');
      if (!seen && find.text(question).evaluate().isNotEmpty) {
        seen = true;
        final at = tester.getRect(find.text(question));
        expect(at.top, greaterThan(0));
        expect(at.bottom, lessThan(844));
      }
    }
    expect(seen, isTrue);
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(seconds: 1));
    expect(offset(tester), 0);
  }

  Future<void> send(WidgetTester tester, String question) async {
    await go(tester, 1);
    await tester.enterText(
        find.descendant(of: find.byType(AccountScreen), matching: find.byKey(const Key('agent-bar-field'))), question);
    await tester.testTextInput.receiveAction(TextInputAction.send);
  }

  // the founder's case: a long conversation exists, the question comes from the Konto bar
  testWidgets('asked on Konto with a long conversation: the chat is at the very bottom, question and answer in view',
      (tester) async {
    account();
    conversation();
    await pumpShell(tester);

    // 1. the conversation was not on screen yet
    expect(chat, findsNothing);
    await send(tester, 'Wie steht es um mein Konto?');
    await follow(tester, 'Wie steht es um mein Konto?');
    expect(find.text('Wie steht es um mein Konto?').hitTestable(), findsOneWidget);
    expect(chart.hitTestable(), findsOneWidget);
    expect(first, findsNothing);

    // 2. the chat is on screen and was left scrolled up
    await tester.drag(chat, const Offset(0, 900));
    await tester.pump(const Duration(milliseconds: 600));
    expect(offset(tester), greaterThan(300));
    await send(tester, 'Wie viel habe ich diesen Monat ausgegeben?');
    await tester.pump();
    expect(offset(tester), 0); // the first frame after sending
    await follow(tester, 'Wie viel habe ich diesen Monat ausgegeben?');
    expect(find.text('Wie viel habe ich diesen Monat ausgegeben?').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await settle(tester);
  });

  testWidgets('the question builds the agent screen: also then the chat starts at its end, chart first', (tester) async {
    account();
    conversation();
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    BuddyScreen.askedFrom = AskPlace.account;
    BuddyScreen.ask.value = 'Wie steht es um mein Konto?';
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.theme(true),
      locale: const Locale('de', 'DE'),
      supportedLocales: const [Locale('de', 'DE')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const BuddyScreen(tab: true),
    ));
    await follow(tester, 'Wie steht es um mein Konto?');
    expect(chart.hitTestable(), findsOneWidget);
    expect(first, findsNothing);
    await settle(tester);
  });

  testWidgets('scrolled up on purpose: a growing answer does not move what is being read', (tester) async {
    conversation();
    await pumpShell(tester);
    await tester.tap(find.byKey(const Key('feed-toggle')));
    await tester.pump(const Duration(milliseconds: 300));
    const question = 'Wie viel habe ich diesen Monat ausgegeben?';
    await tester.enterText(find.byType(TextField).hitTestable(), question);
    await tester.pump();
    await tester.tap(find.byTooltip('Senden'));
    // until the question is in the chat, before the answer is written out
    final asked = find.descendant(of: chat, matching: find.text(question));
    for (var i = 0; i < 10 && asked.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.drag(chat, const Offset(0, 200));
    await tester.pump();
    final was = offset(tester);
    final read = tester.getTopLeft(find.text('Frage 29')).dy;
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // the answer grew below, the line being read stayed where it was
    expect(offset(tester), greaterThan(was));
    expect(tester.getTopLeft(find.text('Frage 29')).dy, moreOrLessEquals(read, epsilon: 0.5));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
  });
}
