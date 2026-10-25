// Daily balance history for the interactive charts.
//
// Pure functions on an already loaded transaction list, so they are cheap and
// testable: the running cash balance at the end of every calendar day.
import '../models/transaction.dart';

// one point of a chart: a calendar day and a value in cents
class ChartPoint {
  final DateTime date;
  final int cents;
  const ChartPoint(this.date, this.cents);
}

class History {
  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  // balance at the end of each day from [from] to [to] (inclusive).
  // Transactions before [from] count towards the starting balance, on top
  // of [opening] (the balance before the very first transaction).
  static List<ChartPoint> dailyBalance(List<Transaction> tx, {required DateTime from, DateTime? to, int opening = 0}) {
    final start = _day(from);
    final end = _day(to ?? DateTime.now());
    if (end.isBefore(start)) return const [];

    // net change per day
    final perDay = <DateTime, int>{};
    int running = opening;
    for (final t in tx) {
      final delta = t.isIncome ? t.amountCents : -t.amountCents;
      final d = _day(t.date);
      if (d.isBefore(start)) {
        running += delta;
      } else {
        perDay[d] = (perDay[d] ?? 0) + delta;
      }
    }

    final points = <ChartPoint>[];
    for (var d = start; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) {
      running += perDay[d] ?? 0;
      points.add(ChartPoint(d, running));
    }
    return points;
  }

  // the first day that has a transaction, or null without any
  static DateTime? firstDay(List<Transaction> tx) {
    DateTime? first;
    for (final t in tx) {
      if (first == null || t.date.isBefore(first)) first = t.date;
    }
    return first == null ? null : _day(first);
  }
}
