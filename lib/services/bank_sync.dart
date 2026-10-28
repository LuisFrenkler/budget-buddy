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
import 'package:flutter/foundation.dart';

import '../models/money_account.dart';
import '../models/transaction.dart';
import '../utils/merchant.dart';
import '../utils/theme.dart';
import 'account_isolation.dart';
import 'account_service.dart';
import 'backend_service.dart';
import 'categorizer.dart';
import 'category_rules.dart';
import 'db.dart';
import 'money_accounts.dart';
import 'settings_service.dart';

class BankSyncResult {
  final List<Transaction> added;
  final int
      openingBalanceCents; // of the main account; ignore when [touchesMain] is false
  final List<Transaction> moved; // known bookings now on their own account
  final List<MoneyAccount>
      accounts; // the bank's other accounts, with their starting balance
  final bool touchesMain;
  // new bookings the categorizer placed outside Sonstiges, without a saved rule
  final int smarter;
  const BankSyncResult(this.added, this.openingBalanceCents,
      {this.moved = const [],
      this.accounts = const [],
      this.touchesMain = true,
      this.smarter = 0});
}

class BankSync {
  static const prefix = 'bank_';
  static Future<({int added, int smarter})>? _inflight;

  // sorts not yet said out loud. A sync snackbar takes them; otherwise the
  // start screen says it once. Nothing is offered when the count is 0.
  static final smileTick = ValueNotifier<int>(0);
  static int _smileAdded = 0;
  static int _smileSmarter = 0;
  static int _hold = 0;

  static bool get smileHeld => _hold > 0;

  static void holdSmile(bool on) {
    if (on) {
      _hold++;
      return;
    }
    if (_hold == 0) return;
    _hold--;
    if (_hold == 0 && _smileSmarter > 0) smileTick.value++;
  }

  static void offerSmile({int added = 0, int smarter = 0}) {
    if (smarter <= 0) return;
    _smileAdded += added;
    _smileSmarter += smarter;
    if (_hold == 0) smileTick.value++;
  }

  static ({int added, int smarter}) takeSmile() {
    final r = (added: _smileAdded, smarter: _smileSmarter);
    _smileAdded = 0;
    _smileSmarter = 0;
    return r;
  }

  /// This sync plus any smarter sort still unspoken.
  /// When this sync itself sorted bookings, those new ones are already in the pool.
  static ({int added, int smarter}) claimSmile(({int added, int smarter}) run) {
    final smile = takeSmile();
    final added = run.smarter > 0 ? smile.added : run.added + smile.added;
    return (added: added, smarter: smile.smarter);
  }

  static String syncedLine(
      {required int added,
      required int smarter,
      String none = 'Alles aktuell'}) {
    final warm = smarter <= 0
        ? null
        : '$smarter ${smarter == 1 ? 'Umsatz' : 'Umsätze'} smarter eingeordnet';
    if (added <= 0) return warm ?? none;
    final fresh = '$added neue ${added == 1 ? 'Buchung' : 'Buchungen'}';
    return warm == null ? fresh : '$fresh · $warm';
  }

  // giro/checking before savings so the main account is never Tagesgeld first
  static List<BankAccountInfo> preferGiroFirst(List<BankAccountInfo> accounts) {
    if (accounts.length < 2) return accounts;
    final giro = [
      for (final a in accounts)
        if (MoneyAccount.guessKind(a.name ?? '') != 'spar') a
    ];
    final spar = [
      for (final a in accounts)
        if (MoneyAccount.guessKind(a.name ?? '') == 'spar') a
    ];
    if (giro.isEmpty) return accounts;
    return [...giro, ...spar];
  }

  // pure merge step, separate from storage so it can be tested
  static BankSyncResult merge({
    required List<Transaction> existing,
    required List<BankTransaction> incoming,
    required int bankBalanceCents,
    Set<String> dismissed = const {}, // bank bookings the user deleted
    List<BankAccountInfo> accounts =
        const [], // empty: an older server, one account
    String link = '', // the bank link these come through
    bool primary =
        true, // the first linked bank: its first account is the main one
    String bankName = 'Bank',
    List<MoneyAccount> others =
        const [], // the user's accounts besides the main one
  }) {
    accounts = preferGiroFirst(accounts);
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
      if (!t.id.startsWith(prefix) || t.note == null) continue;
      // a later automatic Sonstiges must not wipe a category the user already set
      void put(String key) {
        final prev = memory[key];
        if (t.category == 'Sonstiges' && prev != null && prev != 'Sonstiges')
          return;
        memory[key] = t.category;
      }

      put(_key(t.note!, t.isIncome));
      put(_key(Merchant.key(t.note!), t.isIncome));
    }

    final added = <Transaction>[];
    // fresh guesses only — a category the user already taught is not "smarter"
    final smartIds = <String>{};
    for (final b in incoming) {
      final id = '$prefix${b.id}';
      final target = accountFor(b.account);
      // synced before all accounts stood on their own: it moves to its account
      final before = byId[id];
      if (before != null && before.accountId != target)
        moved.add(before.onAccount(target));
      if (known.contains(id)) continue;
      // bank later sends a real id for a booking we stored under a fingerprint
      if (!b.id.contains('|') &&
          _fingerprintDuplicate(existing, b, target, prefix)) {
        known.add(id);
        continue;
      }
      known.add(id);
      final isIncome = b.amountCents >= 0;
      final day = _dayKey(b.date, b.amountCents.abs(), isIncome);
      if ((imported[day] ?? 0) > 0) {
        imported[day] = imported[day]! - 1;
        continue;
      }
      final title = _title(b);
      final blob = '${b.counterparty} ${b.purpose} ${b.hint} $title';
      final guessed = Categorizer.guess(blob, isIncome: isIncome, mcc: b.mcc);
      final rule = CategoryRules.forName(title, isIncome: isIncome);
      // Sonstiges here is the old automatic guess; a real choice lives in CategoryRules
      final prior = [
        memory[_key(title, isIncome)],
        memory[_key(Merchant.key(title), isIncome)]
      ].whereType<String>().where((c) => c != 'Sonstiges').firstOrNull;
      if (rule == null && prior == null && guessed != 'Sonstiges')
        smartIds.add(id);
      added.add(Transaction(
        id: id,
        amountCents: b.amountCents.abs(),
        category: rule ?? prior ?? guessed,
        date: b.date,
        isIncome: isIncome,
        note: title,
        accountId: target,
      ));
    }

    // out of one account and into another on the same day: the user moved
    // their own money — only when notes look like a transfer (not rent+refund)
    for (var i = 0; i < added.length; i++) {
      final out = added[i];
      if (out.isIncome || out.category == Categories.transfer) continue;
      for (var j = 0; j < added.length; j++) {
        final into = added[j];
        if (!into.isIncome ||
            into.category == Categories.transfer ||
            into.accountId == out.accountId) continue;
        if (into.amountCents != out.amountCents ||
            !_sameDay(into.date, out.date)) continue;
        if (!_looksLikeTransfer(out.note, into.note)) continue;
        added[i] = out.withCategory(Categories.transfer);
        added[j] = into.withCategory(Categories.transfer);
        break;
      }
    }

    final smarter = added
        .where((t) =>
            smartIds.contains(t.id) &&
            t.category != Categories.transfer &&
            t.category != 'Sonstiges')
        .length;

    // every booking where it belongs now
    final movedIds = {for (final t in moved) t.id: t};
    final ledger = [for (final t in existing) movedIds[t.id] ?? t, ...added];
    final newIds = {for (final a in accounts) accountFor(a.uid)}..remove(null);
    final otherIds = {for (final a in others) a.id, ...newIds};
    int sumOn(String? account) => DB.balanceOf([
          for (final t in ledger)
            if ((t.accountId != null && otherIds.contains(t.accountId)
                    ? t.accountId
                    : null) ==
                account)
              t
        ]);

    final saved = {for (final a in others) a.id: a};
    final bankAccounts = <MoneyAccount>[];
    for (final a in accounts) {
      final id = accountFor(a.uid);
      if (id == null) continue;
      final name = a.name == null || a.name!.isEmpty
          ? bankName
          : (primary || a.name!.toLowerCase().contains(bankName.toLowerCase())
              ? a.name!
              : '$bankName ${a.name}');
      // a name or kind the user chose stays
      final mine = saved[id];
      bankAccounts.add((mine ??
              MoneyAccount(
                  id: id, name: name, kind: MoneyAccount.guessKind(name)))
          .copyWith(
              openingCents: a.balanceCents - sumOn(id),
              bank: bankName,
              iban: a.iban,
              link: link));
    }
    if (accounts.isEmpty && !primary) {
      final id = accountFor('')!;
      bankAccounts.add((saved[id] ?? MoneyAccount(id: id, name: bankName))
          .copyWith(
              openingCents: bankBalanceCents - sumOn(id),
              bank: bankName,
              link: link));
    }

    final mainBalance =
        accounts.isEmpty ? bankBalanceCents : accounts.first.balanceCents;
    return BankSyncResult(added, mainBalance - sumOn(null),
        moved: moved,
        accounts: bankAccounts,
        touchesMain: primary,
        smarter: smarter);
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static final _transferHint = RegExp(
      r'umbuchung|übertrag|uebertrag|eigen[üu]berweisung|transfer|sparen|tagesgeld',
      caseSensitive: false);

  // same counterparty, or an explicit transfer keyword — avoids rent+refund false positives
  static bool _looksLikeTransfer(String? a, String? b) {
    final na = (a ?? '').trim();
    final nb = (b ?? '').trim();
    if (na.isNotEmpty && na.toLowerCase() == nb.toLowerCase()) return true;
    return _transferHint.hasMatch(na) || _transferHint.hasMatch(nb);
  }

  // same day/amount/account/title under a fingerprint-style id → already imported
  static bool _fingerprintDuplicate(List<Transaction> existing,
      BankTransaction b, String? target, String prefix) {
    final title = _title(b);
    final income = b.amountCents >= 0;
    for (final t in existing) {
      if (!t.id.startsWith(prefix) || !t.id.contains('|')) continue;
      if (t.accountId != target) continue;
      if (t.amountCents != b.amountCents.abs() || t.isIncome != income)
        continue;
      if (!_sameDay(t.date, b.date)) continue;
      // Merchant.tidy can change casing (REWE → Rewe) — match on stable key
      if (Merchant.key(t.note ?? '') == Merchant.key(title)) return true;
    }
    return false;
  }

  // rails (PayPal/Karte) hide the real merchant in the purpose — surface that
  static String _title(BankTransaction b) =>
      Merchant.display(counterparty: b.counterparty, purpose: b.purpose);

  static String _dayKey(DateTime d, int cents, bool income) =>
      '${d.year}-${d.month}-${d.day}|$cents|$income';

  static String _key(String title, bool income) =>
      '${income ? '+' : '-'}${Merchant.key(title)}';

  // fetches, merges and stores every linked bank
  static Future<({int added, int smarter})> run() async {
    if (_inflight != null) return _inflight!;
    return _inflight = () async {
      try {
        final epoch = AccountIsolation.epoch;
        final accountId = AccountService.current.value?.id;
        final state = Settings.bankState;
        var added = 0;
        var smarter = 0;
        final links = [
          if (state.isNotEmpty)
            (state: state, bank: Settings.bankName, primary: true),
          for (final l in Settings.extraBanks)
            (state: l.state, bank: l.bank, primary: false),
        ];
        if (links.isEmpty) return (added: 0, smarter: 0);
        for (final l in links) {
          final data = await BackendService.sync(l.state);
          if (!AccountIsolation.sameEpoch(epoch)) return (added: 0, smarter: 0);
          if (AccountService.current.value?.id != accountId)
            return (added: 0, smarter: 0);
          if (l.primary && Settings.bankState != l.state)
            return (added: 0, smarter: 0);
          if (!l.primary && !Settings.extraBanks.any((e) => e.state == l.state))
            return (added: 0, smarter: 0);
          final accounts = preferGiroFirst(data.accounts);
          final result = merge(
            existing: DB.getTx(),
            incoming: data.transactions,
            bankBalanceCents: data.balanceCents,
            dismissed: DB.dismissedBankIds,
            accounts: accounts,
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
            // giro-first account balance next to its IBAN, not the sum of all accounts
            final shown = accounts.isNotEmpty
                ? accounts.first.balanceCents
                : data.balanceCents;
            await Settings.setBankBalanceCents(shown);
          }
          added += result.added.length;
          smarter += result.smarter;
        }
        if (!AccountIsolation.sameEpoch(epoch)) return (added: 0, smarter: 0);
        if (AccountService.current.value?.id != accountId)
          return (added: 0, smarter: 0);
        // smarter keyword rules also lift older "Sonstiges" bookings
        smarter += await CategoryRules.upgradeSonstiges();
        offerSmile(added: added, smarter: smarter);
        await Settings.setLastSync(DateTime.now());
        return (added: added, smarter: smarter);
      } finally {
        _inflight = null;
      }
    }();
  }

  // syncs quietly when linked and the last sync is older than [maxAge]
  static Future<void> refreshIfStale(
      {Duration maxAge = const Duration(hours: 4)}) async {
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
