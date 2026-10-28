import 'dart:io';

import 'package:budget_buddy/models/goal.dart';
import 'package:budget_buddy/models/money_account.dart';
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/db.dart';
import 'package:budget_buddy/services/goal_credit.dart';
import 'package:budget_buddy/services/goals_service.dart';
import 'package:budget_buddy/services/money_accounts.dart';
import 'package:budget_buddy/utils/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  setUp(() async {
    final dir = Directory.systemTemp.createTempSync('bb_goal_credit');
    Hive.init(dir.path);
    await Hive.openBox('settings');
    await Hive.openBox('goals');
    await Hive.openBox('transactions');
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
  });

  test('bank Umbuchung onto the pot counts toward the only open goal', () async {
    await MoneyAccounts.save(const MoneyAccount(id: 'spar1', name: 'Tagesgeld', kind: 'spar'));
    final g = Goal(
      id: '1',
      name: 'Urlaub',
      emoji: '🏖️',
      targetCents: 80000,
      potId: 'spar1',
      createdAt: DateTime(2026, 1, 1),
    );
    await GoalsService.save(g);
    await DB.addTx(Transaction(
      id: 'bank_in',
      amountCents: 5000,
      category: Categories.transfer,
      date: DateTime(2026, 10, 1),
      isIncome: true,
      note: 'Umbuchung',
      accountId: 'spar1',
    ));
    final added = await GoalCredit.run();
    expect(added, 5000);
    expect(GoalsService.all().single.savedCents, 5000);
    expect(GoalsService.all().single.creditedIds, contains('bank_in'));
  });

  test('same booking is not credited twice', () async {
    await MoneyAccounts.save(const MoneyAccount(id: 'spar1', name: 'Tagesgeld', kind: 'spar'));
    await GoalsService.save(Goal(
      id: '1',
      name: 'Urlaub',
      emoji: '🏖️',
      targetCents: 80000,
      potId: 'spar1',
      savedCents: 5000,
      creditedIds: const ['bank_in'],
      createdAt: DateTime(2026, 1, 1),
    ));
    await DB.addTx(Transaction(
      id: 'bank_in',
      amountCents: 5000,
      category: Categories.transfer,
      date: DateTime(2026, 10, 1),
      isIncome: true,
      note: 'Umbuchung',
      accountId: 'spar1',
    ));
    expect(await GoalCredit.run(), 0);
    expect(GoalsService.all().single.savedCents, 5000);
  });
}
