import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:budget_buddy/models/goal.dart';
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/goals_service.dart';
import 'package:budget_buddy/services/plus_service.dart';
import 'package:budget_buddy/services/recap_service.dart';

Transaction _t(String note, String cat, int cents, DateTime d, {bool income = false}) =>
    Transaction(id: '$note$d$cents', amountCents: cents, category: cat, date: d, isIncome: income, note: note);

void main() {
  final now = DateTime(2026, 10, 25);

  group('Goal plan', () {
    Goal goal(int target, {int saved = 0, DateTime? by}) => Goal(
        id: 'g', name: 'Urlaub', emoji: '🏖️', targetCents: target, savedCents: saved, deadline: by, createdAt: now);

    test('monthly amount to reach the deadline', () {
      final g = goal(120000, saved: 20000, by: DateTime(2027, 4, 1));
      expect(g.monthsLeft(now), 6);
      expect(g.monthlyNeeded(now), 16667);
    });

    test('fits comfortably, tight, or not at all', () {
      final g = goal(120000, by: DateTime(2027, 4, 1)); // 200 € a month
      expect(GoalsService.plan(g, avgSurplusCents: 50000, now: now).onTrack, isTrue);
      expect(GoalsService.plan(g, avgSurplusCents: 25000, now: now).text, contains('knapp'));
      expect(GoalsService.plan(g, avgSurplusCents: 10000, now: now).onTrack, isFalse);
    });

    test('without a date it suggests half of the surplus', () {
      final p = GoalsService.plan(goal(60000), avgSurplusCents: 40000, now: now);
      expect(p.text, contains('3 Monaten'));
    });

    test('on autopilot the plan is the amount the user set up', () {
      final g = goal(60000)..monthlyCents = 15000;
      expect(GoalsService.plan(g, avgSurplusCents: 40000, now: now).text, contains('in 4 Monaten'));
      // not enough for the date: said plainly
      final tight = goal(120000, by: DateTime(2027, 4, 1))..monthlyCents = 10000;
      final p = GoalsService.plan(tight, avgSurplusCents: 90000, now: now);
      expect(p.onTrack, isFalse);
      expect(p.text, contains('knapp'));
    });

    test('a date in the past is named, not treated as one month left', () {
      final p = GoalsService.plan(goal(120000, saved: 30000, by: DateTime(2026, 8, 1)), avgSurplusCents: 90000, now: now);
      expect(p.onTrack, isFalse);
      expect(p.text, contains('vorbei'));
    });
  });

  group('Recap', () {
    final tx = [
      _t('Gehalt', 'Gehalt', 300000, DateTime(2026, 9, 1), income: true),
      _t('REWE', 'Lebensmittel', 4000, DateTime(2026, 9, 3)),
      _t('REWE', 'Lebensmittel', 6000, DateTime(2026, 9, 10)),
      _t('Miete', 'Wohnen', 90000, DateTime(2026, 9, 3)),
      _t('Kino', 'Unterhaltung', 2000, DateTime(2026, 9, 20)),
      _t('Miete', 'Wohnen', 90000, DateTime(2026, 8, 3)),
    ];

    test('numbers for the month', () {
      final r = RecapService.build(tx, DateTime(2026, 9))!;
      expect(r.expenses, 102000);
      expect(r.savingsRate, 66);
      expect(r.topCategory, 'Wohnen');
      expect(r.topMerchant, 'REWE');
      expect(r.topMerchantVisits, 2);
      expect(r.expenseChange, 13);
      expect(r.priciestDay, DateTime(2026, 9, 3));
    });

    test('no bookings, no recap; recap month is the last complete one', () {
      expect(RecapService.build(tx, DateTime(2026, 7)), isNull);
      expect(RecapService.recapMonth(DateTime(2026, 1, 5)), DateTime(2025, 12));
    });
  });

  group('Plus limits', () {
    setUpAll(() async {
      Hive.init(Directory.systemTemp.createTempSync('plus').path);
      await Hive.openBox('settings');
    });

    test('free tier counts per month, Plus has no limits', () async {
      expect(PlusService.allowed(PlusFeature.aiQuestion, now: now), isTrue);
      for (int i = 0; i < PlusService.freeAiQuestions; i++) {
        await PlusService.count(PlusFeature.aiQuestion, now: now);
      }
      expect(PlusService.allowed(PlusFeature.aiQuestion, now: now), isFalse);
      // a new month starts fresh
      expect(PlusService.allowed(PlusFeature.aiQuestion, now: DateTime(2026, 11, 1)), isTrue);
      expect(PlusService.allowed(PlusFeature.goal, current: 1), isFalse);

      await PlusService.activateTest();
      expect(PlusService.allowed(PlusFeature.aiQuestion, now: now), isTrue);
      expect(PlusService.allowed(PlusFeature.goal, current: 5), isTrue);
      await PlusService.cancelTest();
    });
  });

  group('Plus subscription', () {
    setUpAll(() async {
      Hive.init(Directory.systemTemp.createTempSync('sub').path);
      await Hive.openBox('settings');
    });

    test('trial, invoices, cancel and resume', () async {
      final start = DateTime(2026, 1, 10);
      final sub = await PlusService.start(plan: PlusPlan.monthly, method: PayMethod.sepa, now: start);
      expect(PlusService.active.value, isTrue);
      expect(sub.trialEnds, DateTime(2026, 1, 17));
      expect(sub.inTrial(DateTime(2026, 1, 15)), isTrue);
      expect(sub.invoices(DateTime(2026, 1, 15)), isEmpty);

      // two payments by mid March: 17 Jan and 17 Feb
      final march = DateTime(2026, 3, 1);
      expect(sub.invoices(march).length, 2);
      expect(sub.periodEnd(march), DateTime(2026, 3, 17));

      await PlusService.cancel(now: march);
      final cancelled = PlusService.subscription.value!;
      expect(cancelled.endsAt, DateTime(2026, 3, 17));
      expect(cancelled.activeAt(DateTime(2026, 3, 16)), isTrue);
      expect(cancelled.activeAt(DateTime(2026, 3, 18)), isFalse);
      // no charge on the day it ends
      expect(cancelled.invoices(DateTime(2026, 4, 1)).length, 2);

      await PlusService.resume();
      expect(PlusService.subscription.value!.cancelled, isFalse);

      // a run-out cancellation is dropped on load
      await PlusService.cancel(now: march);
      PlusService.load(now: DateTime(2026, 4, 1));
      expect(PlusService.active.value, isFalse);
    });

    test('a period ending on the 31st stays on the month\'s end, no drift to the 3rd', () {
      final sub = Subscription(
          plan: PlusPlan.monthly, method: PayMethod.card, methodDetail: '',
          started: DateTime(2026, 1, 24), trialEnds: DateTime(2026, 1, 31));
      expect(sub.periodEnd(DateTime(2026, 2, 1)), DateTime(2026, 2, 28));
      expect(sub.periodEnd(DateTime(2026, 3, 1)), DateTime(2026, 3, 31));
      expect(sub.invoices(DateTime(2026, 4, 1)).map((i) => i.date),
          [DateTime(2026, 3, 31), DateTime(2026, 2, 28), DateTime(2026, 1, 31)]);
    });

    test('the server\'s period end wins over the calculation', () {
      final sub = Subscription.fromServer({
        'plan': 'monthly',
        'method': 'card',
        'started': '2026-01-10T00:00:00.000',
        'trialEnds': '2026-01-17T00:00:00.000',
        'periodEnd': '2026-03-20T00:00:00.000',
        'cancelAtPeriodEnd': false,
      });
      expect(sub.periodEnd(DateTime(2026, 3, 1)), DateTime(2026, 3, 20));
      expect(Subscription.fromMap(sub.toMap()).serverPeriodEnd, DateTime(2026, 3, 20));
    });

    test('promo codes add free days', () async {
      expect(PlusService.promoDays('freund'), 30);
      expect(PlusService.promoDays('NOPE'), isNull);
      final now = DateTime(2026, 5, 1);
      await PlusService.start(plan: PlusPlan.yearly, method: PayMethod.paypal, now: now, extraDays: 14);
      expect(PlusService.subscription.value!.trialEnds, DateTime(2026, 5, 22));
      expect(await PlusService.redeem('BUDDY30', now: now), isTrue);
      expect(PlusService.subscription.value!.trialEnds, DateTime(2026, 6, 21));
      await PlusService.end();
    });
  });

  group('Payment checks', () {
    test('cards', () {
      expect(PaymentChecks.cardNumber('4242 4242 4242 4242'), isTrue);
      expect(PaymentChecks.cardNumber('4242 4242 4242 4241'), isFalse);
      expect(PaymentChecks.cardBrand('5555 5555 5555 4444'), 'Mastercard');
      expect(PaymentChecks.cardBrand('3782 822463 10005'), 'Amex');
      final now = DateTime(2026, 10, 25);
      expect(PaymentChecks.expiry('10/26', now: now), isTrue);
      expect(PaymentChecks.expiry('09/26', now: now), isFalse);
      expect(PaymentChecks.expiry('13/28', now: now), isFalse);
      expect(PaymentChecks.cvc('123'), isTrue);
      expect(PaymentChecks.cvc('12'), isFalse);
    });

    test('IBAN and e-mail', () {
      expect(PaymentChecks.iban('DE89 3704 0044 0532 0130 00'), isTrue);
      expect(PaymentChecks.iban('DE89 3704 0044 0532 0130 01'), isFalse);
      expect(PaymentChecks.iban('GB82 WEST 1234 5698 7654 32'), isTrue);
      expect(PaymentChecks.maskIban('DE89 3704 0044 0532 0130 00'), 'DE89 •••• 3000');
      expect(PaymentChecks.email('luis@beispiel.de'), isTrue);
      expect(PaymentChecks.email('luis@'), isFalse);
    });
  });
}
