// database operations (transactions, badges, budgets)
import 'package:hive/hive.dart';
import 'settings_service.dart';
import '../models/transaction.dart';
import '../models/badge.dart';
import '../models/budget.dart';
import '../models/holding.dart';
import '../models/recurring.dart';
import '../utils/theme.dart';

class DB {
  static Box get _txBox => Hive.box('transactions');
  static Box get _badgeBox => Hive.box('badges');
  static Box get _budgetBox => Hive.box('budgets');
  static Box get _holdingBox => Hive.box('holdings');
  static Box get _recurringBox => Hive.box('recurring');

  // strips the time component so comparisons happen on calendar dates only
  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  // save a transaction (an undone delete of a bank booking brings it back for good)
  static Future<void> addTx(Transaction t) async {
    if (t.id.startsWith('bank_') && dismissedBankIds.contains(t.id)) {
      await Hive.box('settings').put('bankDismissed', (dismissedBankIds..remove(t.id)).toList());
    }
    await _txBox.put(t.id, t.toMap());
  }

  // delete a transaction; a deleted bank booking stays deleted on the next sync
  static Future<void> deleteTx(String id) async {
    if (id.startsWith('bank_') && Hive.isBoxOpen('settings')) {
      await Hive.box('settings').put('bankDismissed', (dismissedBankIds..add(id)).toList());
    }
    await _txBox.delete(id);
  }

  static Set<String> get dismissedBankIds => Hive.isBoxOpen('settings')
      ? ((Hive.box('settings').get('bankDismissed') as List?) ?? const []).cast<String>().toSet()
      : <String>{};
  
  // get all transactions, sorted by date (newest first)
  static List<Transaction> getTx() {
    final list = <Transaction>[];
    
    // convert each map from hive to Transaction object; skip any corrupt
    // record so one bad entry can't crash the whole list
    for (var m in _txBox.values) {
      try {
        list.add(Transaction.fromMap(Map<String, dynamic>.from(m)));
      } catch (_) {}
    }

    // sort newest first
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }
  
  // get transactions for a specific month
  static List<Transaction> getTxByMonth(DateTime month) => inMonth(getTx(), month);

  // --- pure helpers on an already loaded list ---
  // Screens load getTx() once per build and aggregate with these, instead of
  // re-reading and re-sorting the whole box for every single number.

  // the transactions of one calendar month
  static List<Transaction> inMonth(List<Transaction> list, DateTime month) {
    final result = <Transaction>[];
    for (var t in list) {
      if (t.date.year == month.year && t.date.month == month.month) {
        result.add(t);
      }
    }
    return result;
  }

  // sum of all incomes or all expenses in the list, in cents
  static int sumOf(List<Transaction> list, {required bool isIncome}) {
    int sum = 0;
    for (var t in list) {
      // transfers between own accounts are neither income nor spending;
      // a refund lowers spending instead of counting as income
      if (!Categories.counts(t.category)) continue;
      if (isIncome && t.isEarning) sum += t.amountCents;
      if (!isIncome && t.isSpending) sum += t.spendCents;
    }
    return sum;
  }

  // amounts per category for incomes or expenses, in cents
  static Map<String, int> categoriesOf(List<Transaction> list, {required bool isIncome}) {
    final result = <String, int>{};
    for (var t in list) {
      if (!Categories.counts(t.category)) continue;
      if (isIncome ? t.isEarning : t.isSpending) {
        // if category exists, add to it. otherwise start at 0
        result[t.category] = (result[t.category] ?? 0) + (isIncome ? t.amountCents : t.spendCents);
      }
    }
    // a category whose refunds cover its purchases has nothing left to show
    if (!isIncome) result.removeWhere((_, v) => v <= 0);
    return result;
  }

  // total income, in cents
  static int income({DateTime? month}) =>
      sumOf(month != null ? getTxByMonth(month) : getTx(), isIncome: true);

  // calculate total expenses, in cents
  static int expenses({DateTime? month}) =>
      sumOf(month != null ? getTxByMonth(month) : getTx(), isIncome: false);

  // balance, in cents
  static int balance({DateTime? month}) {
    return income(month: month) - expenses(month: month);
  }

  // group transactions by category and sum the amounts in cents (pie chart)
  static Map<String, int> byCategory({DateTime? month, required bool isIncome}) =>
      categoriesOf(month != null ? getTxByMonth(month) : getTx(), isIncome: isIncome);

  static Future<void> initBadges() async {
    // only create if box is empty
    if (_badgeBox.isEmpty) {
      for (var b in Badges.list) {
        final badge = Badge(
          id: b['id']!,
          name: b['name']!,
          description: b['desc']!,
          emoji: b['emoji']!,
        );
        await _badgeBox.put(badge.id, badge.toMap());
      }
    }
  }
  
  // get all badges
  static List<Badge> getBadges() {
    final list = <Badge>[];
    for (var m in _badgeBox.values) {
      try {
        list.add(Badge.fromMap(Map<String, dynamic>.from(m)));
      } catch (_) {}
    }
    return list;
  }
  
  // unlock a specific badge
  static Future<void> unlockBadge(String id) async {
    final m = _badgeBox.get(id);
    if (m != null) {
      final badge = Badge.fromMap(Map<String, dynamic>.from(m));
      if (!badge.isUnlocked) {
        badge.unlock();
        await _badgeBox.put(id, badge.toMap());
      }
    }
  }
  
  // check if user earned any new badges
  static Future<void> checkBadges() async {
    // badges may not exist yet, e.g. when data arrives before the home screen
    // ever opened (demo data from the onboarding)
    await initBadges();
    final tx = getTx();
    
    // first transaction added
    if (tx.isNotEmpty) {
      await unlockBadge('first');
    }
    
    // 50 or more transactions
    if (tx.length >= 50) {
      await unlockBadge('master');
    }
    
    // positive balance of at least 100 euro (10000 cents)
    if (balance() >= 10000) {
      await unlockBadge('saver');
    }
    
    // tracked on 7 different days
    final uniqueDays = <String>{};
    for (var t in tx) {
      uniqueDays.add('${t.date.year}-${t.date.month}-${t.date.day}');
    }
    if (uniqueDays.length >= 7) {
      await unlockBadge('week');
    }
  }

  // save a budget; a category with a budget again is no longer "stopped"
  static Future<void> addBudget(Budget b) async {
    final key = '${b.category}_${b.startDate.millisecondsSinceEpoch}';
    await _budgetBox.put(key, b.toMap());
    if (Hive.isBoxOpen('settings') && _stopped.contains(b.category)) {
      await Hive.box('settings').put('budgetsStopped', (_stopped..remove(b.category)).toList());
    }
  }

  // delete a budget; a deleted monthly budget does not come back next month
  static Future<void> deleteBudget(Budget b) async {
    final key = '${b.category}_${b.startDate.millisecondsSinceEpoch}';
    await _budgetBox.delete(key);
    if (isMonthly(b) && Hive.isBoxOpen('settings')) {
      await Hive.box('settings').put('budgetsStopped', (_stopped..add(b.category)).toList());
    }
  }

  static Set<String> get _stopped => Hive.isBoxOpen('settings')
      ? ((Hive.box('settings').get('budgetsStopped') as List?) ?? const []).cast<String>().toSet()
      : <String>{};

  // a budget over exactly one calendar month repeats every month
  static bool isMonthly(Budget b) {
    final start = _dateOnly(b.startDate);
    return start.day == 1 && _dateOnly(b.endDate) == DateTime(start.year, start.month + 1, 0);
  }

  // carries every monthly budget into the current month (same limit);
  // past months stay as they were. Returns how many were added.
  static Future<int> rollOverBudgets({DateTime? now}) async {
    final today = now ?? DateTime.now();
    final month = DateTime(today.year, today.month);
    final latest = <String, Budget>{};
    for (final b in getBudgets()) {
      if (!isMonthly(b)) continue;
      final current = latest[b.category];
      if (current == null || b.startDate.isAfter(current.startDate)) latest[b.category] = b;
    }
    final stopped = _stopped;
    var added = 0;
    for (final b in latest.values) {
      if (!b.startDate.isBefore(month) || stopped.contains(b.category)) continue;
      await _budgetBox.put('${b.category}_${month.millisecondsSinceEpoch}', Budget(
        category: b.category,
        limitCents: b.limitCents,
        startDate: month,
        endDate: DateTime(month.year, month.month + 1, 0),
      ).toMap());
      added++;
    }
    return added;
  }
  
  // get all budgets /calculate how much was spent
  static List<Budget> getBudgets() {
    final budgets = <Budget>[];
    for (var m in _budgetBox.values) {
      try {
        budgets.add(Budget.fromMap(Map<String, dynamic>.from(m)));
      } catch (_) {}
    }
    
    // purchases per category once, so each budget only walks its own;
    // refunds in the same category take some back
    final byCategory = <String, List<Transaction>>{};
    for (final t in getTx()) {
      if (t.isSpending) byCategory.putIfAbsent(t.category, () => []).add(t);
    }

    for (var b in budgets) {
      // compare on calendar dates only so a transaction's time-of-day can
      // never push it just outside the budget window
      final from = _dateOnly(b.startDate);
      final until = DateTime(b.endDate.year, b.endDate.month, b.endDate.day + 1); // the day after
      int spent = 0;
      for (final t in byCategory[b.category] ?? const <Transaction>[]) {
        if (!t.date.isBefore(from) && t.date.isBefore(until)) {
          spent += t.spendCents;
        }
      }
      b.spentCents = spent < 0 ? 0 : spent;
    }
    
    // sort newest first
    budgets.sort((a, b) => b.startDate.compareTo(a.startDate));
    return budgets;
  }

  // --- portfolio (holdings) ---

  // save a holding
  static Future<void> addHolding(Holding h) {
    return _holdingBox.put(h.id, h.toMap());
  }

  // delete a holding
  static Future<void> deleteHolding(String id) {
    return _holdingBox.delete(id);
  }

  // all holdings, most valuable first
  static List<Holding> getHoldings() {
    final list = <Holding>[];
    for (var m in _holdingBox.values) {
      try {
        list.add(Holding.fromMap(Map<String, dynamic>.from(m)));
      } catch (_) {}
    }
    list.sort((a, b) => b.valueCents.compareTo(a.valueCents));
    return list;
  }

  // total current market value of the portfolio, in cents
  static int portfolioValue() {
    int sum = 0;
    for (var h in getHoldings()) {
      sum += h.valueCents;
    }
    return sum;
  }

  // total amount invested across the portfolio, in cents
  static int portfolioInvested() {
    int sum = 0;
    for (var h in getHoldings()) {
      sum += h.investedCents;
    }
    return sum;
  }

  // total unrealised gain/loss, in cents
  static int portfolioGain() => portfolioValue() - portfolioInvested();

  // value per holding, for the allocation chart (in cents)
  static Map<String, int> holdingsAllocation() {
    final result = <String, int>{};
    for (var h in getHoldings()) {
      if (h.valueCents > 0) result[h.name] = h.valueCents;
    }
    return result;
  }

  // --- recurring rules ---

  static Future<void> addRule(RecurringRule r) => _recurringBox.put(r.id, r.toMap());
  static Future<void> updateRule(RecurringRule r) => _recurringBox.put(r.id, r.toMap());
  static Future<void> deleteRule(String id) => _recurringBox.delete(id);

  static List<RecurringRule> getRules() {
    final list = <RecurringRule>[];
    for (var m in _recurringBox.values) {
      try {
        list.add(RecurringRule.fromMap(Map<String, dynamic>.from(m)));
      } catch (_) {}
    }
    return list;
  }

  // delete everything and reset badges
  static Future<void> clearAll() async {
    await _txBox.clear();
    await _badgeBox.clear();
    await _budgetBox.clear();
    await _holdingBox.clear();
    await _recurringBox.clear();
    if (Hive.isBoxOpen('goals')) await Hive.box('goals').clear();
    if (Hive.isBoxOpen('splits')) await Hive.box('splits').clear();
    // the opening balance only makes sense together with the bookings
    if (Hive.isBoxOpen('settings')) {
      await Settings.setOpeningBalanceCents(0);
      await Settings.clearBank();
    }
    await initBadges();
  }
}
