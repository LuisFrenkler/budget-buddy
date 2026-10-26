import 'dart:io';
import 'package:budget_buddy/models/budget.dart';
import 'package:budget_buddy/models/goal.dart';
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/auto_save.dart';
import 'package:budget_buddy/services/cancellation_service.dart';
import 'package:budget_buddy/services/category_rules.dart';
import 'package:budget_buddy/services/contracts.dart';
import 'package:budget_buddy/services/db.dart';
import 'package:budget_buddy/services/forecast_service.dart';
import 'package:budget_buddy/services/hints_service.dart';
import 'package:budget_buddy/services/quick_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

Transaction _tx(String id, int cents, String category, DateTime date, {String? note, bool income = false}) =>
    Transaction(id: id, amountCents: cents, category: category, date: date, isIncome: income, note: note);

void main() {
  group('Month forecast', () {
    final now = DateTime(2026, 10, 21);
    final tx = [
      // salary 2.500 € each month
      for (var m = 7; m <= 10; m++) _tx('s$m', 250000, 'Gehalt', DateTime(2026, m, 1), note: 'Gehalt', income: true),
      // rent 900 € on the 3rd, Netflix 14 € on the 25th
      for (var m = 7; m <= 10; m++) _tx('r$m', 90000, 'Wohnen', DateTime(2026, m, 3), note: 'Miete'),
      for (var m = 7; m <= 9; m++) _tx('n$m', 1400, 'Unterhaltung', DateTime(2026, m, 25), note: 'Netflix'),
      // variable spending this month: 600 €
      _tx('v1', 40000, 'Lebensmittel', DateTime(2026, 10, 10)),
      _tx('v2', 20000, 'Essen & Trinken', DateTime(2026, 10, 18)),
    ];

    test('free money, per day and what is still due', () {
      final f = ForecastService.build(tx, now: now)!;
      expect(f.incomeCents, 250000);
      expect(f.fixedCents, 91400);
      expect(f.spentCents, 60000);
      expect(f.freeCents, 250000 - 91400 - 60000);
      expect(f.daysLeft, 11); // 21.–31. Oct
      expect(f.perDayCents, (250000 - 91400 - 60000) ~/ 11);
      expect(f.due.map((d) => d.name), ['Netflix']);
      expect(f.due.single.date, DateTime(2026, 10, 25));
    });

    test('goals reduce what is free', () {
      final goal = Goal(
          id: 'g', name: 'Urlaub', emoji: '🏖', targetCents: 120000, deadline: DateTime(2027, 4, 21),
          createdAt: DateTime(2026, 1, 1));
      final f = ForecastService.build(tx, goals: [goal], now: now)!;
      expect(f.goalsCents, greaterThan(0));
      expect(f.freeCents, 250000 - 91400 - 60000 - f.goalsCents);
    });

    test('no income history, no forecast', () {
      expect(ForecastService.build([_tx('x', 500, 'Sonstiges', now)], now: now), isNull);
    });

    test('pace: over, tight or relaxed', () {
      final heavy = [...tx, _tx('big', 150000, 'Kleidung', DateTime(2026, 10, 20))];
      expect(ForecastService.build(heavy, now: now)!.pace, ForecastPace.over);
      expect(ForecastService.build(tx, now: now)!.pace, isNot(ForecastPace.over));
    });
  });

  group('Cancellation', () {
    test('the letter has everything a provider needs', () {
      final text = CancellationService.letter(
          provider: 'Netflix', name: 'Luisa Test', email: 'luisa@beispiel.de', customerNo: '123',
          date: DateTime(2026, 10, 21));
      expect(text, contains('An: Netflix'));
      expect(text, contains('21. Oktober 2026'));
      expect(text, contains('Kundennummer 123'));
      expect(text, contains('fristgerecht zum nächstmöglichen Zeitpunkt'));
      expect(text, contains('SEPA-Lastschriftmandat'));
      expect(text.trim().endsWith('Luisa Test'), isTrue);
      expect(CancellationService.subject('Netflix', ''), 'Kündigung');
    });

    test('Buddy notices payments after the cancellation', () {
      final tx = [for (var m = 6; m <= 10; m++) _tx('n$m', 1400, 'Unterhaltung', DateTime(2026, m, 5), note: 'Netflix')];
      final c = Contracts.detect(tx, now: DateTime(2026, 10, 21)).single;
      expect(CancellationService.stillCharging(c, DateTime(2026, 8, 20)), isTrue);
      expect(CancellationService.stillCharging(c, DateTime(2026, 10, 1)), isFalse);
      final hints = HintsService.build(
          tx: tx, budgets: const [], goals: const [], cancellations: {'netflix': DateTime(2026, 8, 20)},
          now: DateTime(2026, 10, 21));
      expect(hints.first.kind, HintKind.stillCharging);
      expect(hints.first.title, 'Netflix bucht trotz Kündigung ab');
    });
  });

  group('Categories that learn', () {
    setUpAll(() async {
      Hive.init(Directory.systemTemp.createTempSync('rules').path);
      for (final b in ['transactions', 'budgets', 'badges', 'holdings', 'recurring', 'settings', 'goals']) {
        await Hive.openBox(b);
      }
    });

    test('moving one booking moves all of the merchant and new ones', () async {
      final a = _tx('a', 1200, 'Sonstiges', DateTime(2026, 10, 1), note: 'Kiosk Müller');
      final b = _tx('b', 800, 'Sonstiges', DateTime(2026, 10, 5), note: 'kiosk müller');
      final c = _tx('c', 500, 'Sonstiges', DateTime(2026, 10, 6), note: 'Bäcker');
      for (final t in [a, b, c]) {
        await DB.addTx(t);
      }
      expect(CategoryRules.others(a, 'Essen & Trinken').map((t) => t.id), ['b']);
      expect(await CategoryRules.applyToAll(a, 'Essen & Trinken'), 1);
      final byId = {for (final t in DB.getTx()) t.id: t.category};
      expect(byId['b'], 'Essen & Trinken');
      expect(byId['c'], 'Sonstiges');
      // the quick entry now knows the merchant
      expect(QuickParser.parse('Kiosk Müller 4,50')!.category, 'Essen & Trinken');
      // but not for income of the same name
      expect(CategoryRules.forName('Kiosk Müller', isIncome: true), isNull);
    });

    test('monthly budgets continue, deleted ones stay deleted, custom ranges do not repeat', () async {
      await DB.addBudget(Budget(
          category: 'Lebensmittel', limitCents: 30000, startDate: DateTime(2026, 9, 1), endDate: DateTime(2026, 9, 30)));
      await DB.addBudget(Budget(
          category: 'Kleidung', limitCents: 10000, startDate: DateTime(2026, 9, 10), endDate: DateTime(2026, 9, 20)));
      expect(await DB.rollOverBudgets(now: DateTime(2026, 11, 3)), 1);
      final nov = DB.getBudgets().where((b) => b.startDate == DateTime(2026, 11, 1)).toList();
      expect(nov.map((b) => b.category), ['Lebensmittel']);
      expect(nov.single.limitCents, 30000);
      expect(nov.single.endDate, DateTime(2026, 11, 30));
      // nothing twice
      expect(await DB.rollOverBudgets(now: DateTime(2026, 11, 20)), 0);
      // deleting this month's budget stops it for good
      await DB.deleteBudget(nov.single);
      expect(await DB.rollOverBudgets(now: DateTime(2026, 12, 2)), 0);
      // a new budget for the category brings it back
      await DB.addBudget(Budget(
          category: 'Lebensmittel', limitCents: 25000, startDate: DateTime(2026, 12, 1), endDate: DateTime(2026, 12, 31)));
      expect(await DB.rollOverBudgets(now: DateTime(2027, 1, 5)), 1);
    });
  });

  group('Saving on autopilot', () {
    Goal goal() => Goal(id: 'g', name: 'Urlaub', emoji: '🏖', targetCents: 10000, createdAt: DateTime(2026, 1, 1));

    test('round-up per booking', () {
      expect(AutoSave.roundUpOf(320), 80);
      expect(AutoSave.roundUpOf(1999), 1);
      expect(AutoSave.roundUpOf(500), 0);
    });

    test('monthly amount once per month, round-ups once per booking, never past the target', () {
      final g = goal()
        ..monthlyCents = 5000
        ..roundUp = true
        ..roundUpSince = DateTime(2026, 10, 10);
      final tx = [
        _tx('old', 310, 'Essen & Trinken', DateTime(2026, 10, 1)), // before switching on
        _tx('a', 320, 'Essen & Trinken', DateTime(2026, 10, 12)),
        _tx('b', 1450, 'Lebensmittel', DateTime(2026, 10, 13)),
        _tx('in', 250000, 'Gehalt', DateTime(2026, 10, 14), income: true),
      ];
      expect(AutoSave.apply(g, tx, DateTime(2026, 10, 20)), 5000 + 80 + 50);
      // again the same day: nothing new
      expect(AutoSave.apply(g, tx, DateTime(2026, 10, 21)), 0);
      // next month: the monthly amount, capped at the target
      expect(AutoSave.apply(g, tx, DateTime(2026, 11, 2)), 10000 - 5130);
      expect(g.reached, isTrue);
      expect(AutoSave.apply(g, tx, DateTime(2026, 12, 2)), 0);
    });

    test('the settings survive saving', () {
      final g = goal()
        ..monthlyCents = 2500
        ..roundUp = true
        ..roundUpSince = DateTime(2026, 10, 10)
        ..roundedIds.add('x');
      final back = Goal.fromMap(Map<String, dynamic>.from(g.toMap()));
      expect(back.monthlyCents, 2500);
      expect(back.roundUp, isTrue);
      expect(back.roundUpSince, DateTime(2026, 10, 10));
      expect(back.roundedIds, ['x']);
      expect(Goal.fromMap({'id': 'o', 'name': 'Alt', 'targetCents': 100, 'createdAt': 0}).automated, isFalse);
    });
  });
}
