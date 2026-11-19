// The shell: Ahead, Konto and Depot in one pager that follows the finger, one
// fixed row on top (the switch and the profile), nothing at the bottom, and
// gestures inside a page keep their own drag.
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/screens/account_screen.dart';
import 'package:budget_buddy/screens/buddy_screen.dart';
import 'package:budget_buddy/screens/depot_screen.dart';
import 'package:budget_buddy/screens/home_screen.dart';
import 'package:budget_buddy/screens/overview_screen.dart';
import 'package:budget_buddy/screens/profile_screen.dart';
import 'package:budget_buddy/services/app_nav.dart';
import 'package:budget_buddy/utils/theme.dart';
import 'package:budget_buddy/widgets/interactive_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  final haptics = <String>[];
  const boxes = ['transactions', 'settings', 'recurring', 'badges', 'budgets', 'holdings', 'goals', 'splits'];

  setUpAll(() async {
    // the real font: the test font's square glyphs make every line far too wide
    final inter = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
    }
    await inter.load();
    // in memory: a file write would not finish inside a widget test
    for (final name in boxes) {
      await Hive.openBox(name, bytes: Uint8List(0));
    }
  });

  setUp(() async {
    for (final name in boxes) {
      await Hive.box(name).clear();
    }
    BuddyScreen.ask.value = null;
    AppNav.go.value = null;
    haptics.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,
        (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add('${call.arguments}'.split('.').last);
      return null;
    });
  });

  Future<void> pumpShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(780, 1688); // 390 x 844, an iPhone
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

  // the app's own debounce timers run out first
  Future<void> settle(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  }

  // a slide or a release comes to rest
  Future<void> rest(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  double page(WidgetTester tester) => tester.widget<PageView>(find.byType(PageView)).controller!.page!;
  bool on(WidgetTester tester, String key) => tester.widget<Semantics>(find.byKey(Key(key))).properties.selected!;
  Future<void> go(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await rest(tester);
  }

  // a point on the agent's page, and one at the top of Konto and Depot where nothing swipes by itself
  const onAhead = Offset(300, 400);
  const onPage = Offset(24, 70);

  void addTx(String id, {int daysAgo = 0}) {
    final now = DateTime.now();
    final tx = Transaction(
      id: id,
      amountCents: 1299,
      category: 'Lebensmittel',
      date: DateTime(now.year, now.month, now.day).subtract(Duration(days: daysAgo)),
      isIncome: false,
      note: 'REWE $id',
    );
    Hive.box('transactions').put(tx.id, tx.toMap());
  }

  testWidgets('a drag from Ahead lands on Konto, and the switch shows it', (tester) async {
    await pumpShell(tester);
    // the navigation at the bottom, where the thumb is: the orb for Ahead, Konto and Depot in the pill
    final height = tester.getSize(find.byType(Scaffold).first).height;
    for (final key in ['seg-ahead', 'seg-konto', 'seg-depot']) {
      expect(tester.getRect(find.byKey(Key(key))).top, greaterThanOrEqualTo(height - 100));
    }
    expect(tester.widget<Semantics>(find.byKey(const Key('seg-ahead'))).properties.label, 'Ahead');
    expect(on(tester, 'seg-ahead'), isTrue);
    expect(on(tester, 'seg-konto'), isFalse);
    // the finds that wait sit on the orb
    expect(find.descendant(of: find.byKey(const Key('seg-ahead')), matching: find.byKey(const Key('agent-count'))),
        findsOneWidget);
    expect(find.byType(OverviewScreen), findsNothing); // built when it is swiped in

    await tester.dragFrom(onAhead, const Offset(-300, 0));
    await rest(tester);
    expect(page(tester), 1);
    expect(find.byType(OverviewScreen), findsOneWidget);
    expect(on(tester, 'seg-ahead'), isFalse);
    expect(on(tester, 'seg-ueberblick'), isTrue);
    expect(on(tester, 'seg-konto'), isFalse);
    // the agent's page is kept, not built again on the way back
    expect(find.byType(BuddyScreen, skipOffstage: false), findsOneWidget);
    expect(find.byType(DepotScreen, skipOffstage: false), findsNothing);
    expect(haptics, ['selectionClick']);
    expect(tester.takeException(), isNull);
    await settle(tester);
  });

  testWidgets('the page follows the finger, and a short drag springs back without a tick', (tester) async {
    await pumpShell(tester);
    final row = tester.getRect(find.byKey(const Key('seg-konto')));
    final finger = await tester.startGesture(onAhead);
    await finger.moveBy(const Offset(-30, 0)); // past the slop: the pager has it
    await finger.moveBy(const Offset(-100, 0));
    await tester.pump();
    expect(page(tester), closeTo(100 / 390, 0.01)); // one to one
    expect(on(tester, 'seg-ahead'), isTrue);
    expect(tester.getRect(find.byKey(const Key('seg-konto'))), row); // the row stays put
    // past half-way the switch shows the new place while the finger is still down
    await finger.moveBy(const Offset(-150, 0));
    await tester.pump();
    expect(on(tester, 'seg-ueberblick'), isTrue);
    // and it can be taken back
    await finger.moveBy(const Offset(170, 0));
    await tester.pump();
    expect(on(tester, 'seg-ahead'), isTrue);
    await finger.up();
    await rest(tester);
    expect(page(tester), 0);
    expect(on(tester, 'seg-ahead'), isTrue);
    expect(haptics, isEmpty);
    // the first place is the edge: nothing wraps around
    await tester.dragFrom(onAhead, const Offset(300, 0));
    await rest(tester);
    expect(page(tester), 0);
    expect(haptics, isEmpty);
    expect(tester.takeException(), isNull);
    await settle(tester);
  });

  testWidgets('Depot is there without a holding; the segments switch and follow the swipe', (tester) async {
    expect(Hive.box('holdings').isEmpty, isTrue);
    await pumpShell(tester);
    await go(tester, 'seg-konto');
    expect(page(tester), 2);
    expect(on(tester, 'seg-konto'), isTrue);
    haptics.clear();

    await tester.dragFrom(onPage, const Offset(-300, 0));
    await rest(tester);
    expect(page(tester), 3);
    expect(find.byType(DepotScreen), findsOneWidget);
    expect(on(tester, 'seg-depot'), isTrue);
    expect(on(tester, 'seg-konto'), isFalse);
    expect(haptics, ['selectionClick']);
    // Depot is the last place: the edge holds
    await tester.dragFrom(onPage, const Offset(-300, 0));
    await rest(tester);
    expect(page(tester), 3);

    await go(tester, 'seg-ahead');
    expect(page(tester), 0);
    expect(on(tester, 'seg-ahead'), isTrue);
    await go(tester, 'seg-depot');
    expect(page(tester), 3);
    expect(on(tester, 'seg-depot'), isTrue);
    await go(tester, 'seg-konto');
    expect(page(tester), 2);
    expect(on(tester, 'seg-konto'), isTrue);
    expect(tester.takeException(), isNull);
    await settle(tester);
  });

  testWidgets('with less motion a tap jumps, and the swipe still follows the finger', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpShell(tester);
    await tester.tap(find.byKey(const Key('seg-depot')));
    await tester.pump();
    expect(page(tester), 3);
    final finger = await tester.startGesture(onPage);
    await finger.moveBy(const Offset(30, 0));
    await finger.moveBy(const Offset(100, 0));
    await tester.pump();
    expect(page(tester), inExclusiveRange(2.6, 2.8));
    await finger.up();
    await rest(tester);
    expect(page(tester), 3);
    expect(tester.takeException(), isNull);
    await settle(tester);
  });

  testWidgets('the avatar opens the profile from each page', (tester) async {
    await pumpShell(tester);
    for (final key in ['seg-ahead', 'seg-konto', 'seg-depot']) {
      await go(tester, key);
      // top right on the page that is in front
      final avatar = find.byKey(const Key('profile-avatar')).hitTestable().first;
      expect(tester.getRect(avatar).bottom, lessThanOrEqualTo(80), reason: key);
      await tester.tap(avatar);
      await rest(tester);
      expect(find.byType(ProfileScreen), findsOneWidget, reason: key);
      Navigator.of(tester.element(find.byType(ProfileScreen))).pop();
      await rest(tester);
      expect(find.byType(ProfileScreen), findsNothing);
      expect(on(tester, key), isTrue);
    }
    expect(tester.takeException(), isNull);
    await settle(tester);
  });

  testWidgets('every place the agent can name still opens', (tester) async {
    await pumpShell(tester);
    bool onTop() => Navigator.of(tester.element(find.byType(HomeScreen, skipOffstage: false))).canPop();
    for (final name in AppNav.places) {
      expect(AppNav.open(name), isTrue);
      await tester.pump();
      await rest(tester);
      expect(AppNav.go.value, isNull, reason: 'the shell did not take "$name"');
      expect(tester.takeException(), isNull, reason: '"$name" threw');
      final p = HomeScreen.place(name)!;
      expect(onTop(), p.screen != null, reason: name);
      switch (p.tab) {
        case 0:
          expect(page(tester), 1, reason: name);
          expect(on(tester, 'seg-ueberblick'), isTrue);
        case 1:
          expect(page(tester), 2, reason: name);
          expect(on(tester, 'seg-konto'), isTrue);
          expect(tester.widget<AccountScreen>(find.byType(AccountScreen)).segment.value, p.segment);
        case 2:
          expect(page(tester), 3);
          expect(on(tester, 'seg-depot'), isTrue);
        case 3:
          expect(page(tester), 0);
          expect(on(tester, 'seg-ahead'), isTrue);
      }
    }
    // from the Überblick on into a view: the pager turns
    AppNav.open('ueberblick');
    await tester.pump();
    await rest(tester);
    tester.widget<OverviewScreen>(find.byType(OverviewScreen)).onOpen(2);
    await rest(tester);
    expect(onTop(), isFalse);
    expect(page(tester), 3);
    expect(tester.takeException(), isNull);
    await settle(tester);
  });

  testWidgets('a drag that starts on a swipeable Konto row does not change the place', (tester) async {
    for (var i = 0; i < 30; i++) {
      addTx('row-$i', daysAgo: i ~/ 3);
    }
    await pumpShell(tester);
    await go(tester, 'seg-konto');
    haptics.clear();
    final list = find.descendant(of: find.byType(AccountScreen), matching: find.byType(Scrollable)).first;

    // the balance chart is scrubbed, the page stays
    final chart = find.byType(InteractiveChart).hitTestable();
    expect(chart, findsOneWidget);
    await tester.drag(chart, const Offset(-150, 0));
    await rest(tester);
    expect(page(tester), 2);
    await tester.drag(chart, const Offset(150, 0));
    await rest(tester);
    expect(page(tester), 2);
    haptics.clear(); // the chart ticks by itself while it is scrubbed

    // a row is swiped away, the page stays: also against the direction it deletes in
    await tester.drag(list, const Offset(0, -300));
    await rest(tester);
    final row = find.byType(Dismissible).hitTestable().first;
    final text = find.descendant(of: row, matching: find.textContaining('REWE')).first;
    final before = tester.getTopLeft(text).dx;
    final finger = await tester.startGesture(tester.getCenter(row));
    await finger.moveBy(const Offset(-30, 0));
    await finger.moveBy(const Offset(-70, 0));
    await tester.pump();
    expect(page(tester), 2);
    expect(tester.getTopLeft(text).dx, lessThan(before)); // the row has the drag
    await finger.up();
    await rest(tester);
    await tester.dragFrom(tester.getCenter(row), const Offset(200, 0));
    await rest(tester);
    expect(page(tester), 2);
    expect(on(tester, 'seg-konto'), isTrue);
    expect(haptics, isEmpty);

    // the active segment again scrolls the view back to the top
    final scroll = tester.widget<AccountScreen>(find.byType(AccountScreen)).scroll!;
    expect(scroll.offset, greaterThan(0));
    await go(tester, 'seg-konto');
    expect(scroll.offset, 0);

    // and the page itself still swipes from anywhere else
    await tester.dragFrom(onPage, const Offset(-300, 0));
    await rest(tester);
    expect(page(tester), 3);
    expect(tester.takeException(), isNull);
    await settle(tester);
  });

  testWidgets('a tap on the active Ahead segment leaves the chat where it is', (tester) async {
    await pumpShell(tester);
    for (var i = 0; i < 3; i++) {
      await tester.enterText(find.byType(TextField), 'Was kannst du alles?');
      await tester.pump();
      await tester.tap(find.byTooltip('Senden'));
      for (var j = 0; j < 40; j++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
      await tester.pump(const Duration(seconds: 1));
    }
    await rest(tester);
    final scroll = tester.widget<BuddyScreen>(find.byType(BuddyScreen)).scroll!;
    expect(scroll.position.maxScrollExtent, greaterThan(400), reason: 'the chat is long enough to scroll');
    scroll.jumpTo(300);
    await rest(tester);
    final where = scroll.offset;
    expect(where, greaterThan(0));

    await go(tester, 'seg-ahead');
    expect(scroll.offset, where);

    // away and back, by finger and by tap: the page is kept with its position
    await tester.dragFrom(const Offset(300, 200), const Offset(-300, 0));
    await rest(tester);
    expect(page(tester), 1);
    await tester.dragFrom(onPage, const Offset(300, 0));
    await rest(tester);
    expect(page(tester), 0);
    expect(scroll.offset, where);
    await go(tester, 'seg-depot');
    await go(tester, 'seg-ahead');
    expect(page(tester), 0);
    expect(scroll.offset, where);
    // asking from elsewhere brings the agent forward
    await go(tester, 'seg-konto');
    BuddyScreen.ask.value = '';
    await rest(tester);
    expect(page(tester), 0);
    expect(on(tester, 'seg-ahead'), isTrue);
    expect(tester.takeException(), isNull);
    await settle(tester);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
