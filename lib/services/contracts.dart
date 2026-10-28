// Finds contracts and subscriptions in the bookings: payments to the same
// counterparty, about once a month, for about the same amount (rent, phone,
// streaming, gym, ...). Works on bank imports and manual entries alike.
//
// Real life is a little messy, so the rules look at how a payment behaves
// lately: the latest amount may jump (that is the price rise worth reporting),
// one skipped debit doesn't end a contract, and the user can say "kein
// Vertrag" for a regular payment that isn't one (pocket money, a rent share).
import '../utils/merchant.dart';
import '../utils/theme.dart';
import 'package:hive/hive.dart';
import '../models/transaction.dart';

class Contract {
  final String name;
  final String category;
  final List<Transaction> payments; // oldest first

  const Contract(this.name, this.category, this.payments);

  Transaction get last => payments.last;

  // the latest amount, which is what the next payment will likely be
  int get monthlyCents => last.amountCents;

  // change of the latest payment against the one before, in cents
  int get priceChange => payments.length < 2 ? 0 : last.amountCents - payments[payments.length - 2].amountCents;

  // the next payment: one month after the last, same day where possible
  DateTime get nextDate {
    final d = last.date;
    final daysInNext = DateTime(d.year, d.month + 2, 0).day;
    return DateTime(d.year, d.month + 1, d.day > daysInNext ? daysInNext : d.day);
  }
}

class Contracts {
  // how far earlier amounts of one contract may differ from their median (15 %)
  static const _tolerance = 0.15;
  // how far the latest amount may move: a price rise, not a different purchase
  static const _latestTolerance = 0.6;

  // regular payments the user marked as "kein Vertrag"
  static Set<String> get hidden {
    if (!Hive.isBoxOpen('settings')) return const {};
    return ((Hive.box('settings').get('contractsHidden') as List?) ?? const []).cast<String>().toSet();
  }

  static Future<void> hide(String name, {bool hide = true}) async {
    final set = {...hidden};
    final key = Merchant.key(name);
    final legacy = name.toLowerCase().trim();
    if (hide) {
      if (key.isNotEmpty) set.add(key);
      set.add(legacy);
    } else {
      set.remove(key);
      set.remove(legacy);
    }
    await Hive.box('settings').put('contractsHidden', set.toList());
  }

  static List<Contract> detect(List<Transaction> tx, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final skip = hidden;
    final groups = <String, List<Transaction>>{};
    for (final t in tx) {
      final name = t.note?.trim() ?? '';
      // a monthly savings transfer is no contract to cancel
      if (t.isIncome || name.isEmpty || !Categories.counts(t.category)) continue;
      final key = Merchant.key(name);
      if (key.isEmpty || skip.contains(key) || skip.contains(name.toLowerCase())) continue;
      groups.putIfAbsent(key, () => []).add(t);
    }

    final out = <Contract>[];
    for (final payments in groups.values) {
      if (payments.length < 3) continue;
      payments.sort((a, b) => a.date.compareTo(b.date));
      if (!_monthly(payments) || !_steadyAmount(payments)) continue;
      // ended contracts: nothing in the last 45 days
      if (today.difference(payments.last.date).inDays > 45) continue;
      // prefer the latest tidy merchant name (PayPal *Netflix → Netflix)
      out.add(Contract(Merchant.tidy(payments.last.note!.trim()), payments.last.category, payments));
    }
    // largest first, like on a bank statement summary
    out.sort((a, b) => b.monthlyCents.compareTo(a.monthlyCents));
    return out;
  }

  static int monthlyTotal(List<Contract> contracts) => contracts.fold(0, (sum, c) => sum + c.monthlyCents);

  // lately one payment per month: the last three gaps are about a month,
  // one of them may be two (a debit the bank skipped or merged)
  static bool _monthly(List<Transaction> p) {
    var doubles = 0;
    for (int i = p.length - 1; i >= 1 && i >= p.length - 3; i--) {
      final gap = p[i].date.difference(p[i - 1].date).inDays;
      if (gap >= 25 && gap <= 36) continue;
      if (gap >= 52 && gap <= 70 && ++doubles == 1) continue;
      return false;
    }
    return true;
  }

  // the earlier payments agree; the latest may have moved (a price change)
  static bool _steadyAmount(List<Transaction> p) {
    final before = [for (final t in p.sublist(0, p.length - 1)) t.amountCents]..sort();
    final median = before[before.length ~/ 2];
    if (median <= 0) return false;
    if (!before.every((a) => (a - median).abs() <= median * _tolerance)) return false;
    return (p.last.amountCents - median).abs() <= median * _latestTolerance;
  }
}
