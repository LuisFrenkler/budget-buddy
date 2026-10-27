// A compact summary of the user's finances for Buddy: totals per month and
// category, budgets, contracts, top merchants and the depot. No account
// numbers and no single bookings beyond merchant totals leave the device.
import '../utils/theme.dart';
import '../models/budget.dart';
import '../models/holding.dart';
import '../models/transaction.dart';
import 'contracts.dart';

class FinanceSnapshot {
  final DateTime today;
  final int balanceCents;
  final int depotCents;
  final List<MonthSummary> months; // oldest first, the current month last
  final List<({String name, int cents, int count})> topMerchants; // this month
  final List<Budget> budgets; // current ones
  final List<Contract> contracts;
  final List<Holding> holdings;

  const FinanceSnapshot({
    required this.today,
    required this.balanceCents,
    required this.depotCents,
    required this.months,
    required this.topMerchants,
    required this.budgets,
    required this.contracts,
    required this.holdings,
  });

  MonthSummary get current => months.last;

  // complete months before the current one, for averages
  List<MonthSummary> get past => months.sublist(0, months.length - 1).where((m) => m.hasData).toList();

  int get avgIncome => past.isEmpty ? 0 : past.fold<int>(0, (s, m) => s + m.income) ~/ past.length;
  int get avgExpenses => past.isEmpty ? 0 : past.fold<int>(0, (s, m) => s + m.expenses) ~/ past.length;

  // average per category over the past months
  Map<String, int> get avgByCategory {
    final sums = <String, int>{};
    for (final m in past) {
      m.byCategory.forEach((k, v) => sums[k] = (sums[k] ?? 0) + v);
    }
    return {for (final e in sums.entries) e.key: e.value ~/ (past.isEmpty ? 1 : past.length)};
  }

  int get daysLeftInMonth => DateTime(today.year, today.month + 1, 0).day - today.day;

  static FinanceSnapshot build({
    required List<Transaction> tx,
    required int openingCents,
    required List<Budget> budgets,
    required List<Holding> holdings,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    int balance = openingCents;
    for (final t in tx) {
      balance += t.isIncome ? t.amountCents : -t.amountCents;
    }

    final months = <MonthSummary>[];
    for (int i = 5; i >= 0; i--) {
      final start = DateTime(today.year, today.month - i);
      final inMonth = tx.where((t) => t.date.year == start.year && t.date.month == start.month);
      final byCategory = <String, int>{};
      int income = 0, expenses = 0;
      for (final t in inMonth) {
        if (!Categories.counts(t.category)) continue;
        if (t.isEarning) {
          income += t.amountCents;
        } else {
          expenses += t.spendCents;
          byCategory[t.category] = (byCategory[t.category] ?? 0) + t.spendCents;
        }
      }
      months.add(MonthSummary(start, income, expenses, byCategory));
    }

    final merchants = <String, ({String name, int cents, int count})>{};
    for (final t in tx) {
      final name = t.note?.trim() ?? '';
      if (t.isIncome || name.isEmpty || !Categories.counts(t.category) || t.date.year != today.year || t.date.month != today.month) continue;
      final key = name.toLowerCase();
      final m = merchants[key];
      merchants[key] = (name: name, cents: (m?.cents ?? 0) + t.amountCents, count: (m?.count ?? 0) + 1);
    }
    final top = merchants.values.toList()..sort((a, b) => b.cents.compareTo(a.cents));

    final current = budgets
        .where((b) => !b.startDate.isAfter(today) && !b.endDate.isBefore(DateTime(today.year, today.month, today.day)))
        .toList();

    int depot = 0;
    for (final h in holdings) {
      depot += h.valueCents;
    }

    return FinanceSnapshot(
      today: today,
      balanceCents: balance,
      depotCents: depot,
      months: months,
      topMerchants: top.take(8).toList(),
      budgets: current,
      contracts: Contracts.detect(tx, now: today),
      holdings: holdings,
    );
  }

  static double _eur(int cents) => cents / 100;

  // the JSON Buddy reads (German keys, euros)
  Map<String, dynamic> toJson() => {
        'heute': today.toIso8601String().substring(0, 10),
        'kontostand': _eur(balanceCents),
        'depotwert': _eur(depotCents),
        'gesamtvermoegen': _eur(balanceCents + depotCents),
        'monate': [
          for (final m in months)
            {
              'monat': '${m.month.year}-${m.month.month.toString().padLeft(2, '0')}',
              'einnahmen': _eur(m.income),
              'ausgaben': _eur(m.expenses),
              'ausgabenNachKategorie': {for (final e in m.byCategory.entries) e.key: _eur(e.value)},
            }
        ],
        'tageBisMonatsende': daysLeftInMonth,
        'topHaendlerDiesenMonat': [
          for (final m in topMerchants) {'name': m.name, 'summe': _eur(m.cents), 'anzahl': m.count}
        ],
        'budgets': [
          for (final b in budgets) {'kategorie': b.category, 'limit': _eur(b.limitCents), 'ausgegeben': _eur(b.spentCents)}
        ],
        'vertraegeUndAbos': [
          for (final c in contracts) {'name': c.name, 'proMonat': _eur(c.monthlyCents), 'kategorie': c.category}
        ],
        'depot': [
          for (final h in holdings)
            {'name': h.name, 'typ': h.type, 'wert': _eur(h.valueCents), 'investiert': _eur(h.investedCents)}
        ],
      };
}

class MonthSummary {
  final DateTime month;
  final int income;
  final int expenses;
  final Map<String, int> byCategory;
  const MonthSummary(this.month, this.income, this.expenses, this.byCategory);

  bool get hasData => income > 0 || expenses > 0;
}
