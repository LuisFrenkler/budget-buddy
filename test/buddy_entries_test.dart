import 'dart:io';
import 'package:budget_buddy/models/money_account.dart';
import 'package:budget_buddy/services/buddy_entries.dart';
import 'package:budget_buddy/services/db.dart';
import 'package:budget_buddy/services/money_accounts.dart';
import 'package:budget_buddy/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('bb_entries').path);
    for (final name in ['transactions', 'settings', 'budgets', 'badges', 'holdings', 'recurring']) {
      await Hive.openBox(name);
    }
    await Settings.setOpeningBalanceCents(100000);
    await MoneyAccounts.save(const MoneyAccount(id: 'tg', name: 'Tagesgeld', kind: 'spar', openingCents: 0));
  });

  test('telling from asking', () {
    expect(BuddyEntries.looksLikeEvent('Hab 200 € aufs Tagesgeld überwiesen'), isTrue);
    expect(BuddyEntries.looksLikeEvent('10 Apple zu 180 € gekauft'), isTrue);
    expect(BuddyEntries.looksLikeEvent('Wie viel habe ich im Oktober ausgegeben?'), isFalse);
    expect(BuddyEntries.looksLikeEvent('Wo kann ich sparen'), isFalse);
  });

  test('unknown accounts and categories from the AI fall back safely', () {
    final e = BuddyEntry.fromJson(
        {'type': 'booking', 'amount': 8.5, 'isIncome': false, 'category': 'Quatsch', 'note': 'Döner', 'account': 'x'})!;
    expect(e.category, 'Sonstiges');
    expect(e.account, isNull);
    expect(BuddyEntry.fromJson({'type': 'transfer', 'amount': 50, 'account': 'main', 'toAccount': 'main'}), isNull);
  });

  test('a transfer, a buy from the main account and a sell land where they belong', () async {
    final transfer = BuddyEntry.fromJson({'type': 'transfer', 'amount': 200, 'account': 'main', 'toAccount': 'tg'})!;
    await BuddyEntries.apply(transfer);
    var tx = DB.getTx();
    expect(MoneyAccounts.balanceOf(MoneyAccounts.main, tx), 80000);
    expect(MoneyAccounts.balanceOf(MoneyAccounts.byId('tg')!, tx), 20000);
    expect(DB.sumOf(tx, isIncome: false), 0); // moving money is no spending

    final buy = BuddyEntry.fromJson(
        {'type': 'buy', 'name': 'Apple', 'symbol': 'AAPL', 'shares': 2, 'price': 150, 'account': 'main', 'depot': 'Scalable'})!;
    expect(await BuddyEntries.apply(buy), 'Im Depot');
    await BuddyEntries.apply(BuddyEntry.fromJson(
        {'type': 'buy', 'symbol': 'AAPL', 'name': 'Apple', 'shares': 2, 'price': 250, 'depot': 'Scalable'})!);
    final apple = DB.getHoldings().single;
    expect(apple.shares, 4);
    expect(apple.buyPriceCents, 20000); // average of 150 € and 250 €
    expect(apple.depot, 'Scalable');
    tx = DB.getTx();
    expect(MoneyAccounts.balanceOf(MoneyAccounts.main, tx), 80000 - 30000); // only the first came from an account
    expect(DB.sumOf(tx, isIncome: false), 0);

    await BuddyEntries.apply(BuddyEntry.fromJson({'type': 'sell', 'symbol': 'AAPL', 'shares': 4, 'price': 300})!);
    expect(DB.getHoldings(), isEmpty);
  });
}
