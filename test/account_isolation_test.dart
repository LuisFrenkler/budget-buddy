import 'dart:io';
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/account_isolation.dart';
import 'package:budget_buddy/services/db.dart';
import 'package:budget_buddy/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  group('mayKeepLocal', () {
    test('same vault owner keeps data', () {
      expect(
        AccountIsolation.mayKeepLocal(
          accountId: 'a',
          vaultOwner: 'a',
          bankOwner: '',
          depotOwner: '',
          hasBankOrDepotLinks: true,
          hasFinanceData: true,
          wasGuest: false,
        ),
        isTrue,
      );
    });

    test('different vault owner never keeps bank or bookings', () {
      expect(
        AccountIsolation.mayKeepLocal(
          accountId: 'b',
          vaultOwner: 'a',
          bankOwner: 'a',
          depotOwner: '',
          hasBankOrDepotLinks: true,
          hasFinanceData: true,
          wasGuest: false,
        ),
        isFalse,
      );
    });

    test('orphaned bank link without owner is wiped for any sign-in', () {
      expect(
        AccountIsolation.mayKeepLocal(
          accountId: 'b',
          vaultOwner: '',
          bankOwner: '',
          depotOwner: '',
          hasBankOrDepotLinks: true,
          hasFinanceData: false,
          wasGuest: false,
        ),
        isFalse,
      );
    });

    test('guest upgrading may keep their own typed bookings', () {
      expect(
        AccountIsolation.mayKeepLocal(
          accountId: 'new',
          vaultOwner: '',
          bankOwner: '',
          depotOwner: '',
          hasBankOrDepotLinks: false,
          hasFinanceData: true,
          wasGuest: true,
        ),
        isTrue,
      );
    });

    test('unowned bookings after sign-out are not given to a new account', () {
      expect(
        AccountIsolation.mayKeepLocal(
          accountId: 'new',
          vaultOwner: '',
          bankOwner: '',
          depotOwner: '',
          hasBankOrDepotLinks: false,
          hasFinanceData: true,
          wasGuest: false,
        ),
        isFalse,
      );
    });

    test('bankOwner alone identifies the previous account', () {
      expect(
        AccountIsolation.mayKeepLocal(
          accountId: 'b',
          vaultOwner: '',
          bankOwner: 'a',
          depotOwner: '',
          hasBankOrDepotLinks: true,
          hasFinanceData: false,
          wasGuest: true,
        ),
        isFalse,
      );
    });
  });

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

    test('clears bank, depot and bookings so a new account starts clean', () async {
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

      await AccountIsolation.wipeLocalFinance();

      expect(DB.getTx(), isEmpty);
      expect(Settings.bankState, isEmpty);
      expect(Settings.bankOwner, isEmpty);
      expect(Settings.bankName, isEmpty);
      expect(Settings.depotState, isEmpty);
      expect(Settings.depotOwner, isEmpty);
      expect(Hive.box('settings').get('vaultOwner'), isNull);
      expect(Settings.openingBalanceCents, 0);
    });
  });
}
