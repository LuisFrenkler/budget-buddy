import 'dart:io';
import 'package:budget_buddy/models/budget.dart';
import 'package:budget_buddy/models/goal.dart';
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/hints_service.dart';
import 'package:budget_buddy/services/plus_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

Transaction _tx(String id, int cents, String category, DateTime date, {String? note}) =>
    Transaction(id: id, amountCents: cents, category: category, date: date, isIncome: false, note: note);

void main() {
  final now = DateTime(2026, 10, 20);

  test('budget close and over', () {
    final hints = HintsService.build(
      tx: const [],
      budgets: [
        Budget(category: 'Essen', limitCents: 10000, spentCents: 9000,
            startDate: DateTime(2026, 10, 1), endDate: DateTime(2026, 10, 31)),
        Budget(category: 'Kino', limitCents: 5000, spentCents: 6000,
            startDate: DateTime(2026, 10, 1), endDate: DateTime(2026, 10, 31)),
        Budget(category: 'Ok', limitCents: 5000, spentCents: 1000,
            startDate: DateTime(2026, 10, 1), endDate: DateTime(2026, 10, 31)),
      ],
      goals: const [],
      now: now,
    );
    expect(hints.map((h) => h.kind), [HintKind.budgetOver, HintKind.budgetClose]);
    expect(hints.last.text, contains('11 Tage'));
  });

  test('contract price rise and upcoming payment', () {
    final tx = [
      for (var m = 6; m <= 10; m++)
        _tx('m$m', m == 10 ? 1399 : 1299, 'Abos', DateTime(2026, m, 2), note: 'Netflix'),
      for (var m = 7; m <= 9; m++) _tx('r$m', 85000, 'Miete', DateTime(2026, m, 22), note: 'Miete'),
    ];
    final hints = HintsService.build(tx: tx, budgets: const [], goals: const [], now: now);
    final kinds = hints.map((h) => h.kind).toSet();
    expect(kinds, containsAll([HintKind.priceUp]));
    final rise = hints.firstWhere((h) => h.kind == HintKind.priceUp);
    expect(rise.title, 'Netflix ist teurer geworden');
  });

  test('unusual expense, trial end, bank expiry, goal due', () {
    final tx = [
      for (var i = 0; i < 6; i++) _tx('e$i', 2000, 'Shopping', DateTime(2026, 9, i + 1)),
      _tx('big', 25000, 'Shopping', DateTime(2026, 10, 19), note: 'Sneaker'),
    ];
    final sub = Subscription(
        plan: PlusPlan.yearly,
        method: PayMethod.card,
        methodDetail: '',
        started: DateTime(2026, 10, 14),
        trialEnds: DateTime(2026, 10, 21));
    final goal = Goal(
        id: 'g', name: 'Urlaub', emoji: '🏖', targetCents: 100000, savedCents: 40000,
        deadline: DateTime(2026, 11, 10), createdAt: DateTime(2026, 1, 1));
    final hints = HintsService.build(
        tx: tx, budgets: const [], goals: [goal], subscription: sub,
        bankValidUntil: DateTime(2026, 10, 25), now: now);
    final kinds = hints.map((h) => h.kind).toList();
    expect(kinds, containsAll([HintKind.bigExpense, HintKind.trialEnds, HintKind.bankExpires, HintKind.goalDue]));
    expect(hints.first.urgent, isTrue);
    expect(hints.firstWhere((h) => h.kind == HintKind.trialEnds).title, 'Dein Gratis-Test endet morgen');
  });

  test('dismissed hints stay away', () async {
    Hive.init(Directory.systemTemp.createTempSync('hints').path);
    await Hive.openBox('settings');
    final budgets = [
      Budget(category: 'Kino', limitCents: 5000, spentCents: 6000,
          startDate: DateTime(2026, 10, 1), endDate: DateTime(2026, 10, 31)),
    ];
    final first = HintsService.current(tx: const [], budgets: budgets, goals: const [], now: now);
    expect(first, hasLength(1));
    await HintsService.dismiss(first.single.id);
    expect(HintsService.current(tx: const [], budgets: budgets, goals: const [], now: now), isEmpty);
    // next month it is a new situation
    final nov = [
      Budget(category: 'Kino', limitCents: 5000, spentCents: 6000,
          startDate: DateTime(2026, 11, 1), endDate: DateTime(2026, 11, 30)),
    ];
    expect(HintsService.current(tx: const [], budgets: nov, goals: const [], now: DateTime(2026, 11, 20)), hasLength(1));
  });
}
