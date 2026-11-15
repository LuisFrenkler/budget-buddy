// Bridge from everyday money to the next layer: emergency fund, debts,
// insurance inventory, and an honest net worth (cash + depot − debts).
import 'package:hive/hive.dart';
import '../models/transaction.dart';
import '../utils/money.dart';
import 'emergency_plan.dart';
import 'history.dart';
import 'money_accounts.dart';
import 'savings_rate.dart';
import '../l10n/l10n.dart';

class Debt {
  final String id;
  final String name;
  final int cents;
  const Debt({required this.id, required this.name, required this.cents});

  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'cents': cents};
  factory Debt.fromMap(Map m) => Debt(
        id: '${m['id']}',
        name: '${m['name'] ?? ''}',
        cents: (m['cents'] as num? ?? 0).toInt(),
      );
}

class Policy {
  final String id;
  final String name;
  final int monthlyCents;
  const Policy(
      {required this.id, required this.name, required this.monthlyCents});

  Map<String, dynamic> toMap() =>
      {'id': id, 'name': name, 'monthlyCents': monthlyCents};
  factory Policy.fromMap(Map m) => Policy(
        id: '${m['id']}',
        name: '${m['name'] ?? ''}',
        monthlyCents: (m['monthlyCents'] as num? ?? 0).toInt(),
      );
}

class EmergencyFund {
  final int targetCents; // 3 (or 6) lean months, see EmergencyPlan
  final int haveCents; // spar accounts + tagged cash
  final int fixedMonthlyCents;
  const EmergencyFund(
      {required this.targetCents,
      required this.haveCents,
      required this.fixedMonthlyCents});

  double get progress =>
      targetCents <= 0 ? 1 : (haveCents / targetCents).clamp(0.0, 1.0);
  int get missingCents => (targetCents - haveCents).clamp(0, targetCents);
  bool get ready => missingCents == 0 && targetCents > 0;
}

class Wealth {
  static Box get _box => Hive.box('settings');

  static List<Debt> debts() {
    final raw = (_box.get('wealthDebts') as List?) ?? const [];
    return [
      for (final m in raw)
        if (m is Map) Debt.fromMap(m),
    ];
  }

  static Future<void> saveDebts(List<Debt> list) =>
      _box.put('wealthDebts', [for (final d in list) d.toMap()]);

  static List<Policy> policies() {
    final raw = (_box.get('wealthPolicies') as List?) ?? const [];
    return [
      for (final m in raw)
        if (m is Map) Policy.fromMap(m),
    ];
  }

  static Future<void> savePolicies(List<Policy> list) =>
      _box.put('wealthPolicies', [for (final p in list) p.toMap()]);

  static int debtTotal() => debts().fold(0, (s, d) => s + d.cents);

  static int policyMonthly() =>
      policies().fold(0, (s, p) => s + p.monthlyCents);

  // cash + depot − debts (honest headline when debts are entered)
  static int netWorthCents({required int cashCents, required int depotCents}) =>
      cashCents + depotCents - debtTotal();

  /// One honest Start line when cash or net worth rose vs. seven days ago
  /// (end-of-day balances from [History]; optional [depotThenCents] for depot).
  static String? weekOverWeekPulse(
    List<Transaction> tx, {
    required int cashCents,
    required int depotCents,
    int? depotThenCents,
    int opening = 0,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final end = DateTime(today.year, today.month, today.day);
    final from = end.subtract(const Duration(days: 7));
    final cashPts =
        History.dailyBalance(tx, from: from, to: end, opening: opening);
    if (cashPts.length < 2) return null;

    final debts = debtTotal();
    final cashThen = cashPts.first.cents;
    final cashDelta = cashCents - cashThen;
    final netNow = netWorthCents(cashCents: cashCents, depotCents: depotCents);
    final int? netThen;
    if (depotThenCents != null) {
      netThen = cashThen + depotThenCents - debts;
    } else if (depotCents == 0) {
      netThen = cashThen - debts;
    } else {
      netThen = null;
    }
    final netDelta = netThen != null ? netNow - netThen : null;

    if (netDelta != null && netDelta > 0) {
      return tr('Nettovermögen +{x} seit letzter Woche', {'x': Money.format(netDelta)});
    }
    if (cashDelta > 0) {
      return tr('Konto +{x} seit letzter Woche', {'x': Money.format(cashDelta)});
    }
    return null;
  }

  static EmergencyFund emergency(List<Transaction> tx, {DateTime? now}) {
    // what a lean month really costs, times three (six with an unsteady income)
    final plan = EmergencyPlan.compute(tx, now: now);
    final monthly = plan.monthlyCents;
    final target = plan.targetCents;
    // spar accounts count toward the cushion; main giro does not (day-to-day)
    var have = 0;
    final allTx = tx;
    for (final a in MoneyAccounts.others) {
      if (a.kind == 'spar') have += MoneyAccounts.balanceOf(a, allTx);
    }
    // optional manual cushion on top (cash under the mattress, etc.)
    have += emergencyExtraCents;
    if (have < 0) have = 0;
    return EmergencyFund(
        targetCents: target, haveCents: have, fixedMonthlyCents: monthly);
  }

  static int get emergencyExtraCents =>
      Hive.isBoxOpen('settings') ? (_box.get('emergencyExtraCents') as num?)?.toInt() ?? 0 : 0;

  static Future<void> setEmergencyExtra(int cents) =>
      _box.put('emergencyExtraCents', cents < 0 ? 0 : cents);

  static int? savingsRatePercent(List<Transaction> tx, {DateTime? now}) =>
      SavingsRate.headline(tx, now: now);

  /// One calm line when last month saved a higher share than the month
  /// before. Null otherwise (the chart already shows the change in value).
  static String? moment({required List<Transaction> tx, DateTime? now}) {
    final months = SavingsRate.months(tx, now: now);
    if (months.length >= 3) {
      final last = months[1].rate;
      final prev = months[2].rate;
      if (last != null && prev != null && last > prev && last > 0) {
        return tr('Sparquote letzten Monat: {last} %, höher als im Monat davor', {'last': last});
      }
    }
    return null;
  }

  // months of variable spend the current cash covers (runway)
  static int? runwayMonths(List<Transaction> tx, int cashCents,
      {DateTime? now}) {
    if (cashCents <= 0) return null;
    final rate = SavingsRate.months(tx, now: now).where((m) => !m.running);
    final avgSpend = rate.isEmpty
        ? 0
        : rate.fold<int>(0, (s, m) => s + m.spent) ~/ rate.length;
    if (avgSpend <= 0) return null;
    return cashCents ~/ avgSpend;
  }

  // wipe keys with the rest of finance isolation
  static const settingKeys = [
    'wealthDebts',
    'wealthPolicies',
    'emergencyExtraCents',
    'vorsorge'
  ];
}
