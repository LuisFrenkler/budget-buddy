import 'dart:io';
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/account_isolation.dart';
import 'package:budget_buddy/services/db.dart';
import 'package:budget_buddy/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  group('wipeLocalFinance', () {
    late Directory dir;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('bb_iso');
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

    test('clears bank, depot, bookings, dismissals and onboarding', () async {
      await DB.addTx(Transaction(
          id: 't1',
          amountCents: 100,
          category: 'Essen',
          date: DateTime(2026, 1, 1),
          isIncome: false));
      await Settings.setBankState('state-a');
      await Settings.setBankOwner('user-a');
      await Settings.setBankInfo(name: 'ING');
      await Settings.setDepot('depot-a', broker: 'Trade Republic');
      await Settings.setDepotOwner('user-a');
      await Hive.box('settings').put('vaultOwner', 'user-a');
      await Hive.box('settings').put('openingBalanceCents', 50000);
      await Hive.box('settings').put('onboardingDone', true);
      await Hive.box('settings').put('onboardingHidden', true);
      await Hive.box('settings').put('bankDismissed', ['bank_old']);

      final before = AccountIsolation.epoch;
      await AccountIsolation.wipeLocalFinance();

      expect(AccountIsolation.epoch, before + 1);
      expect(AccountIsolation.sameEpoch(before), isFalse);
      expect(DB.getTx(), isEmpty);
      expect(Settings.bankState, isEmpty);
      expect(Settings.bankOwner, isEmpty);
      expect(Settings.bankName, isEmpty);
      expect(Settings.depotState, isEmpty);
      expect(Settings.depotOwner, isEmpty);
      expect(Hive.box('settings').get('vaultOwner'), isNull);
      expect(Settings.openingBalanceCents, 0);
      expect(Settings.onboardingDone, isFalse);
      expect(Hive.box('settings').get('onboardingHidden'), isNull);
      expect(Hive.box('settings').get('bankDismissed'), isNull);
    });

    test('claim without depot links drops orphan depot holdings', () async {
      await Hive.box('holdings').put('depot_US123', {
        'id': 'depot_US123',
        'name': 'Leak',
        'symbol': '',
        'type': 'Aktie',
        'shares': 1,
        'buyPriceCents': 100,
        'currentPriceCents': 100,
      });
      await Hive.box('holdings').put('hand_1', {
        'id': 'hand_1',
        'name': 'Typed',
        'symbol': '',
        'type': 'Aktie',
        'shares': 1,
        'buyPriceCents': 100,
        'currentPriceCents': 100,
      });

      await AccountIsolation.claimLocalFor('user-b');

      expect(Hive.box('holdings').containsKey('depot_US123'), isFalse);
      expect(Hive.box('holdings').containsKey('hand_1'), isTrue);
    });
  });
}
