// Brings the bookings of a linked bank account into the app.
//
// - Every booking gets the stable id "bank_<id>", so syncing again never
//   duplicates and never overwrites a booking the user has edited.
// - New bookings get a category: the one the user last gave the same
//   counterparty, otherwise a keyword guess (see Categorizer).
// - The opening balance is set so the app's Kontostand equals the bank's,
//   even though the bank only hands out the last months of history.
// - Every account at the bank stands on its own: the first account of the
//   first linked bank is the app's main account, every other one (the
//   savings account, accounts at a second bank) gets its own account.
//   Money moved between two of them in one sync is booked as "Umbuchung".
import '../models/money_account.dart';
import '../models/transaction.dart';
import '../utils/theme.dart';
import 'backend_service.dart';
import 'categorizer.dart';
import 'category_rules.dart';
import 'db.dart';
import 'money_accounts.dart';
import 'settings_service.dart';

class BankSyncResult {
  final List<Transaction> added;
  final int openingBalanceCents; // of the main account; ignore when [touchesMain] is false
  final List<Transaction> moved; // known bookings now on their own account
  final List<MoneyAccount> accounts; // the bank's other accounts, with their starting balance
  final bool touchesMain;
  const BankSyncResult(this.added, this.openingBalanceCents,
      {this.moved = const [], this.accounts = const [], this.touchesMain = true});
}

class BankSync {
  static const prefix = 'bank_';

  // pure merge step, separate from storage so it can be tested
  static BankSyncResult merge({
    required List<Transaction> existing,
    required List<BankTransaction> incoming,
    required int bankBalanceCents,
    Set<String> dismissed = const {}, // bank bookings the user deleted
    List<BankAccountInfo> accounts = const [], // empty: an older server, one account
    String link = '', // the bank link these come through
    bool primary = true, // the first linked bank: its first account is the main one
    String bankName = 'Bank',
    List<MoneyAccount> others = const [], // the user's accounts besides the main one
  }) {
    // the app account each bank account books on; null = the main account
    String? accountFor(String uid) {
      if (accounts.isEmpty) return primary ? null : '$prefix$link';
      if (primary && uid == accounts.first.uid) return null;
      return '$prefix$uid';
    }

    final byId = {for (final t in existing) t.id: t};
    final moved = <Transaction>[];
    final known = {for (final t in existing) t.id, ...dismissed};
    // bookings imported from a bank CSV before the bank was linked: the
    // same booking arriving from the bank is not counted a second time
    final imported = <String, int>{};
    for (final t in existing) {
      if (!t.id.startsWith('csv_')) continue;
      final k = _dayKey(t.date, t.amountCents, t.isIncome);
      imported[k] = (imported[k] ?? 0) + 1;
    }

    // what the user calls things: the latest category per bank title
    final memory = <String, String>{};
    final sorted = [...existing]..sort((a, b) => a.date.compareTo(b.date));
    for (final t in sorted) {
      if (t.id.startsWith(prefix) && t.note != null) memory[_key(t.note!, t.isIncome)] = t.category;
    }

    final added = <Transaction>[];
    for (final b in incoming) {
      final id = '$prefix${b.id}';
      final target = accountFor(b.account);
      // synced before all accounts stood on their own: it moves to its account
      final before = byId[id];
      if (before != null && before.accountId != target) moved.add(before.onAccount(target));
      if (known.contains(id)) continue;
      known.add(id);
      final isIncome = b.amountCents >= 0;
      final day = _dayKey(b.date, b.amountCents.abs(), isIncome);
      if ((imported[day] ?? 0) > 0) {
        imported[day] = imported[day]! - 1;
        continue;
      }
      final title = _title(b);
      added.add(Transaction(
        id: id,
        amountCents: b.amountCents.abs(),
        category: CategoryRules.forName(title, isIncome: isIncome) ??
            memory[_key(title, isIncome)] ??
            Categorizer.guess('${b.counterparty} ${b.purpose}', isIncome: isIncome),
        date: b.date,
        isIncome: isIncome,
        note: title,
        accountId: target,
      ));
    }

    // out of one account and into another on the same day: the user moved
    // their own money, which is neither spending nor income
    for (var i = 0; i < added.length; i++) {
      final out = added[i];
      if (out.isIncome || out.category == Categories.transfer) continue;
      for (var j = 0; j < added.length; j++) {
        final into = added[j];
        if (!into.isIncome || into.category == Categories.transfer || into.accountId == out.accountId) continue;
        if (into.amountCents != out.amountCents || !_sameDay(into.date, out.date)) continue;
        added[i] = out.withCategory(Categories.transfer);
        added[j] = into.withCategory(Categories.transfer);
        break;
      }
    }

    // every booking where it belongs now
    final movedIds = {for (final t in moved) t.id: t};
    final ledger = [for (final t in existing) movedIds[t.id] ?? t, ...added];
    final newIds = {for (final a in accounts) accountFor(a.uid)}..remove(null);
    final otherIds = {for (final a in others) a.id, ...newIds};
    int sumOn(String? account) => DB.balanceOf([
          for (final t in ledger)
            if ((t.accountId != null && otherIds.contains(t.accountId) ? t.accountId : null) == account) t
        ]);

    final saved = {for (final a in others) a.id: a};
    final bankAccounts = <MoneyAccount>[];
    for (final a in accounts) {
      final id = accountFor(a.uid);
      if (id == null) continue;
      final name = a.name == null || a.name!.isEmpty
          ? bankName
          : (primary || a.name!.toLowerCase().contains(bankName.toLowerCase()) ? a.name! : '$bankName ${a.name}');
      // a name or kind the user chose stays
      final mine = saved[id];
      bankAccounts.add((mine ?? MoneyAccount(id: id, name: name, kind: MoneyAccount.guessKind(name)))
          .copyWith(openingCents: a.balanceCents - sumOn(id), bank: bankName, iban: a.iban, link: link));
    }
    if (accounts.isEmpty && !primary) {
      final id = accountFor('')!;
      bankAccounts.add((saved[id] ?? MoneyAccount(id: id, name: bankName))
          .copyWith(openingCents: bankBalanceCents - sumOn(id), bank: bankName, link: link));
    }

    final mainBalance = accounts.isEmpty ? bankBalanceCents : accounts.first.balanceCents;
    return BankSyncResult(added, mainBalance - sumOn(null),
        moved: moved, accounts: bankAccounts, touchesMain: primary);
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  // the counterparty reads best ("REWE Markt GmbH"); the purpose is the fallback
  static String _title(BankTransaction b) {
    final party = b.counterparty.trim();
    if (party.isNotEmpty) return party;
    final purpose = b.purpose.trim();
    return purpose.isNotEmpty ? purpose : 'Bankbuchung';
  }

  static String _dayKey(DateTime d, int cents, bool income) => '${d.year}-${d.month}-${d.day}|$cents|$income';

  static String _key(String title, bool income) => '${income ? '+' : '-'}${title.toLowerCase().trim()}';

  // fetches, merges and stores every linked bank; returns how many bookings are new
  static Future<int> run() async {
    final state = Settings.bankState;
    var added = 0;
    final links = [
      if (state.isNotEmpty) (state: state, bank: Settings.bankName, primary: true),
      for (final l in Settings.extraBanks) (state: l.state, bank: l.bank, primary: false),
    ];
    if (links.isEmpty) return 0;
    for (final l in links) {
      final data = await BackendService.sync(l.state);
      final result = merge(
        existing: DB.getTx(),
        incoming: data.transactions,
        bankBalanceCents: data.balanceCents,
        dismissed: DB.dismissedBankIds,
        accounts: data.accounts,
        link: l.state,
        primary: l.primary,
        bankName: l.bank.isEmpty ? 'Bank' : l.bank,
        others: MoneyAccounts.others,
      );
      for (final a in result.accounts) {
        await MoneyAccounts.save(a);
      }
      for (final t in [...result.moved, ...result.added]) {
        await DB.addTx(t);
      }
      if (result.touchesMain) {
        await Settings.setOpeningBalanceCents(result.openingBalanceCents);
        await Settings.setBankBalanceCents(data.balanceCents);
      }
      added += result.added.length;
    }
    await Settings.setLastSync(DateTime.now());
    await DB.checkBadges();
    return added;
  }

  // syncs quietly when linked and the last sync is older than [maxAge]
  static Future<void> refreshIfStale({Duration maxAge = const Duration(hours: 4)}) async {
    if (Settings.bankState.isEmpty && Settings.extraBanks.isEmpty) return;
    final last = Settings.lastSync;
    if (last != null && DateTime.now().difference(last) < maxAge) return;
    try {
      await run();
    } catch (_) {
      // offline or server not running: try again next start
    }
  }
}
