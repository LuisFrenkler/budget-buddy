import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:budget_buddy/models/budget.dart';
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/categorizer.dart';
import 'package:budget_buddy/services/db.dart';
import 'package:budget_buddy/services/forecast_service.dart';
import 'package:budget_buddy/services/recap_service.dart';

Transaction _t(String id, int cents, String category, DateTime date, {bool income = false, String? note}) =>
    Transaction(id: id, amountCents: cents, category: category, date: date, isIncome: income, note: note);

void main() {
  final now = DateTime(2026, 10, 21);
  final tx = [
    for (var m = 7; m <= 10; m++) _t('s$m', 250000, 'Gehalt', DateTime(2026, m, 1), income: true, note: 'Gehalt'),
    _t('shoes', 12000, 'Kleidung', DateTime(2026, 10, 3), note: 'Zalando'),
    // the shoes went back: 80 € returned
    _t('return', 8000, 'Kleidung', DateTime(2026, 10, 9), income: true, note: 'Zalando'),
    _t('food', 30000, 'Lebensmittel', DateTime(2026, 10, 10)),
  ];

  test('a return lowers spending in its category and is no income', () {
    final r = tx.firstWhere((t) => t.id == 'return');
    expect(r.isRefund, isTrue);
    expect(r.spendCents, -8000);
    final oct = DB.inMonth(tx, now);
    expect(DB.sumOf(oct, isIncome: true), 250000);
    expect(DB.sumOf(oct, isIncome: false), 12000 + 30000 - 8000);
    expect(DB.categoriesOf(oct, isIncome: false), {'Kleidung': 4000, 'Lebensmittel': 30000});
    // other income under "Sonstiges" stays income
    expect(_t('x', 500, 'Sonstiges', now, income: true).isRefund, isFalse);
  });

  test('a category fully refunded disappears from the breakdown', () {
    final all = [...tx, _t('return2', 4000, 'Kleidung', DateTime(2026, 10, 12), income: true)];
    expect(DB.categoriesOf(DB.inMonth(all, now), isIncome: false).containsKey('Kleidung'), isFalse);
  });

  test('forecast and recap net the return', () {
    final f = ForecastService.build(tx, now: now)!;
    expect(f.incomeCents, 250000);
    expect(f.spentCents, 34000);
    final recap = RecapService.build(tx, DateTime(2026, 10))!;
    expect(recap.income, 250000);
    expect(recap.expenses, 34000);
  });

  test('a budget counts what is left after the return', () async {
    Hive.init(Directory.systemTemp.createTempSync('refund').path);
    for (final name in ['transactions', 'budgets', 'settings']) {
      await Hive.openBox(name);
    }
    for (final t in tx) {
      await DB.addTx(t);
    }
    await DB.addBudget(Budget(
        category: 'Kleidung', limitCents: 10000, startDate: DateTime(2026, 10, 1), endDate: DateTime(2026, 10, 31)));
    final b = DB.getBudgets().single;
    expect(b.spentCents, 4000);
    expect(b.isOver, isFalse);
  });

  test('money back from a shop is recognised as a refund', () {
    expect(Categorizer.guess('Zalando SE Rueckerstattung', isIncome: true), 'Kleidung');
    expect(Categorizer.guess('Gehalt Oktober', isIncome: true), 'Gehalt');
    expect(Categorizer.guess('Max Mustermann', isIncome: true), 'Sonstiges');
  });
}
