// Savings rate: the share of income that was not spent.
//
// The headline uses the last three complete months. A running month is
// misleading on its own (the salary arrives at the start, spending spreads
// over the month), so it is shown separately as "bisher".
import '../utils/theme.dart';
import '../models/transaction.dart';

class MonthRate {
  final DateTime month;
  final int income;
  final int spent;
  final bool running;
  const MonthRate(this.month, this.income, this.spent, {this.running = false});

  int? get rate => income <= 0 ? null : ((income - spent) / income * 100).round();
}

class SavingsRate {
  static MonthRate _month(List<Transaction> tx, DateTime m, {bool running = false}) {
    var income = 0, spent = 0;
    for (final t in tx) {
      if (t.date.year != m.year || t.date.month != m.month || !Categories.counts(t.category)) continue;
      if (t.isIncome) {
        income += t.amountCents;
      } else {
        spent += t.amountCents;
      }
    }
    return MonthRate(m, income, spent, running: running);
  }

  // the running month first, then the three complete months before it
  static List<MonthRate> months(List<Transaction> tx, {DateTime? now}) {
    final today = now ?? DateTime.now();
    return [
      _month(tx, DateTime(today.year, today.month), running: true),
      for (var i = 1; i <= 3; i++) _month(tx, DateTime(today.year, today.month - i)),
    ];
  }

  // the headline: over the three complete months together
  static int? headline(List<Transaction> tx, {DateTime? now}) {
    final done = months(tx, now: now).where((m) => !m.running);
    final income = done.fold<int>(0, (s, m) => s + m.income);
    final spent = done.fold<int>(0, (s, m) => s + m.spent);
    return income <= 0 ? null : ((income - spent) / income * 100).round();
  }
}
