// Paying debts off in a sensible order. Every debt keeps its minimum rate;
// whatever is extra goes to one debt at a time: the most expensive interest
// first (avalanche), so the least money goes to interest. Debts without a
// known rate come after, smallest first (snowball), because a debt that is
// gone quickly keeps people going. When one is paid off, its rate rolls
// over to the next.
class DebtItem {
  final String name;
  final int cents;
  final double? ratePercent; // yearly interest, if known
  final int minCents; // monthly minimum
  const DebtItem(this.name, this.cents, {this.ratePercent, this.minCents = 0});
}

class DebtStep {
  final String name;
  final int month; // paid off after this many months
  final double? ratePercent;
  const DebtStep(this.name, this.month, this.ratePercent);
}

class DebtPlanResult {
  final List<DebtStep> order;
  final int months; // until all are gone (capped)
  final int interestCents;
  final bool tooSlow; // the payments do not even cover the interest
  const DebtPlanResult(this.order, this.months, this.interestCents, {this.tooSlow = false});
}

class DebtPlan {
  static const maxMonths = 360;

  static List<DebtItem> sorted(List<DebtItem> debts) {
    final known = debts.where((d) => d.ratePercent != null).toList()
      ..sort((a, b) => b.ratePercent!.compareTo(a.ratePercent!));
    final unknown = debts.where((d) => d.ratePercent == null).toList()..sort((a, b) => a.cents.compareTo(b.cents));
    return [...known, ...unknown];
  }

  static DebtPlanResult compute(List<DebtItem> debts, {int extraCents = 0}) {
    final order = sorted(debts.where((d) => d.cents > 0).toList());
    if (order.isEmpty) return const DebtPlanResult([], 0, 0);
    final left = {for (final d in order) d.name: d.cents.toDouble()};
    final budget = order.fold<int>(0, (s, d) => s + d.minCents) + extraCents;
    final done = <DebtStep>[];
    var interest = 0.0;
    var month = 0;
    while (left.values.any((v) => v > 0.5) && month < maxMonths) {
      month++;
      // interest first
      for (final d in order) {
        if (left[d.name]! <= 0) continue;
        final i = left[d.name]! * (d.ratePercent ?? 0) / 100 / 12;
        left[d.name] = left[d.name]! + i;
        interest += i;
      }
      // minimums, then everything left to the first open debt in the order
      var pot = budget.toDouble();
      for (final d in order) {
        if (left[d.name]! <= 0) continue;
        final pay = [d.minCents.toDouble(), left[d.name]!, pot].reduce((a, b) => a < b ? a : b);
        left[d.name] = left[d.name]! - pay;
        pot -= pay;
      }
      for (final d in order) {
        if (pot <= 0) break;
        if (left[d.name]! <= 0) continue;
        final pay = pot < left[d.name]! ? pot : left[d.name]!;
        left[d.name] = left[d.name]! - pay;
        pot -= pay;
      }
      for (final d in order) {
        if (left[d.name]! <= 0.5 && !done.any((x) => x.name == d.name)) {
          left[d.name] = 0;
          done.add(DebtStep(d.name, month, d.ratePercent));
        }
      }
    }
    final slow = left.values.any((v) => v > 0.5);
    return DebtPlanResult(done, month, interest.round(), tooSlow: slow);
  }
}
