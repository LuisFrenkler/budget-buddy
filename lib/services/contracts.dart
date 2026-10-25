// Finds contracts and subscriptions in the bookings: payments to the same
// counterparty, about once a month, for about the same amount (rent, phone,
// streaming, gym, ...). Works on bank imports and manual entries alike.
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
  // how far amounts of one contract may differ from their median (15 %)
  static const _tolerance = 0.15;

  static List<Contract> detect(List<Transaction> tx, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final groups = <String, List<Transaction>>{};
    for (final t in tx) {
      final name = t.note?.trim() ?? '';
      if (t.isIncome || name.isEmpty) continue;
      groups.putIfAbsent(name.toLowerCase(), () => []).add(t);
    }

    final out = <Contract>[];
    for (final payments in groups.values) {
      if (payments.length < 3) continue;
      payments.sort((a, b) => a.date.compareTo(b.date));
      if (!_monthly(payments) || !_steadyAmount(payments)) continue;
      // ended contracts: nothing in the last 45 days
      if (today.difference(payments.last.date).inDays > 45) continue;
      out.add(Contract(payments.last.note!.trim(), payments.last.category, payments));
    }
    // largest first, like on a bank statement summary
    out.sort((a, b) => b.monthlyCents.compareTo(a.monthlyCents));
    return out;
  }

  static int monthlyTotal(List<Contract> contracts) => contracts.fold(0, (sum, c) => sum + c.monthlyCents);

  // one payment per month with gaps of roughly a month
  static bool _monthly(List<Transaction> p) {
    for (int i = 1; i < p.length; i++) {
      final gap = p[i].date.difference(p[i - 1].date).inDays;
      if (gap < 25 || gap > 36) return false;
    }
    return true;
  }

  static bool _steadyAmount(List<Transaction> p) {
    final amounts = [for (final t in p) t.amountCents]..sort();
    final median = amounts[amounts.length ~/ 2];
    if (median <= 0) return false;
    return amounts.every((a) => (a - median).abs() <= median * _tolerance);
  }
}
