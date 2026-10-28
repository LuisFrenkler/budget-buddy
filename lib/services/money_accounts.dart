// The user's accounts and what is on each. The main account always exists;
// further ones (a savings account, cash, accounts at a second bank) are kept
// in the settings box, so backups and the account copy carry them along.
import 'package:hive/hive.dart';
import '../models/money_account.dart';
import '../models/transaction.dart';
import 'db.dart';
import 'settings_service.dart';

class MoneyAccounts {
  static Box get _box => Hive.box('settings');

  // the main account's name and kind, the others in full
  static MoneyAccount get main {
    final m = (_box.get('mainAccount') as Map?) ?? const {};
    final bank = Settings.bankName;
    return MoneyAccount(
      id: MoneyAccount.main,
      name: (m['name'] as String?) ?? (bank.isNotEmpty ? bank : 'Girokonto'),
      kind: MoneyAccount.kinds.containsKey(m['kind']) ? m['kind'] as String : 'giro',
      bank: bank.isEmpty ? null : bank,
      iban: Settings.bankIban.isEmpty ? null : Settings.bankIban,
      link: Settings.bankState.isEmpty ? null : Settings.bankState,
    );
  }

  // an account whose bank was disconnected is kept by hand from then on
  static List<MoneyAccount> get others {
    final active = {Settings.bankState, for (final l in Settings.extraBanks) l.state}..remove('');
    return [
      for (final m in (_box.get('moneyAccounts') as List?) ?? const [])
        if (m is Map)
          if (MoneyAccount.fromMap(m) case final a) a.link == null || active.contains(a.link) ? a : a.unlinked(),
    ];
  }

  static List<MoneyAccount> get all => [main, ...others];

  static bool get several => others.isNotEmpty;

  static MoneyAccount? byId(String? id) {
    if (id == null) return null;
    if (id == MoneyAccount.main) return main;
    for (final a in others) {
      if (a.id == id) return a;
    }
    return null;
  }

  static int openingOf(MoneyAccount a) => a.isMain ? Settings.openingBalanceCents : a.openingCents;

  // the starting balances of all accounts together: with all bookings this
  // gives the money on every account
  static int get openingTotal => Settings.openingBalanceCents + others.fold(0, (s, a) => s + a.openingCents);

  // bookings of one account (null id = main); a booking of an account that
  // no longer exists counts on the main account
  static List<Transaction> bookingsOf(String id, List<Transaction> tx) {
    final known = {for (final a in others) a.id};
    return [
      for (final t in tx)
        if ((t.accountId != null && known.contains(t.accountId) ? t.accountId : MoneyAccount.main) == id) t
    ];
  }

  static int balanceOf(MoneyAccount a, List<Transaction> tx) => openingOf(a) + DB.balanceOf(bookingsOf(a.id, tx));

  static Future<void> save(MoneyAccount a) async {
    if (a.isMain) {
      await _box.put('mainAccount', {'name': a.name, 'kind': a.kind});
      return;
    }
    final list = others;
    final i = list.indexWhere((x) => x.id == a.id);
    i < 0 ? list.add(a) : list[i] = a;
    await _box.put('moneyAccounts', [for (final x in list) x.toMap()]);
  }

  // sets the starting balance so the account shows [cents] today
  static Future<void> setBalance(MoneyAccount a, int cents, List<Transaction> tx) async {
    final opening = cents - DB.balanceOf(bookingsOf(a.id, tx));
    a.isMain ? await Settings.setOpeningBalanceCents(opening) : await save(a.copyWith(openingCents: opening));
  }

  // its bookings move to the main account, so no money disappears
  static Future<void> remove(MoneyAccount a) async {
    if (a.isMain) return;
    for (final t in DB.getTx().where((t) => t.accountId == a.id)) {
      await DB.addTx(t.onAccount(null));
    }
    await Settings.setOpeningBalanceCents(Settings.openingBalanceCents + a.openingCents);
    await _box.put('moneyAccounts', [for (final x in others) if (x.id != a.id) x.toMap()]);
  }
}
