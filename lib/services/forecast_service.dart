// "Was bleibt bis Monatsende?": how much is still free to spend this month,
// per day, and whether the current pace fits.
//
// free = usual monthly income − fixed costs − savings for goals
//        − what was already spent this month on everything else
//
// Fixed costs are the detected contracts (rent, subscriptions); the ones
// not yet booked this month are listed as still due. Income is the average
// of the regular sources (salary, Kindergeld, side job: paid in two of the last
// three complete months), so a bonus or a tax refund does not inflate it, and
// a salary that lands on the 31st instead of the 1st does not count twice.
//
// It never promises more than the account holds: with the balance known,
// "free" is at most the balance minus what is still due this month.
import '../utils/merchant.dart';
import '../utils/theme.dart';
import '../models/goal.dart';
import '../models/transaction.dart';
import 'contracts.dart';
import 'income_sources.dart';

enum ForecastPace { relaxed, tight, over }

// What-if knobs for the same forecast formula, never persisted.
class ForecastOverrides {
  final Set<String> excludedContractKeys; // Merchant.key(contract.name)
  final int oneTimeSpentCents;
  final int? incomeCents;
  final int? goalsMonthlyCents;

  const ForecastOverrides({
    this.excludedContractKeys = const {},
    this.oneTimeSpentCents = 0,
    this.incomeCents,
    this.goalsMonthlyCents,
  });

  bool get isEmpty =>
      excludedContractKeys.isEmpty &&
      oneTimeSpentCents == 0 &&
      incomeCents == null &&
      goalsMonthlyCents == null;
}

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
  final bool limitedByBalance; // the account holds less than the plan says
  final bool incomePreliminary; // only this month's earnings so far (no 3-month avg yet)

  const MonthForecast({
    required this.incomeCents,
    required this.fixedCents,
    required this.goalsCents,
    required this.spentCents,
    required this.freeCents,
    required this.daysLeft,
    required this.paceCents,
    required this.due,
    this.limitedByBalance = false,
    this.incomePreliminary = false,
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

  // [balanceCents]: the real account balance, when the user has told it
  // [overrides]: what-if knobs (cancel Abo, one-time buy, trim goals), same formula
  static MonthForecast? build(
    List<Transaction> tx, {
    List<Goal> goals = const [],
    DateTime? now,
    int? balanceCents,
    ForecastOverrides? overrides,
  }) {
    final o = overrides ?? const ForecastOverrides();
    final today = _day(now ?? DateTime.now());
    final monthStart = DateTime(today.year, today.month);
    final monthEnd = DateTime(today.year, today.month + 1, 0);
    final daysLeft = monthEnd.difference(today).inDays + 1;
    // moving money to savings or the depot is neither income nor spending
    tx = [for (final t in tx) if (Categories.counts(t.category)) t];
    if (tx.isEmpty) return null;
    final first = tx.map((t) => t.date).reduce((a, b) => a.isBefore(b) ? a : b);

    // usual income: the last three complete months the app knows about, all
    // of them counted, so a salary paid on the 31st (two in one month, none in
    // the next) averages out to one per month
    var incomeSum = 0;
    var months = 0;
    for (var m = 1; m <= 3; m++) {
      final start = DateTime(today.year, today.month - m);
      final end = DateTime(today.year, today.month - m + 1);
      // a month before the first booking says nothing
      if (!first.isBefore(end)) continue;
      months++;
      incomeSum += tx
          .where((t) => t.isEarning && !t.date.isBefore(start) && t.date.isBefore(end))
          .fold<int>(0, (s, t) => s + t.amountCents);
    }
    var incomePreliminary = false;
    late final int income;
    if (o.incomeCents != null) {
      income = o.incomeCents!;
    } else if (months == 0 || incomeSum == 0) {
      // week 1: only Gehalt this month, still show „noch frei“, labelled preliminary
      final monthLast = _day(monthEnd);
      final thisMonth = tx
          .where((t) =>
              t.isEarning &&
              !_day(t.date).isBefore(_day(monthStart)) &&
              !_day(t.date).isAfter(monthLast))
          .fold<int>(0, (s, t) => s + t.amountCents);
      if (thisMonth <= 0) return null;
      income = thisMonth;
      incomePreliminary = true;
    } else {
      // count on what comes every month (salary, Kindergeld, side job), not on
      // a bonus or a tax refund; if too little looks regular, the plain average
      final average = incomeSum ~/ months;
      final regular = months >= 2 ? IncomeSources.regularMonthly(IncomeSources.detect(tx, now: today)) : 0;
      income = regular >= average ~/ 2 && regular > 0 ? regular : average;
    }

    final allContracts = Contracts.detect(tx, now: today);
    // keep all payment ids as "fixed" so excluding an Abo doesn't inflate variable spend
    final fixedIds = {for (final c in allContracts) for (final p in c.payments) p.id};
    final contracts = [
      for (final c in allContracts)
        if (!o.excludedContractKeys.contains(Merchant.key(c.name))) c,
    ];
    final fixed = Contracts.monthlyTotal(contracts);

    // still due: contracts without a payment this month yet
    final due = <DueItem>[
      for (final c in contracts)
        if (c.last.date.isBefore(monthStart) && !c.nextDate.isAfter(monthEnd))
          DueItem(c.name, c.monthlyCents, c.nextDate.isBefore(today) ? today : c.nextDate),
    ]..sort((a, b) => a.date.compareTo(b.date));

    final goalsMonthly = o.goalsMonthlyCents ??
        goals
            .where((g) => !g.reached)
            // a fixed monthly amount the user chose wins over the computed need
            .map((g) => g.monthlyCents > 0 ? g.monthlyCents : (g.monthlyNeeded(today) ?? 0))
            .fold<int>(0, (s, v) => s + v);

    final spent = tx
            .where((t) => t.isSpending && !fixedIds.contains(t.id) && !t.date.isBefore(monthStart))
            .fold<int>(0, (s, t) => s + t.spendCents) +
        o.oneTimeSpentCents.clamp(0, 1 << 30);

    // the usual daily variable spending over the last 60 days, or over the
    // shorter time the app has known the user (at least a week)
    final known = today.difference(_day(first)).inDays.clamp(7, 60);
    final since = today.subtract(Duration(days: known));
    final recent = tx
        .where((t) => t.isSpending && !fixedIds.contains(t.id) && !t.date.isBefore(since) && t.date.isBefore(today))
        .fold<int>(0, (s, t) => s + t.spendCents);
    final pace = recent * daysLeft ~/ known;

    var free = income - fixed - goalsMonthly - spent;
    var limited = false;
    if (balanceCents != null) {
      final available = balanceCents - due.fold<int>(0, (s, d) => s + d.cents);
      if (available < free) {
        free = available;
        limited = true;
      }
    }

    return MonthForecast(
      incomeCents: income,
      fixedCents: fixed,
      goalsCents: goalsMonthly,
      spentCents: spent,
      freeCents: free,
      daysLeft: daysLeft,
      paceCents: pace,
      due: due,
      limitedByBalance: limited,
      incomePreliminary: incomePreliminary,
    );
  }
}
