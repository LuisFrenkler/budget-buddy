import 'dart:io';
import 'package:budget_buddy/models/money_account.dart';
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/db.dart';
import 'package:budget_buddy/services/money_accounts.dart';
import 'package:budget_buddy/services/settings_service.dart';
import 'package:budget_buddy/widgets/transfer_sheet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

Transaction _tx(String id, int cents, {bool income = false, String? account}) => Transaction(
    id: id, amountCents: cents, category: income ? 'Gehalt' : 'Lebensmittel', date: DateTime(2026, 10, 5),
    isIncome: income, accountId: account);

void main() {
  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('bb_accounts').path);
    for (final name in ['transactions', 'settings', 'budgets', 'badges', 'holdings', 'recurring']) {
      await Hive.openBox(name);
    }
  });

  test('each account has its own balance, together they make the total', () async {
    await Settings.setOpeningBalanceCents(100000);
    const savings = MoneyAccount(id: 'tg', name: 'Tagesgeld', kind: 'spar', openingCents: 500000);
    await MoneyAccounts.save(savings);
    await DB.addTx(_tx('a', 2000));
    await DB.addTx(_tx('b', 1250, income: true, account: 'tg'));
    final tx = DB.getTx();

    expect(MoneyAccounts.balanceOf(MoneyAccounts.main, tx), 98000);
    expect(MoneyAccounts.balanceOf(MoneyAccounts.byId('tg')!, tx), 501250);
    expect(DB.balanceOf(tx) + MoneyAccounts.openingTotal, 98000 + 501250);

    // moving money between them changes both, the total stays and nothing is spending
    for (final t in transferBookings(
        from: MoneyAccounts.main, to: MoneyAccounts.byId('tg')!, cents: 20000, date: DateTime(2026, 10, 6))) {
      await DB.addTx(t);
    }
    final after = DB.getTx();
    expect(MoneyAccounts.balanceOf(MoneyAccounts.main, after), 78000);
    expect(MoneyAccounts.balanceOf(MoneyAccounts.byId('tg')!, after), 521250);
    expect(DB.balanceOf(after) + MoneyAccounts.openingTotal, 98000 + 501250);
    expect(DB.sumOf(after, isIncome: false), 2000);

    // setting today's balance of one account leaves the others alone
    await MoneyAccounts.setBalance(MoneyAccounts.byId('tg')!, 600000, after);
    expect(MoneyAccounts.balanceOf(MoneyAccounts.byId('tg')!, DB.getTx()), 600000);
    expect(MoneyAccounts.balanceOf(MoneyAccounts.main, DB.getTx()), 78000);

    // removing an account moves its bookings and money to the main account
    final total = DB.balanceOf(DB.getTx()) + MoneyAccounts.openingTotal;
    await MoneyAccounts.remove(MoneyAccounts.byId('tg')!);
    expect(MoneyAccounts.several, isFalse);
    expect(DB.getTx().every((t) => t.accountId == null), isTrue);
    expect(DB.balanceOf(DB.getTx()) + MoneyAccounts.openingTotal, total);
  });
}
