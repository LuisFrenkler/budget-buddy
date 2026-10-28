import 'dart:io';

import 'package:budget_buddy/models/goal.dart';
import 'package:budget_buddy/models/money_account.dart';
import 'package:budget_buddy/services/db.dart';
import 'package:budget_buddy/services/goal_move.dart';
import 'package:budget_buddy/services/goals_service.dart';
import 'package:budget_buddy/services/money_accounts.dart';
import 'package:budget_buddy/utils/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  setUp(() async {
    final dir = Directory.systemTemp.createTempSync('bb_goal_move');
    Hive.init(dir.path);
    await Hive.openBox('settings');
    await Hive.openBox('goals');
    await Hive.openBox('transactions');
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
  });

  test('with one account, only the goal counter moves', () async {
    final g = Goal(id: '1', name: 'Urlaub', emoji: '🏖️', targetCents: 80000, createdAt: DateTime(2026));
    await GoalsService.save(g);
    final r = await GoalMove.apply(goal: g, cents: 5000, take: false);
    expect(r.booked, isFalse);
    expect(r.moved, 5000);
    expect(g.savedCents, 5000);
    expect(DB.getTx(), isEmpty);
  });

  test('with a savings account, Zurücklegen books an Umbuchung', () async {
    await MoneyAccounts.save(const MoneyAccount(id: 'spar1', name: 'Tagesgeld', kind: 'spar'));
    final g = Goal(id: '1', name: 'Urlaub', emoji: '🏖️', targetCents: 80000, createdAt: DateTime(2026));
    await GoalsService.save(g);
    final r = await GoalMove.apply(goal: g, cents: 5000, take: false);
    expect(r.booked, isTrue);
    expect(r.moved, 5000);
    expect(g.savedCents, 5000);
    expect(g.potId, 'spar1');
    final tx = DB.getTx();
    expect(tx.length, 2);
    expect(tx.every((t) => t.category == Categories.transfer), isTrue);
    expect(tx.any((t) => t.note!.contains('Urlaub')), isTrue);
  });

  test('Entnehmen reverses onto the source account', () async {
    await MoneyAccounts.save(const MoneyAccount(id: 'spar1', name: 'Tagesgeld', kind: 'spar'));
    final g = Goal(
        id: '1', name: 'Urlaub', emoji: '🏖️', targetCents: 80000, savedCents: 5000, potId: 'spar1', createdAt: DateTime(2026));
    await GoalsService.save(g);
    final r = await GoalMove.apply(goal: g, cents: 2000, take: true);
    expect(r.booked, isTrue);
    expect(g.savedCents, 3000);
    expect(DB.getTx().length, 2);
  });
}
