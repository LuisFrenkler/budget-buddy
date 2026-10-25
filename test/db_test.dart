import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:budget_buddy/services/db.dart';
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/models/budget.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('bb_test');
    Hive.init(tempDir.path);
    await Hive.openBox('transactions');
    await Hive.openBox('budgets');
    await Hive.openBox('badges');
  });

  tearDown(() async {
    await Hive.box('transactions').clear();
    await Hive.box('budgets').clear();
    await Hive.box('badges').clear();
  });

  tearDownAll(() async {
    await Hive.deleteFromDisk();
    tempDir.deleteSync(recursive: true);
  });

  Future<void> add(int cents, String cat, bool income, DateTime date) {
    return DB.addTx(Transaction(
      id: '$cat-${date.millisecondsSinceEpoch}-$cents',
      amountCents: cents,
      category: cat,
      date: date,
      isIncome: income,
    ));
  }

  group('DB aggregation in cents', () {
    test('income, expenses and balance sum exactly', () async {
      await add(285000, 'Gehalt', true, DateTime(2025, 3, 1));
      await add(6743, 'Lebensmittel', false, DateTime(2025, 3, 5));
      await add(1099, 'Unterhaltung', false, DateTime(2025, 3, 8));

      expect(DB.income(), 285000);
      expect(DB.expenses(), 7842);
      expect(DB.balance(), 277158);
    });

    test('month filter only counts the selected month', () async {
      await add(285000, 'Gehalt', true, DateTime(2025, 3, 1));
      await add(285000, 'Gehalt', true, DateTime(2025, 4, 1));

      expect(DB.income(month: DateTime(2025, 3)), 285000);
      expect(DB.income(month: DateTime(2025, 4)), 285000);
      expect(DB.income(), 570000);
    });

    test('byCategory groups expenses', () async {
      await add(5000, 'Lebensmittel', false, DateTime(2025, 3, 5));
      await add(3000, 'Lebensmittel', false, DateTime(2025, 3, 6));
      await add(2000, 'Transport', false, DateTime(2025, 3, 7));

      final byCat = DB.byCategory(isIncome: false);
      expect(byCat['Lebensmittel'], 8000);
      expect(byCat['Transport'], 2000);
    });
  });

  group('Budget spent calculation', () {
    test('sums only matching category and date range', () async {
      await DB.addBudget(Budget(
        category: 'Lebensmittel',
        limitCents: 25000,
        startDate: DateTime(2025, 3, 1),
        endDate: DateTime(2025, 3, 31),
      ));

      await add(5000, 'Lebensmittel', false, DateTime(2025, 3, 5));
      await add(3000, 'Lebensmittel', false, DateTime(2025, 3, 20));
      await add(9999, 'Transport', false, DateTime(2025, 3, 10)); // wrong category
      await add(7777, 'Lebensmittel', false, DateTime(2025, 4, 2)); // out of range

      final budget = DB.getBudgets().single;
      expect(budget.spentCents, 8000);
      expect(budget.isOver, isFalse);
    });

    test('counts transactions on the last day regardless of time-of-day', () async {
      await DB.addBudget(Budget(
        category: 'Lebensmittel',
        limitCents: 10000,
        startDate: DateTime(2025, 3, 1),
        endDate: DateTime(2025, 3, 31),
      ));
      // a transaction stamped late on the last day must still count
      await add(5000, 'Lebensmittel', false, DateTime(2025, 3, 31, 23, 59));

      expect(DB.getBudgets().single.spentCents, 5000);
    });
  });
}
