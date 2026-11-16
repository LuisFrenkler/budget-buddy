// How big the Notgroschen should be, from the person's own money instead of a
// rule of thumb: what a month costs when only the necessary things keep
// running (rent, insurance, phone, energy, groceries, health, getting to
// work), times three months, or six when the income moves a lot. Streaming
// and other fun contracts are left out: in a bad month they get cancelled.
import '../models/transaction.dart';
import 'contracts.dart';

class EmergencyPart {
  final String name;
  final int cents; // per month
  final bool contract;
  const EmergencyPart(this.name, this.cents, {this.contract = false});
}

class EmergencyPlan {
  final List<EmergencyPart> fixed; // necessary contracts
  final List<EmergencyPart> living; // groceries, health, transport (average)
  final List<EmergencyPart> skipped; // contracts that could pause in a crisis
  final int months; // 3 or 6
  final bool irregularIncome;
  final bool fromAverage; // no contracts or categories, the plain average spend

  const EmergencyPlan({
    required this.fixed,
    required this.living,
    required this.skipped,
    required this.months,
    required this.irregularIncome,
    this.fromAverage = false,
    int averageCents = 0,
  }) : _average = averageCents;

  final int _average;

  int get fixedCents => fixed.fold(0, (s, p) => s + p.cents);
  int get livingCents => living.fold(0, (s, p) => s + p.cents);
  int get monthlyCents => fromAverage ? _average : fixedCents + livingCents;

  // rounded up to full 100 €, it is a goal people remember
  static int _round(int c) => c <= 0 ? 0 : ((c + 9999) ~/ 10000) * 10000;
  int get targetCents => _round(monthlyCents * months);
  int get lowCents => _round(monthlyCents * 3);
  int get highCents => _round(monthlyCents * 6);

  // what is needed in every month even when things go wrong
  static const essential = {'Lebensmittel', 'Wohnen', 'Gesundheit', 'Transport'};
  // contracts in these categories pause or get cancelled in a crisis
  static const optional = {'Unterhaltung', 'Essen & Trinken', 'Kleidung'};

  static EmergencyPlan compute(List<Transaction> tx, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final contracts = Contracts.detect(tx, now: today);
    final paid = {for (final c in contracts) for (final p in c.payments) p.id};
    final fixed = <EmergencyPart>[], skipped = <EmergencyPart>[];
    for (final c in contracts) {
      final part = EmergencyPart(c.name, c.monthlyCents, contract: true);
      (optional.contains(c.category) ? skipped : fixed).add(part);
    }

    // the last three complete months
    final first = DateTime(today.year, today.month - 3);
    final end = DateTime(today.year, today.month);
    final byCat = <String, int>{};
    final income = <int, int>{};
    var spent = 0;
    for (final t in tx) {
      if (t.date.isBefore(first) || !t.date.isBefore(end) || t.category == 'Umbuchung') continue;
      final m = t.date.year * 12 + t.date.month;
      if (t.isEarning) {
        income[m] = (income[m] ?? 0) + t.amountCents;
        continue;
      }
      spent += t.spendCents;
      if (!essential.contains(t.category) || paid.contains(t.id)) continue;
      byCat[t.category] = (byCat[t.category] ?? 0) + t.spendCents;
    }
    final living = [
      for (final e in byCat.entries)
        if (e.value > 0) EmergencyPart(e.key, e.value ~/ 3)
    ]..sort((a, b) => b.cents.compareTo(a.cents));

    // income that swings by more than a quarter between months: six months
    final values = income.values.toList();
    final irregular = values.length < 2 && values.isNotEmpty
        ? false
        : values.length >= 2 &&
            values.reduce((a, b) => a < b ? a : b) < values.reduce((a, b) => a > b ? a : b) * 0.75;

    final plan = EmergencyPlan(
      fixed: fixed,
      living: living,
      skipped: skipped,
      months: irregular ? 6 : 3,
      irregularIncome: irregular,
    );
    if (plan.monthlyCents > 0) return plan;
    // nothing to sort yet: the average month
    return EmergencyPlan(
      fixed: const [],
      living: const [],
      skipped: skipped,
      months: irregular ? 6 : 3,
      irregularIncome: irregular,
      fromAverage: true,
      averageCents: spent ~/ 3,
    );
  }
}
