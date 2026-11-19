// The money check before sign-up: a guest's bank bookings stay in memory,
// become the agent's money finds, and move into the ledger only on sign-up.
import 'dart:io';

import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/ahead_agent.dart';
import 'package:budget_buddy/services/db.dart';
import 'package:budget_buddy/services/guest_money_check.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  final today = DateTime(2026, 11, 17);
  final netflix = [
    for (final m in [8, 9, 10, 11])
      Transaction(id: 'n$m', amountCents: 1399, category: 'Unterhaltung', isIncome: false, date: DateTime(2026, m, 3), note: 'Netflix'),
  ];

  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('guest_money').path);
    for (final name in ['transactions', 'settings', 'recurring', 'badges', 'budgets', 'holdings', 'goals', 'splits']) {
      await Hive.openBox(name);
    }
  });
  setUp(() async {
    GuestMoneyCheck.clear();
    await Hive.box('settings').clear();
    await Hive.box('transactions').clear();
  });

  test('bookings become money finds, never tax finds, and nothing touches the ledger', () {
    expect(GuestMoneyCheck.finds(now: today), isEmpty);
    GuestMoneyCheck.set(netflix);
    final finds = GuestMoneyCheck.finds(now: today);
    expect(finds, isNotEmpty);
    expect(finds.every((f) => f.kind == FindKind.money), isTrue);
    expect(DB.getTx(), isEmpty);
  });

  test('sign-up adopts the bookings once; another account signing in gets none', () async {
    GuestMoneyCheck.set(netflix);
    final before = AheadAgent.changed.value;
    expect(await GuestMoneyCheck.adopt(), 4);
    expect(DB.getTx().length, 4);
    expect(AheadAgent.changed.value, before + 1);
    expect(await GuestMoneyCheck.adopt(), 0);

    GuestMoneyCheck.set(netflix);
    GuestMoneyCheck.clear();
    expect(GuestMoneyCheck.done, isFalse);
    expect(await GuestMoneyCheck.adopt(), 0);
  });
}
