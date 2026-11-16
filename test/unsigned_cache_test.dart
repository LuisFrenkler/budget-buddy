import 'dart:io';

import 'package:budget_buddy/models/goal.dart';
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/account_isolation.dart';
import 'package:budget_buddy/services/account_service.dart';
import 'package:budget_buddy/services/db.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('bb_unsigned');
    Hive.init(dir.path);
    await Hive.openBox('transactions');
    await Hive.openBox('budgets');
    await Hive.openBox('badges');
    await Hive.openBox('holdings');
    await Hive.openBox('recurring');
    await Hive.openBox('goals');
    await Hive.openBox('splits');
    await Hive.openBox('settings');
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    dir.deleteSync(recursive: true);
  });

  test('unsigned restore wipes leftover bookings, Notgroschen and demo keys', () async {
    await DB.addTx(Transaction(
      id: 'leak_tx',
      amountCents: 4200,
      category: 'Essen',
      date: DateTime(2026, 1, 2),
      isIncome: false,
    ));
    await Hive.box('goals').put(
      'g1',
      Goal(
        id: 'g1',
        name: 'Notgroschen',
        emoji: '🛟',
        targetCents: 300000,
        savedCents: 180000,
        createdAt: DateTime(2026, 1, 1),
      ).toMap(),
    );
    await Hive.box('settings').put('demoKeys', {
      'goals': ['g1'],
      'transactions': ['leak_tx'],
    });
    await Hive.box('settings').put('openingBalanceCents', 99900);
    await Hive.box('settings').put('emergencyExtraCents', 50000);
    await Hive.box('settings').put('vaultOwner', 'someone-else');

    expect(AccountIsolation.hasFinanceData, isTrue);

    await AccountService.restore();

    expect(AccountService.current.value, isNull);
    expect(AccountService.token, isNull);
    expect(DB.getTx(), isEmpty);
    expect(Hive.box('goals').isEmpty, isTrue);
    expect(Hive.box('settings').get('demoKeys'), isNull);
    expect(Hive.box('settings').get('openingBalanceCents') ?? 0, 0);
    expect(Hive.box('settings').get('emergencyExtraCents'), isNull);
    expect(Hive.box('settings').get('vaultOwner'), isNull);
    expect(AccountIsolation.hasFinanceData, isFalse);
  });
}
