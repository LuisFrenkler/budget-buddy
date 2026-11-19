// The refund check, the range, the certificate and the notice: the parts of
// the tax flow that decide what the person sees as their number.
import 'dart:io';

import 'package:budget_buddy/screens/refund_check_screen.dart';
import 'package:budget_buddy/services/product_events.dart';
import 'package:budget_buddy/services/tax_docs.dart';
import 'package:budget_buddy/services/tax_estimate.dart';
import 'package:budget_buddy/services/tax_letters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  final today = DateTime(2026, 11, 17);

  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('tax_flow').path);
    await Hive.openBox('settings');
  });
  setUp(() async {
    await Hive.box('settings').clear();
    ProductEvents.reset();
  });

  test('refund check: every open year from the start, the first one partial, with its deadline', () {
    final years = TaxEstimate.quickCheck(startYear: 2022, startMonth: 9, grossMonth: 3000, today: today);
    expect(years.map((y) => y.year), [2022, 2023, 2024, 2025, 2026]);
    final first = years.first;
    expect(first.deadline, DateTime(2026, 12, 31));
    expect(first.high, greaterThan(800));
    expect(first.low, lessThanOrEqualTo(first.high));
    expect(first.reasons.join(), contains('4 Monate'));
    // the running year cannot be filed yet
    expect(years.last.deadline, isNull);
    // a start before the open years: all of them full years
    final early = TaxEstimate.quickCheck(startYear: 2021, startMonth: 6, grossMonth: 3000, today: today);
    expect(early.first.year, 2022);
    expect(early.first.reasons.join(), isNot(contains('Monate gearbeitet')));
  });

  test('range: the commute widens it, the certificate takes away the guess', () {
    const guess = TaxProfile(grossMonth: 3000, km: 25);
    final b = TaxEstimate.range(guess, year: 2025);
    expect(b.high, greaterThan(b.low));
    final cert = guess.copyWith(grossYear: 36000, withheldYear: TaxEstimate.compute(guess, year: 2025).withheld);
    final c = TaxEstimate.range(cert.copyWith(km: 0), year: 2025);
    expect(c.high - c.low, lessThan(1));
  });

  test('the certificate fills one year and does not leak into the others', () async {
    const doc = TaxDoc(kind: 'lohnsteuerbescheinigung', year: 2023, months: 5, gross: 15000, wageTax: 1200, soli: 0);
    expect(doc.isCertificate, isTrue);
    final p = doc.applyTo(const TaxProfile());
    expect(p.monthsWorked, 5);
    expect(p.grossMonth, 3000);
    expect(p.withheldYear, 1200);
    await TaxEstimate.saveProfile(p, year: 2023);
    expect(TaxEstimate.profile(year: 2023).fromCertificate, isTrue);
    expect(TaxEstimate.profile(year: 2024).fromCertificate, isFalse);
    expect(TaxEstimate.profile(year: 2024).grossMonth, 3000);
    // with the real withheld tax, the refund is that tax minus what the year costs
    final r = TaxEstimate.compute(p, year: 2023);
    expect(r.withheld, 1200);
  });

  test('filed, then the notice: deviation bucket and objection period', () async {
    await TaxEstimate.markFiled(2022, 900, at: DateTime(2026, 11, 20));
    expect(TaxEstimate.filedAt(2022), DateTime(2026, 11, 20));
    const notice = TaxDoc(kind: 'bescheid', year: 2022, refund: 860, werbungskosten: null);
    expect(notice.isAssessment, isFalse, reason: 'no date yet');
    final dated = TaxDoc(kind: 'bescheid', year: 2022, refund: 860, date: DateTime(2027, 1, 27));
    await TaxEstimate.saveAssessment(dated.toAssessment());
    expect(TaxEstimate.assessment(2022)!.refund, 860);
    expect(ProductEvents.log.join(' '), allOf(contains('tax_filed'), contains('assessment'), contains('estimate_within_10')));
    // 27 Jan + 4 days = 31 Jan, + 1 month = end of February
    expect(TaxEstimate.objectionUntil(DateTime(2027, 1, 27)), DateTime(2027, 2, 28));
    expect(TaxEstimate.objectionUntil(DateTime(2026, 3, 10)), DateTime(2026, 4, 14));
    // before 2025 three days
    expect(TaxEstimate.objectionUntil(DateTime(2024, 3, 10)), DateTime(2024, 4, 13));
    expect(TaxEstimate.accuracyEvent(900, 600), ProductEvents.estimateOff);
    expect(TaxEstimate.accuracyEvent(900, 760), ProductEvents.estimateWithin25);
  });

  test('a back payment counts as a negative refund', () {
    final a = TaxDoc(kind: 'bescheid', year: 2024, backPayment: 120, date: DateTime(2025, 6, 1)).toAssessment();
    expect(a.refund, -120);
  });

  test('letters stay German and carry the year and the amounts', () {
    final req = TaxLetters.employerRequest(year: 2022, name: 'Mia', date: DateTime(2026, 11, 17));
    expect(req, allOf(contains('17.11.2026'), contains('Lohnsteuerbescheinigung 2022'), endsWith('Mia')));
    final obj = TaxLetters.objection(
        year: 2022, noticeDate: DateTime(2027, 1, 27), claimed: 2106.5, accepted: 1200, date: DateTime(2027, 2, 2));
    expect(obj, allOf(contains('vom 27.01.2027'), contains('2.106,50 €'), contains('1.200,00 €')));
  });

  test('after sign-up the refund check becomes the open years, once', () async {
    await Hive.box('settings').put('refundCheck', {'startYear': 2022, 'startMonth': 9, 'grossMonth': 3000.0, 'km': 12.0});
    await TaxEstimate.saveProfile(const TaxProfile(grossMonth: 4100), year: 2024); // own answers stay
    final year = await TaxEstimate.adoptRefundCheck(now: today);
    expect(year, 2022);
    expect(TaxEstimate.profile(year: 2022).monthsWorked, 4);
    expect(TaxEstimate.profile(year: 2022).km, 12);
    expect(TaxEstimate.profile(year: 2023).monthsWorked, 12);
    expect(TaxEstimate.profile(year: 2024).grossMonth, 4100);
    expect(Hive.box('settings').get('refundCheck'), isNull);
    expect(await TaxEstimate.adoptRefundCheck(now: today), isNull);
  });

  test('the notice is also scored against the three-answer estimate', () async {
    const p = TaxProfile(grossMonth: 3000, monthsWorked: 4, km: 20);
    final control = TaxEstimate.controlEstimate(p.copyWith(grossYear: 12000, withheldYear: 900), 2022);
    expect(control, closeTo(TaxEstimate.compute(p, year: 2022).refund, 0.01));
    await TaxEstimate.markFiled(2022, 900, control: 500, at: DateTime(2026, 11, 20));
    await TaxEstimate.saveAssessment(Assessment(year: 2022, refund: 880, date: DateTime(2027, 1, 27)));
    expect(ProductEvents.log.join(' '), allOf(contains('estimate_within_10'), contains('control_off')));
  });

  // last: the widget clock leaves file writes behind for later tests
  testWidgets('refund check screen: three answers, a range per open year, no sign-up needed', (tester) async {
    await tester.pumpWidget(MaterialApp(home: RefundCheckScreen(now: today)));
    // one question per page: the start of work, the gross pay, the way to work
    await tester.tap(find.byKey(const Key('refund-step-next')));
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byKey(const Key('refund-step-next'))).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('refund-gross')), '3000');
    await tester.pump();
    await tester.tap(find.byKey(const Key('refund-step-next')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('refund-check')));
    await tester.pumpAndSettle();
    expect(find.text('2025'), findsOneWidget); // the card of the start year
    expect(find.textContaining('Abgabe bis'), findsWidgets);
    await tester.scrollUntilVisible(find.byKey(const Key('refund-next')), 300, scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const Key('refund-next')), findsOneWidget);
    // the box writes real files: let them finish outside the fake clock
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    expect(RefundCheckScreen.saved()?['grossMonth'], 3000);
    expect(ProductEvents.log.join(), contains('refund_check'));
  });
}
