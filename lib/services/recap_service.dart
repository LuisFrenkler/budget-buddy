// The numbers behind the monthly recap story: what went out, where most of
// it went, the favourite merchant, the savings rate and the change against
// the month before.
import '../utils/theme.dart';
import '../models/transaction.dart';
import 'contracts.dart';

class MonthRecap {
  final DateTime month;
  final int income;
  final int expenses;
  final int everydayExpenses; // without rent and subscriptions
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
    this.everydayExpenses = 0,
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
  // the highlights leave rent and subscriptions out, so the share does too
  int get topCategoryShare {
    final base = everydayExpenses > 0 ? everydayExpenses : expenses;
    return base <= 0 ? 0 : ((topCategoryCents / base) * 100).round();
  }
}

class RecapService {
  // the month a recap is shown for: the last complete one
  static DateTime recapMonth(DateTime now) => DateTime(now.year, now.month - 1);

  static MonthRecap? build(List<Transaction> tx, DateTime month) {
    bool inMonth(Transaction t, DateTime m) => t.date.year == m.year && t.date.month == m.month;
    // moving money to savings or the depot is neither income nor spending
    tx = [for (final t in tx) if (Categories.counts(t.category)) t];
    final these = tx.where((t) => inMonth(t, month)).toList();
    if (these.isEmpty) return null;
    final fixed = {
      for (final c in Contracts.detect(tx, now: DateTime(month.year, month.month + 1, 0)))
        for (final p in c.payments) p.id
    };
    final prev = DateTime(month.year, month.month - 1);

    int income = 0, expenses = 0, everyday = 0;
    final byCategory = <String, int>{};
    final merchants = <String, ({String name, int visits, int cents})>{};
    final byDay = <DateTime, int>{};
    for (final t in these) {
      if (t.isIncome) {
        income += t.amountCents;
        continue;
      }
      expenses += t.amountCents;
      // rent and subscriptions are no surprise: the highlights are about the rest
      if (fixed.contains(t.id)) continue;
      everyday += t.amountCents;
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
      everydayExpenses: everyday,
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
