import 'package:budget_buddy/models/goal.dart';
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/utils/password.dart';
import 'package:budget_buddy/services/notification_service.dart';
import 'package:budget_buddy/services/plus_service.dart';
import 'package:budget_buddy/services/weekly_report.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _tx(String id, int cents, String category, DateTime date, {String? note, bool income = false}) =>
    Transaction(id: id, amountCents: cents, category: category, date: date, isIncome: income, note: note);

void main() {
  group('Weekly report', () {
    test('which week is reported', () {
      // Wednesday: last week
      expect(WeeklyReportService.reportWeek(DateTime(2026, 10, 21, 12)), DateTime(2026, 10, 12));
      // Sunday before 18:00 still last week, after 18:00 this week
      expect(WeeklyReportService.reportWeek(DateTime(2026, 10, 25, 17)), DateTime(2026, 10, 12));
      expect(WeeklyReportService.reportWeek(DateTime(2026, 10, 25, 18)), DateTime(2026, 10, 19));
      expect(WeeklyReportService.nextReady(DateTime(2026, 10, 21)), DateTime(2026, 10, 25, 18));
      expect(WeeklyReportService.nextReady(DateTime(2026, 10, 25, 19)), DateTime(2026, 11, 1, 18));
    });

    test('compares with the usual week and finds the jump', () {
      final tx = <Transaction>[];
      // four usual weeks: 50 € groceries, 20 € going out
      for (var w = 1; w <= 4; w++) {
        final monday = DateTime(2026, 10, 12 - 7 * w);
        tx.add(_tx('g$w', 5000, 'Lebensmittel', monday));
        tx.add(_tx('o$w', 2000, 'Ausgehen', monday.add(const Duration(days: 4))));
      }
      // report week (12.–18. Oct): groceries as usual, going out much higher
      tx.addAll([
        _tx('a', 5000, 'Lebensmittel', DateTime(2026, 10, 12)),
        _tx('b', 3000, 'Ausgehen', DateTime(2026, 10, 16)),
        _tx('c', 4000, 'Ausgehen', DateTime(2026, 10, 17), note: 'Konzert'),
        _tx('d', 250000, 'Gehalt', DateTime(2026, 10, 15), income: true),
      ]);
      final r = WeeklyReportService.build(tx, now: DateTime(2026, 10, 21))!;
      expect(r.start, DateTime(2026, 10, 12));
      expect(r.week, 42);
      expect(r.spentCents, 12000);
      expect(r.incomeCents, 250000);
      expect(r.usualCents, 7000);
      expect(r.change, closeTo(5 / 7, 0.001));
      expect(r.headline, 'Eine teure Woche');
      expect(r.categories.first.category, 'Ausgehen');
      expect(r.perDay[0], 5000);
      expect(r.topDay, 0); // Monday: the 50 € shop
      expect(r.noSpendDays, 4);
      expect(r.biggest!.amountCents, 5000);
      expect(r.tip, startsWith('Ausgehen lag 50,00'));
    });

    test('rent and subscriptions are left out', () {
      final tx = [
        for (var m = 7; m <= 10; m++) _tx('rent$m', 85000, 'Miete', DateTime(2026, m, 13), note: 'Miete'),
        _tx('food', 4000, 'Lebensmittel', DateTime(2026, 10, 14)),
      ];
      final r = WeeklyReportService.build(tx, now: DateTime(2026, 10, 21))!;
      expect(r.spentCents, 4000);
      expect(r.categories.map((c) => c.category), ['Lebensmittel']);
    });

    test('no expenses, no report', () {
      expect(WeeklyReportService.build(const [], now: DateTime(2026, 10, 21)), isNull);
    });

    test('a small swing is still a normal week, without a ±% badge', () {
      final tx = <Transaction>[];
      for (var w = 1; w <= 4; w++) {
        final monday = DateTime(2026, 10, 12 - 7 * w);
        tx.add(_tx('u$w', 10000, 'Lebensmittel', monday));
      }
      // 4 % over usual → headline "normale Woche", not a red +4 %
      tx.add(_tx('a', 10400, 'Lebensmittel', DateTime(2026, 10, 12)));
      final r = WeeklyReportService.build(tx, now: DateTime(2026, 10, 21))!;
      expect(r.usualCents, 10000);
      expect(r.roughlyUsual, isTrue);
      expect(r.headline, 'Eine ganz normale Woche');
    });
  });

  group('Reminder plan', () {
    test('weekly, payment, trial, bank and goal reminders', () {
      final now = DateTime(2026, 10, 21, 12);
      final tx = [for (var m = 7; m <= 10; m++) _tx('r$m', 85000, 'Miete', DateTime(2026, m, 1), note: 'Miete')];
      final sub = Subscription(
          plan: PlusPlan.monthly,
          method: PayMethod.paypal,
          methodDetail: '',
          started: DateTime(2026, 10, 20),
          trialEnds: DateTime(2026, 10, 27));
      final goal = Goal(
          id: 'g', name: 'Urlaub', emoji: '🏖', targetCents: 100000, deadline: DateTime(2026, 11, 20),
          createdAt: DateTime(2026, 1, 1));
      final plan = NotificationService.plan(
          tx: tx, goals: [goal], subscription: sub, bankValidUntil: DateTime(2026, 11, 5), now: now);
      final byPayload = {for (final r in plan) r.payload: r};
      expect(byPayload['weekly']!.when, DateTime(2026, 10, 25, 18));
      expect(byPayload['subscription']!.when, DateTime(2026, 10, 25, 10));
      expect(byPayload['contracts']!.when, DateTime(2026, 10, 31, 9));
      expect(byPayload['contracts']!.title, 'Morgen: Miete');
      expect(byPayload['connections']!.when, DateTime(2026, 11, 2, 10));
      expect(byPayload['goals']!.when, DateTime(2026, 11, 13, 10));
      // in time order, all in the future
      expect(plan.map((r) => r.when).toList(), [...plan.map((r) => r.when)]..sort());
      expect(plan.every((r) => r.when.isAfter(now)), isTrue);
    });

    test('nothing for a cancelled trial or past dates', () {
      final now = DateTime(2026, 10, 21);
      final sub = Subscription(
          plan: PlusPlan.monthly,
          method: PayMethod.card,
          methodDetail: '',
          started: DateTime(2026, 10, 20),
          trialEnds: DateTime(2026, 10, 27),
          endsAt: DateTime(2026, 10, 27));
      final plan = NotificationService.plan(
          tx: const [], goals: const [], subscription: sub, bankValidUntil: DateTime(2026, 10, 22), now: now);
      expect(plan.map((r) => r.payload), ['weekly']);
    });
  });

  test('password strength', () {
    expect(passwordStrength('kurz').$1, 0);
    expect(passwordStrength('abcdefgh').$1, 1);
    expect(passwordStrength('Abcdefg1').$1, 2);
    expect(passwordStrength('Abcdefgh1234').$1, 3);
    expect(passwordStrength('Abcdefgh123!').$2, 'Stark');
  });

  test('withdrawal only in the first 14 days', () {
    final sub = Subscription(
        plan: PlusPlan.yearly,
        method: PayMethod.card,
        methodDetail: '',
        started: DateTime(2026, 10, 1),
        trialEnds: DateTime(2026, 10, 8));
    expect(PlusService.canWithdraw(sub, now: DateTime(2026, 10, 14)), isTrue);
    expect(PlusService.canWithdraw(sub, now: DateTime(2026, 10, 16)), isFalse);
  });
}
