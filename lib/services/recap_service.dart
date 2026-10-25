// The numbers behind the monthly recap story: what went out, where most of
// it went, the favourite merchant, the savings rate and the change against
// the month before.
import '../models/transaction.dart';

class MonthRecap {
  final DateTime month;
  final int income;
  final int expenses;
  final int previousExpenses;
  final String? topCategory;
  final int topCategoryCents;
  final String? topMerchant;
  final int topMerchantVisits;
  final int topMerchantCents;
  final int bookings;
  final DateTime? priciestDay;
  final int priciestDayCents;

  const MonthRecap({
    required this.month,
    required this.income,
    required this.expenses,
    required this.previousExpenses,
    required this.topCategory,
    required this.topCategoryCents,
    required this.topMerchant,
    required this.topMerchantVisits,
    required this.topMerchantCents,
    required this.bookings,
    required this.priciestDay,
    required this.priciestDayCents,
  });

  int get saved => income - expenses;
  // share of income that was not spent, in percent (0 without income)
  int get savingsRate => income <= 0 ? 0 : ((saved / income) * 100).round();
  // change of spending against the month before, in percent
  int? get expenseChange =>
      previousExpenses <= 0 ? null : (((expenses - previousExpenses) / previousExpenses) * 100).round();
  int get topCategoryShare => expenses <= 0 ? 0 : ((topCategoryCents / expenses) * 100).round();
}

class RecapService {
  // the month a recap is shown for: the last complete one
  static DateTime recapMonth(DateTime now) => DateTime(now.year, now.month - 1);

  static MonthRecap? build(List<Transaction> tx, DateTime month) {
    bool inMonth(Transaction t, DateTime m) => t.date.year == m.year && t.date.month == m.month;
    final these = tx.where((t) => inMonth(t, month)).toList();
    if (these.isEmpty) return null;
    final prev = DateTime(month.year, month.month - 1);

    int income = 0, expenses = 0;
    final byCategory = <String, int>{};
    final merchants = <String, ({String name, int visits, int cents})>{};
    final byDay = <DateTime, int>{};
    for (final t in these) {
      if (t.isIncome) {
        income += t.amountCents;
        continue;
      }
      expenses += t.amountCents;
      byCategory[t.category] = (byCategory[t.category] ?? 0) + t.amountCents;
      final day = DateTime(t.date.year, t.date.month, t.date.day);
      byDay[day] = (byDay[day] ?? 0) + t.amountCents;
      final name = t.note?.trim() ?? '';
      if (name.isNotEmpty) {
        final m = merchants[name.toLowerCase()];
        merchants[name.toLowerCase()] =
            (name: name, visits: (m?.visits ?? 0) + 1, cents: (m?.cents ?? 0) + t.amountCents);
      }
    }
    int previous = 0;
    for (final t in tx) {
      if (!t.isIncome && inMonth(t, prev)) previous += t.amountCents;
    }

    MapEntry<String, int>? top;
    for (final e in byCategory.entries) {
      if (top == null || e.value > top.value) top = e;
    }
    // the favourite place: most visits, then most money
    ({String name, int visits, int cents})? fav;
    for (final m in merchants.values) {
      if (fav == null || m.visits > fav.visits || (m.visits == fav.visits && m.cents > fav.cents)) fav = m;
    }
    MapEntry<DateTime, int>? priciest;
    for (final e in byDay.entries) {
      if (priciest == null || e.value > priciest.value) priciest = e;
    }

    return MonthRecap(
      month: month,
      income: income,
      expenses: expenses,
      previousExpenses: previous,
      topCategory: top?.key,
      topCategoryCents: top?.value ?? 0,
      topMerchant: fav?.name,
      topMerchantVisits: fav?.visits ?? 0,
      topMerchantCents: fav?.cents ?? 0,
      bookings: these.length,
      priciestDay: priciest?.key,
      priciestDayCents: priciest?.value ?? 0,
    );
  }
}
