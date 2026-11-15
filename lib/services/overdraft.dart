// Will the account go below zero before the next salary? The balance of
// today, minus the contracts still due before payday, minus what an
// ordinary day costs until then. Earlier than the month forecast: that one
// asks whether the month works out, this one whether the timing does.
import '../models/transaction.dart';
import 'contracts.dart';

class OverdraftRisk {
  final DateTime payday;
  final int lowestCents; // the expected balance just before payday (negative)
  final int dueCents; // contracts still to come before payday
  final List<String> dueNames;
  final int dailyCents;
  const OverdraftRisk(this.payday, this.lowestCents, this.dueCents, this.dueNames, this.dailyCents);
  int get shortCents => -lowestCents;
}

class Overdraft {
  // the day the salary usually comes, from the last three salaries; null without one
  static DateTime? nextPayday(List<Transaction> tx, DateTime today) {
    final salaries = tx.where((t) => t.isEarning && t.category == 'Gehalt' && t.amountCents >= 30000).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    if (salaries.isEmpty || today.difference(salaries.first.date).inDays > 45) return null;
    final days = salaries.take(3).map((t) => t.date.day).toList()..sort();
    final day = days[days.length ~/ 2];
    DateTime at(int y, int m) {
      final last = DateTime(y, m + 1, 0).day;
      return DateTime(y, m, day > last ? last : day);
    }

    // already paid this month: next month
    final paidThisMonth = salaries.first.date.year == today.year && salaries.first.date.month == today.month;
    final here = at(today.year, today.month);
    return !paidThisMonth && here.isAfter(today) ? here : at(today.year, today.month + 1);
  }

  static OverdraftRisk? check(List<Transaction> tx, {required int balanceCents, DateTime? now}) {
    final today = now ?? DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    final payday = nextPayday(tx, day);
    if (payday == null) return null;
    final days = payday.difference(day).inDays;
    if (days <= 0 || days > 35) return null;

    final contracts = Contracts.detect(tx, now: day);
    final due = [
      for (final c in contracts)
        if (c.nextDate.isAfter(day) && c.nextDate.isBefore(payday)) c
    ];
    final dueCents = due.fold<int>(0, (s, c) => s + c.monthlyCents);

    // an ordinary day: spending of the last 90 days without contracts and transfers
    final paid = {for (final c in contracts) for (final p in c.payments) p.id};
    var spent = 0;
    for (final t in tx) {
      if (t.isIncome || t.category == 'Umbuchung' || paid.contains(t.id)) continue;
      final age = day.difference(DateTime(t.date.year, t.date.month, t.date.day)).inDays;
      if (age < 1 || age > 90) continue;
      spent += t.amountCents;
    }
    final daily = spent ~/ 90;
    final lowest = balanceCents - dueCents - daily * days;
    if (lowest >= 0) return null;
    return OverdraftRisk(payday, lowest, dueCents, [for (final c in due.take(3)) c.name], daily);
  }
}
