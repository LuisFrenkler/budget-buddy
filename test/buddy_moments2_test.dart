import 'dart:io';

import 'package:budget_buddy/models/budget.dart';
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/buddy_help.dart';
import 'package:budget_buddy/services/hints_service.dart';
import 'package:budget_buddy/services/tax_estimate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

Transaction _salary(String id, int cents, DateTime d) =>
    Transaction(id: id, amountCents: cents, category: 'Gehalt', date: d, isIncome: true, note: 'Gehalt');
Transaction _spend(String id, int cents, String cat, DateTime d) =>
    Transaction(id: id, amountCents: cents, category: cat, date: d, isIncome: false, note: 'x');

void main() {
  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('moments2').path);
    await Hive.openBox('settings');
  });
  setUp(() => Hive.box('settings').clear());

  final now = DateTime(2026, 11, 3);
  Budget budget(String cat, int limit) => Budget(
      category: cat, limitCents: limit, startDate: DateTime(2026, 11, 1), endDate: DateTime(2026, 11, 30));

  test('a raise: half of it as the savings suggestion', () {
    final tx = [
      for (final m in [7, 8, 9]) _salary('s$m', 240000, DateTime(2026, m, 28)),
      _salary('s10', 258000, DateTime(2026, 10, 28)),
    ];
    final r = HintsService.salaryRaise(tx, now: now)!;
    expect(r.raiseCents, 18000);
    final h = HintsService.build(tx: tx, budgets: const [], goals: const [], now: now)
        .firstWhere((h) => h.kind == HintKind.salaryUp);
    expect(h.title, contains('180,00'));
    expect(h.text, contains('90,00'));
  });

  test('a bonus month or a tiny change is not a raise', () {
    final base = [for (final m in [7, 8, 9]) _salary('s$m', 240000, DateTime(2026, m, 28))];
    expect(HintsService.salaryRaise([...base, _salary('b', 480000, DateTime(2026, 10, 28))], now: now), isNull);
    expect(HintsService.salaryRaise([...base, _salary('t', 242000, DateTime(2026, 10, 28))], now: now), isNull);
  });

  test('a budget over for three months gets a realistic one', () {
    final tx = [
      _spend('a', 31000, 'Lebensmittel', DateTime(2026, 8, 10)),
      _spend('b', 34000, 'Lebensmittel', DateTime(2026, 9, 10)),
      _spend('c', 36500, 'Lebensmittel', DateTime(2026, 10, 10)),
    ];
    final fit = HintsService.realisticBudget(tx, 'Lebensmittel', 25000, now: now)!;
    // the middle month 340 €, minus 5 %, up to 10 €: 330 €
    expect(fit.suggestCents, 33000);
    final h = HintsService.build(tx: tx, budgets: [budget('Lebensmittel', 25000)], goals: const [], now: now)
        .firstWhere((h) => h.kind == HintKind.budgetUnreal);
    expect(h.text, contains('330,00'));
    // one good month in between: no hint
    final ok = [...tx]..[1] = _spend('b', 24000, 'Lebensmittel', DateTime(2026, 9, 10));
    expect(HintsService.realisticBudget(ok, 'Lebensmittel', 25000, now: now), isNull);
  });

  test('February: the tax return, from the profile or from a short first year', () async {
    final feb = DateTime(2027, 2, 10);
    final firstYear = [for (final m in [9, 10, 11, 12]) _salary('s$m', 240000, DateTime(2026, m, 28))];
    var h = HintsService.build(tx: firstYear, budgets: const [], goals: const [], now: feb)
        .where((h) => h.kind == HintKind.taxReturn);
    expect(h.single.text, contains('4 Monate'));
    await TaxEstimate.saveProfile(const TaxProfile(grossMonth: 3500, monthsWorked: 4));
    h = HintsService.build(tx: firstYear, budgets: const [], goals: const [], now: feb).where((h) => h.kind == HintKind.taxReturn);
    expect(h.single.text, contains('zurück'));
    expect(HintsService.build(tx: firstYear, budgets: const [], goals: const [], now: DateTime(2027, 9, 1))
        .where((h) => h.kind == HintKind.taxReturn), isEmpty);
  });

  test('"Was kannst du alles?" is answered on the device', () {
    expect(BuddyHelp.matches('Was kannst du alles?'), isTrue);
    expect(BuddyHelp.matches('what can you do'), isTrue);
    expect(BuddyHelp.matches('Was kann ich alles mit dir machen?'), isTrue);
    expect(BuddyHelp.matches('Was kann Ahead?'), isTrue);
    expect(BuddyHelp.matches('Was kannst du mir zum Thema ETF sagen?'), isFalse);
    final a = BuddyHelp.answer();
    expect(a.text, contains('Nächster Schritt:'));
    expect(a.chips.length, 3);
    expect(BuddyHelp.answer(guest: true).text, contains('kostenlosen Konto'));
  });
}
