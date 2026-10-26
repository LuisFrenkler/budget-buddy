// "Was bleibt bis Monatsende?": how much is still free to spend this month,
// per day, and whether the current pace fits.
//
// free = usual monthly income − fixed costs − savings for goals
//        − what was already spent this month on everything else
//
// Fixed costs are the detected contracts (rent, subscriptions); the ones
// not yet booked this month are listed as still due. Income is the average
// of the last three complete months, so one bonus does not inflate it.
import '../models/goal.dart';
import '../models/transaction.dart';
import 'contracts.dart';

enum ForecastPace { relaxed, tight, over }

class DueItem {
  final String name;
  final int cents;
  final DateTime date;
  const DueItem(this.name, this.cents, this.date);
}

class MonthForecast {
  final int incomeCents; // usual monthly income
  final int fixedCents; // all fixed costs per month
  final int goalsCents; // monthly savings the goals need
  final int spentCents; // variable spending so far this month
  final int freeCents; // what is left for the rest of the month
  final int daysLeft; // including today
  final int paceCents; // spending at the usual pace until month end
  final List<DueItem> due; // fixed costs still to come this month

  const MonthForecast({
    required this.incomeCents,
    required this.fixedCents,
    required this.goalsCents,
    required this.spentCents,
    required this.freeCents,
    required this.daysLeft,
    required this.paceCents,
    required this.due,
  });

  int get perDayCents => daysLeft <= 0 ? freeCents : freeCents ~/ daysLeft;

  // the budget for variable spending this month
  int get variableBudgetCents => incomeCents - fixedCents - goalsCents;

  double get usedShare => variableBudgetCents <= 0 ? 1 : (spentCents / variableBudgetCents).clamp(0.0, 1.0);

  ForecastPace get pace {
    if (freeCents < 0) return ForecastPace.over;
    if (paceCents > freeCents) return ForecastPace.tight;
    return ForecastPace.relaxed;
  }
}

class ForecastService {
  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static MonthForecast? build(List<Transaction> tx, {List<Goal> goals = const [], DateTime? now}) {
    final today = _day(now ?? DateTime.now());
    final monthStart = DateTime(today.year, today.month);
    final monthEnd = DateTime(today.year, today.month + 1, 0);
    final daysLeft = monthEnd.difference(today).inDays + 1;

    // usual income: the last three complete months that had any
    final incomes = <int>[];
    for (var m = 1; m <= 3; m++) {
      final start = DateTime(today.year, today.month - m);
      final end = DateTime(today.year, today.month - m + 1);
      final sum = tx
          .where((t) => t.isIncome && !t.date.isBefore(start) && t.date.isBefore(end))
          .fold<int>(0, (s, t) => s + t.amountCents);
      if (sum > 0) incomes.add(sum);
    }
    if (incomes.isEmpty) return null;
    final income = incomes.reduce((a, b) => a + b) ~/ incomes.length;

    final contracts = Contracts.detect(tx, now: today);
    final fixedIds = {for (final c in contracts) for (final p in c.payments) p.id};
    final fixed = Contracts.monthlyTotal(contracts);

    // still due: contracts without a payment this month yet
    final due = <DueItem>[
      for (final c in contracts)
        if (c.last.date.isBefore(monthStart) && !c.nextDate.isAfter(monthEnd))
          DueItem(c.name, c.monthlyCents, c.nextDate.isBefore(today) ? today : c.nextDate),
    ]..sort((a, b) => a.date.compareTo(b.date));

    final goalsMonthly = goals
        .where((g) => !g.reached)
        .map((g) => g.monthlyNeeded(today) ?? 0)
        .fold<int>(0, (s, v) => s + v);

    final spent = tx
        .where((t) => !t.isIncome && !fixedIds.contains(t.id) && !t.date.isBefore(monthStart))
        .fold<int>(0, (s, t) => s + t.amountCents);

    // the usual daily variable spending over the last 60 days
    final since = today.subtract(const Duration(days: 60));
    final recent = tx
        .where((t) => !t.isIncome && !fixedIds.contains(t.id) && !t.date.isBefore(since) && t.date.isBefore(today))
        .fold<int>(0, (s, t) => s + t.amountCents);
    final pace = recent ~/ 60 * daysLeft;

    return MonthForecast(
      incomeCents: income,
      fixedCents: fixed,
      goalsCents: goalsMonthly,
      spentCents: spent,
      freeCents: income - fixed - goalsMonthly - spent,
      daysLeft: daysLeft,
      paceCents: pace,
      due: due,
    );
  }
}
