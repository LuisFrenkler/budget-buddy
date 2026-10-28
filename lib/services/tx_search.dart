// Searching bookings the way people think about them: by merchant or
// category ("rewe", "essen"), by amount ("23,75", "über 100", "unter 10"),
// by month ("oktober") or by type ("einnahmen").
import '../models/transaction.dart';
import '../utils/dates.dart';
import '../utils/money.dart';

enum TxKind { all, expenses, income }

class TxSearch {
  static List<Transaction> filter(List<Transaction> tx, String query, {TxKind kind = TxKind.all, String? category}) {
    var list = tx.where((t) => switch (kind) {
          TxKind.all => true,
          // refunds count as spending (same as DB.sumOf / Forecast)
          TxKind.expenses => t.isSpending,
          TxKind.income => t.isEarning,
        });
    if (category != null) list = list.where((t) => t.category == category);

    var q = query.trim().toLowerCase();
    if (q.isEmpty) return list.toList();

    // words that filter the type
    if (RegExp(r'\beinnahme').hasMatch(q)) {
      list = list.where((t) => t.isEarning);
      q = q.replaceAll(RegExp(r'\beinnahmen?\b'), '').trim();
    } else if (RegExp(r'\bausgabe').hasMatch(q)) {
      list = list.where((t) => t.isSpending);
      q = q.replaceAll(RegExp(r'\bausgaben?\b'), '').trim();
    }

    // "über 100" / "ab 100" / "> 100" and "unter 10" / "< 10"
    final range = RegExp(r'(über|ueber|ab|mehr als|>|unter|bis|weniger als|<)\s*(\d[\d.,]*)').firstMatch(q);
    if (range != null) {
      final cents = Money.parseToCents(range.group(2)!) ?? 0;
      final above = ['über', 'ueber', 'ab', 'mehr als', '>'].contains(range.group(1));
      list = list.where((t) => above ? t.amountCents >= cents : t.amountCents <= cents);
      q = q.replaceRange(range.start, range.end, '').trim();
    }

    // a month name
    for (var m = 0; m < 12; m++) {
      final name = Dates.months[m].toLowerCase();
      if (q.contains(name)) {
        list = list.where((t) => t.date.month == m + 1);
        q = q.replaceAll(name, '').trim();
        break;
      }
    }

    // a plain amount: matches the booking's amount exactly
    final amount = RegExp(r'^\d+([.,]\d{1,2})?$').hasMatch(q) ? Money.parseToCents(q) : null;
    if (amount != null && (q.contains(',') || q.contains('.'))) {
      return list.where((t) => t.amountCents == amount).toList();
    }

    if (q.isEmpty) return list.toList();
    return list
        .where((t) =>
            t.category.toLowerCase().contains(q) ||
            (t.note?.toLowerCase().contains(q) ?? false) ||
            // whole euros: "24" finds 23,75 € and 24,00 € (rounded)
            (amount != null && (t.amountCents / 100).round() == amount ~/ 100))
        .toList();
  }

  static int total(List<Transaction> tx) => tx.fold(0, (s, t) => s + (t.isIncome ? t.amountCents : -t.amountCents));
}
