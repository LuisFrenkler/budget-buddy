import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/db.dart';
import 'package:budget_buddy/services/demo_data.dart';
import 'package:budget_buddy/services/goals_service.dart';
import 'package:budget_buddy/services/recurring_service.dart';
import 'package:budget_buddy/services/settings_service.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('bb_demo_remove');
    Hive.init(tempDir.path);
    for (final name in ['transactions', 'budgets', 'badges', 'holdings', 'recurring', 'goals', 'settings']) {
      await Hive.openBox(name);
    }
  });

  tearDownAll(() async {
    await Hive.deleteFromDisk();
    tempDir.deleteSync(recursive: true);
  });

  test('sample data is marked and removed again, the user\'s own data stays', () async {
    final mine = Transaction(
        id: 'mine', amountCents: 450, category: 'Essen & Trinken', date: DateTime(2026, 3, 1), isIncome: false,
        note: 'Bäcker');
    await DB.addTx(mine);
    await Settings.setOpeningBalanceCents(12300);

    await DemoData.load(now: DateTime(2026, 3, 15, 18));
    expect(DemoData.active, isTrue);
    expect(DB.getTx().length, greaterThan(50));
    expect(DB.getHoldings(), isNotEmpty);
    expect(GoalsService.all(), isNotEmpty);

    await DemoData.remove();
    expect(DemoData.active, isFalse);
    expect(DB.getTx().map((t) => t.id), ['mine']);
    expect(DB.getHoldings(), isEmpty);
    expect(DB.getRules(), isEmpty);
    expect(DB.getBudgets(), isEmpty);
    expect(GoalsService.all(), isEmpty);
    expect(Settings.openingBalanceCents, 12300);
  });

  test('what the demo booked and carried over in later months goes too', () async {
    await DB.addTx(Transaction(
        id: 'mine2', amountCents: 450, category: 'Essen & Trinken', date: DateTime(2026, 3, 2), isIncome: false));
    await DemoData.load(now: DateTime(2026, 3, 15, 18));
    // the app is opened again two months later
    expect(await RecurringService.process(today: DateTime(2026, 5, 20)), greaterThan(0));
    expect(await DB.rollOverBudgets(now: DateTime(2026, 5, 20)), greaterThan(0));

    await DemoData.remove();
    expect(DB.getTx().map((t) => t.id), containsAll(['mine2']));
    expect(DB.getTx().where((t) => t.id.startsWith('rec_')), isEmpty);
    expect(DB.getBudgets(), isEmpty);
  });
}
