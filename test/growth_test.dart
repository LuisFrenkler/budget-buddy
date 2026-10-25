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
}
