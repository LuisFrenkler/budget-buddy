// Before sign-up: the tax way on the start opens the refund check, the check asks one
// question per page, and the yes after it leads to the tax page without an
// account. The answers stay on the device and do not outlive a sign-in.

import 'package:budget_buddy/screens/buddy_screen.dart';
import 'package:budget_buddy/screens/refund_check_screen.dart';
import 'package:budget_buddy/screens/tax_screen.dart';
import 'package:budget_buddy/services/account_isolation.dart';
import 'package:budget_buddy/services/product_events.dart';
import 'package:budget_buddy/services/tax_estimate.dart';
import 'package:budget_buddy/utils/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  final today = DateTime(2026, 11, 17);
  Box settings() => Hive.box('settings');

  setUpAll(() async {
    // the real font: the test font's square glyphs make every line far too wide
    final inter = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
    }
    await inter.load();
    // in memory: no file write has to finish outside the widget test's clock
    for (final name in ['transactions', 'settings', 'recurring', 'badges', 'budgets', 'holdings', 'goals', 'splits']) {
      await Hive.openBox(name, bytes: Uint8List(0));
    }
  });
  setUp(() async {
    await settings().clear();
    ProductEvents.reset();
  });

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(780, 1688); // 390 x 844, an iPhone
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

  // the app's own timers (the server check, debounces) run out first
  Future<void> settle(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  }

  Future<void> answer(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('refund-step-next')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('refund-gross')), '3000');
    await tester.pump();
    await tester.tap(find.byKey(const Key('refund-step-next')));
    await tester.pump();
  }

  testWidgets('the tax way on the start opens the check, not the registration', (tester) async {
    await pump(tester, const BuddyScreen(guest: true));
    await tester.tap(find.byKey(const Key('guest-refund-check')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(RefundCheckScreen), findsOneWidget);
    expect(find.byKey(const Key('refund-month')), findsOneWidget);
    await settle(tester);
  });

  testWidgets('the check: one question per page, back one step, the result on its own page', (tester) async {
    await pump(tester, RefundCheckScreen(now: today, source: 'start'));
    expect(find.byKey(const Key('refund-steps')), findsOneWidget);
    expect(find.byKey(const Key('refund-gross')), findsNothing);
    await tester.tap(find.byKey(const Key('refund-step-next')));
    await tester.pump();
    // no gross pay, no next question
    expect(find.byKey(const Key('refund-month')), findsNothing);
    expect(tester.widget<FilledButton>(find.byKey(const Key('refund-step-next'))).onPressed, isNull);
    // text fields below 16 px make mobile browsers zoom in
    expect(tester.widget<TextField>(find.byKey(const Key('refund-gross'))).style!.fontSize, greaterThanOrEqualTo(16));
    await tester.enterText(find.byKey(const Key('refund-gross')), '3000');
    await tester.pump();
    await tester.tap(find.byKey(const Key('refund-step-next')));
    await tester.pump();
    expect(find.byKey(const Key('refund-km')), findsOneWidget);
    // back is the question before, with its answer still there
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byKey(const Key('refund-km')), findsNothing);
    expect(find.text('3000'), findsOneWidget);
    await tester.tap(find.byKey(const Key('refund-step-next')));
    await tester.pump();
    // the way to work can be left out
    await tester.tap(find.byKey(const Key('refund-skip')));
    await tester.pump();
    expect(find.byKey(const Key('refund-steps')), findsNothing);
    expect(find.text('2025'), findsOneWidget); // the year's card; the picker is a page back
    expect(find.textContaining('Abgabe bis'), findsWidgets);
    expect(RefundCheckScreen.saved(), {'startYear': 2025, 'startMonth': 1, 'grossMonth': 3000.0, 'km': 0.0});
    expect(ProductEvents.log.join(' '), allOf(contains('refund_check'), contains('refund_check_start')));
  });

  testWidgets('a guest says "Ja, los": the tax page opens with the answers saved, a sign-in wipes them', (tester) async {
    await pump(tester, RefundCheckScreen(now: today, source: 'start'));
    await answer(tester);
    await tester.enterText(find.byKey(const Key('refund-km')), '12');
    await tester.tap(find.byKey(const Key('refund-check')));
    await tester.pump();
    await tester.scrollUntilVisible(find.byKey(const Key('refund-next')), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Ja, los'), findsOneWidget);
    expect(find.byKey(const Key('refund-signup')), findsOneWidget); // the account stays an offer
    await tester.tap(find.byKey(const Key('refund-next')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(TaxScreen), findsOneWidget);
    expect(tester.widget<TaxScreen>(find.byType(TaxScreen)).year, 2025);
    expect(TaxEstimate.profile(year: 2025).grossMonth, 3000);
    expect(TaxEstimate.profile(year: 2025).km, 12);
    expect(settings().get('taxProfile:2024'), isNull); // not worked yet
    expect(RefundCheckScreen.saved(), isNotNull);
    await settle(tester);

    // every sign-in starts with this wipe: another account never sees the guest's years
    await AccountIsolation.wipeLocalFinance();
    expect(settings().keys.where((k) => '$k'.startsWith('taxProfile')), isEmpty);
    // the check itself stays, so the guest's own new account gets its answers back
    expect(await TaxEstimate.adoptRefundCheck(now: today), 2025);
    expect(TaxEstimate.profile(year: 2025).km, 12);
  });

  testWidgets('guest start: each find is a card with its yes, the headline in whole euros', (tester) async {
    final year = DateTime.now().year - 2;
    await settings().put('refundCheck', {'startYear': year, 'startMonth': 9, 'grossMonth': 3000.0, 'km': 20.0});
    await pump(tester, const BuddyScreen(guest: true));
    expect(tester.widget<Text>(find.byKey(const Key('guest-found'))).data, isNot(contains(',')));
    expect(find.byKey(Key('guest-find-tax-$year')), findsOneWidget);
    expect(find.byKey(const Key('guest-carry-on')), findsOneWidget);
    expect(find.byKey(const Key('guest-recheck')), findsOneWidget);
    // years the check filled, then answered on the tax page, keep those answers
    await TaxEstimate.saveProfile(const TaxProfile(grossMonth: 4100), year: year + 1);
    await tester.ensureVisible(find.byKey(Key('guest-go-tax-$year')));
    await tester.tap(find.byKey(Key('guest-go-tax-$year')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.widget<TaxScreen>(find.byType(TaxScreen)).year, year);
    expect(TaxEstimate.profile(year: year).monthsWorked, 4);
    expect(TaxEstimate.profile(year: year).km, 20);
    expect(TaxEstimate.profile(year: year + 1).grossMonth, 4100);
    expect(RefundCheckScreen.saved(), isNotNull);
    expect(ProductEvents.log.join(' '), contains('find_yes_tax'));
    await settle(tester);
  });
}
