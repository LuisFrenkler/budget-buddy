// Brings the bookings of a linked bank account into the app.
//
// - Every booking gets the stable id "bank_<id>", so syncing again never
//   duplicates and never overwrites a booking the user has edited.
// - New bookings get a category: the one the user last gave the same
//   counterparty, otherwise a keyword guess (see Categorizer).
// - The opening balance is set so the app's Kontostand equals the bank's,
//   even though the bank only hands out the last months of history.
import '../models/transaction.dart';
import 'backend_service.dart';
import 'categorizer.dart';
import 'category_rules.dart';
import 'db.dart';
import 'settings_service.dart';

class BankSyncResult {
  final List<Transaction> added;
  final int openingBalanceCents;
  const BankSyncResult(this.added, this.openingBalanceCents);
}

class BankSync {
  static const prefix = 'bank_';

  // pure merge step, separate from storage so it can be tested
  static BankSyncResult merge({
    required List<Transaction> existing,
    required List<BankTransaction> incoming,
    required int bankBalanceCents,
    Set<String> dismissed = const {}, // bank bookings the user deleted
  }) {
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
      ));
    }

    int sum = 0;
    for (final t in [...existing, ...added]) {
      sum += t.isIncome ? t.amountCents : -t.amountCents;
    }
    return BankSyncResult(added, bankBalanceCents - sum);
  }

  // the counterparty reads best ("REWE Markt GmbH"); the purpose is the fallback
  static String _title(BankTransaction b) {
    final party = b.counterparty.trim();
    if (party.isNotEmpty) return party;
    final purpose = b.purpose.trim();
    return purpose.isNotEmpty ? purpose : 'Bankbuchung';
  }

  static String _dayKey(DateTime d, int cents, bool income) => '${d.year}-${d.month}-${d.day}|$cents|$income';

  static String _key(String title, bool income) => '${income ? '+' : '-'}${title.toLowerCase().trim()}';

  // fetches, merges and stores; returns how many bookings are new
  static Future<int> run() async {
    final state = Settings.bankState;
    if (state.isEmpty) return 0;
    final data = await BackendService.sync(state);
    final result = merge(
        existing: DB.getTx(),
        incoming: data.transactions,
        bankBalanceCents: data.balanceCents,
        dismissed: DB.dismissedBankIds);
    for (final t in result.added) {
      await DB.addTx(t);
    }
    await Settings.setOpeningBalanceCents(result.openingBalanceCents);
    await Settings.setBankBalanceCents(data.balanceCents);
    await Settings.setLastSync(DateTime.now());
    await DB.checkBadges();
    return result.added.length;
  }

  // syncs quietly when linked and the last sync is older than [maxAge]
  static Future<void> refreshIfStale({Duration maxAge = const Duration(hours: 4)}) async {
    if (Settings.bankState.isEmpty) return;
    final last = Settings.lastSync;
    if (last != null && DateTime.now().difference(last) < maxAge) return;
    try {
      await run();
    } catch (_) {
      // offline or server not running: try again next start
    }
  }
}
