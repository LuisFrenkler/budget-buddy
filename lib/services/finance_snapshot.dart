// Compact summary Buddy may send off the device. Totals, a short recent
// list, holdings, goals, split balances, wealth and pension snapshots.
// No IBANs, no payment details, no full ledger. Hive stays in BuddyService
// so this build stays usable in tests.
import '../models/budget.dart';
import '../models/goal.dart';
import '../models/holding.dart';
import '../models/transaction.dart';
import '../utils/theme.dart';
import 'contracts.dart';
import 'forecast_service.dart';
import 'savings_rate.dart';
import 'vorsorge.dart';
import 'wealth.dart';

typedef AccountSnap = ({String name, String art, int cents});
typedef RecentSnap = ({String date, String category, int cents, String note, String account});
typedef RecurringSnap = ({
  String title,
  int cents,
  bool income,
  String category,
  String interval,
  bool active,
  String next,
});
typedef SplitSnap = ({
  String name,
  int myCents,
  List<({String name, int cents})> salden,
  List<({String von, String an, int cents})> ausgleich,
});
typedef PlusSnap = ({
  bool active,
  String? plan,
  bool trial,
  bool cancelled,
  String? bis,
  int? fragenRest,
  int? scansRest,
});

class FinanceSnapshot {
  static const plusOff = (
    active: false,
    plan: null,
    trial: false,
    cancelled: false,
    bis: null,
    fragenRest: null,
    scansRest: null,
  );

  final DateTime today;
  final int balanceCents;
  final int depotCents;
  final List<MonthSummary> months; // oldest first, the current month last
  final List<({String name, int cents, int count})> topMerchants; // this month
  final List<Budget> budgets; // current ones
  final List<Contract> contracts;
  final List<Holding> holdings;
  final List<AccountSnap> accounts;
  final List<RecentSnap> recent;
  final int bookingsThisMonth;
  final List<Goal> goals;
  final List<RecurringSnap> recurring;
  final List<SplitSnap> splits;
  final List<({String name, int cents})> debts;
  final List<({String name, int monthlyCents})> policies;
  final int? emergencyTargetCents;
  final int emergencyHaveCents;
  final int? savingsRatePercent;
  final int? runwayMonths;
  final VorsorgeResult? vorsorge; // null = not set up
  final PlusSnap plus;
  final MonthForecast? forecast;

  const FinanceSnapshot({
    required this.today,
    required this.balanceCents,
    required this.depotCents,
    required this.months,
    required this.topMerchants,
    required this.budgets,
    required this.contracts,
    required this.holdings,
    this.accounts = const [],
    this.recent = const [],
    this.bookingsThisMonth = 0,
    this.goals = const [],
    this.recurring = const [],
    this.splits = const [],
    this.debts = const [],
    this.policies = const [],
    this.emergencyTargetCents,
    this.emergencyHaveCents = 0,
    this.savingsRatePercent,
    this.runwayMonths,
    this.vorsorge,
    this.plus = plusOff,
    this.forecast,
  });

  MonthSummary get current => months.last;

  // complete months before the current one, for averages
  List<MonthSummary> get past => months.sublist(0, months.length - 1).where((m) => m.hasData).toList();

  int get avgIncome => past.isEmpty ? 0 : past.fold<int>(0, (s, m) => s + m.income) ~/ past.length;
  int get avgExpenses => past.isEmpty ? 0 : past.fold<int>(0, (s, m) => s + m.expenses) ~/ past.length;
  int get debtCents => debts.fold(0, (s, d) => s + d.cents);

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
    List<AccountSnap> accounts = const [],
    Map<String, String> accountNames = const {},
    List<Goal> goals = const [],
    List<RecurringSnap> recurring = const [],
    List<SplitSnap> splits = const [],
    List<({String name, int cents})> debts = const [],
    List<({String name, int monthlyCents})> policies = const [],
    int? emergencyTargetCents,
    int emergencyHaveCents = 0,
    VorsorgeResult? vorsorge,
    PlusSnap plus = plusOff,
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

    final sorted = [...tx]..sort((a, b) => b.date.compareTo(a.date));
    final recent = <RecentSnap>[
      for (final t in sorted.take(15))
        (
          date: _day(t.date),
          category: t.category,
          cents: t.isIncome ? t.amountCents : -t.amountCents,
          note: (t.note?.trim().isNotEmpty ?? false) ? t.note!.trim() : t.category,
          account: _accountName(t.accountId, accountNames),
        ),
    ];

    return FinanceSnapshot(
      today: today,
      balanceCents: balance,
      depotCents: depot,
      months: months,
      topMerchants: top.take(8).toList(),
      budgets: current,
      contracts: Contracts.detect(tx, now: today),
      holdings: holdings,
      accounts: accounts,
      recent: recent,
      bookingsThisMonth: tx.where((t) => t.date.year == today.year && t.date.month == today.month).length,
      goals: goals,
      recurring: recurring,
      splits: splits,
      debts: debts,
      policies: policies,
      emergencyTargetCents: emergencyTargetCents,
      emergencyHaveCents: emergencyHaveCents,
      savingsRatePercent: SavingsRate.headline(tx, now: today),
      runwayMonths: Wealth.runwayMonths(tx, balance, now: today),
      vorsorge: vorsorge,
      plus: plus,
      forecast: ForecastService.build(tx, goals: goals, now: today, balanceCents: balance),
    );
  }

  static String _accountName(String? id, Map<String, String> names) {
    if (id == null || id.isEmpty || id == 'main') return names['main'] ?? 'Konto';
    return names[id] ?? 'Konto';
  }

  static double _eur(int cents) => cents / 100;

  static String _day(DateTime d) => d.toIso8601String().substring(0, 10);

  static num _qty(double s) {
    if (s == s.roundToDouble()) return s.round();
    return num.parse(s.toStringAsFixed(6));
  }

  // the JSON Buddy reads (German keys, euros)
  Map<String, dynamic> toJson() {
    final ranked = [...holdings]..sort((a, b) => b.valueCents.compareTo(a.valueCents));
    final shownHoldings = ranked.take(30);
    final policyMonthly = policies.fold<int>(0, (s, p) => s + p.monthlyCents);
    return {
      'heute': _day(today),
      'kontostand': _eur(balanceCents),
      'depotwert': _eur(depotCents),
      'gesamtvermoegen': _eur(balanceCents + depotCents),
      'konten': [
        for (final a in accounts.take(8)) {'name': a.name, 'art': a.art, 'saldo': _eur(a.cents)}
      ],
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
      'buchungenDiesenMonat': bookingsThisMonth,
      'topHaendlerDiesenMonat': [
        for (final m in topMerchants) {'name': m.name, 'summe': _eur(m.cents), 'anzahl': m.count}
      ],
      'letzteBuchungen': [
        for (final t in recent.take(12))
          {
            'datum': t.date,
            'kategorie': t.category,
            'betrag': _eur(t.cents),
            'titel': t.note,
            'konto': t.account,
          }
      ],
      'budgets': [
        for (final b in budgets.take(20))
          {
            'kategorie': b.category,
            'limit': _eur(b.limitCents),
            'ausgegeben': _eur(b.spentCents),
            'prozent': b.percentUsed,
          }
      ],
      'vertraegeUndAbos': [
        for (final c in contracts.take(20))
          {
            'name': c.name,
            'proMonat': _eur(c.monthlyCents),
            'kategorie': c.category,
            'naechste': _day(c.nextDate),
          }
      ],
      if (contracts.length > 20) 'weitereVertraege': contracts.length - 20,
      'wiederkehrend': [
        for (final r in recurring.take(20))
          {
            'titel': r.title,
            'betrag': _eur(r.cents),
            'einnahme': r.income,
            'kategorie': r.category,
            'intervall': r.interval,
            'aktiv': r.active,
            'naechstes': r.next,
          }
      ],
      'sparziele': [
        for (final g in goals.take(20))
          {
            'name': g.name,
            'emoji': g.emoji,
            'ziel': _eur(g.targetCents),
            'gespart': _eur(g.savedCents),
            'prozent': (g.progress * 100).round(),
            'erreicht': g.reached,
            if (g.deadline != null) 'frist': _day(g.deadline!),
            if (g.monthlyNeeded(today) != null) 'monatlichNoetig': _eur(g.monthlyNeeded(today)!),
            if (g.monthlyCents > 0) 'automatischMonat': _eur(g.monthlyCents),
            if (g.roundUp) 'aufrunden': true,
          }
      ],
      if (goals.length > 20) 'weitereZiele': goals.length - 20,
      'depot': [
        for (final h in shownHoldings)
          {
            'name': h.name,
            if (h.symbol.isNotEmpty) 'symbol': h.symbol,
            'typ': h.type,
            'stueck': _qty(h.shares),
            'wert': _eur(h.valueCents),
            'investiert': _eur(h.investedCents),
            'gewinn': _eur(h.gainCents),
            if (h.depot != null && h.depot!.isNotEmpty) 'depot': h.depot,
          }
      ],
      if (ranked.length > 30) 'weiterePositionen': ranked.length - 30,
      'vermoegen': {
        'netto': _eur(balanceCents + depotCents - debtCents),
        'schuldenGesamt': _eur(debtCents),
        'schulden': [
          for (final d in debts.take(12)) {'name': d.name, 'betrag': _eur(d.cents)}
        ],
        'versicherungen': [
          for (final p in policies.take(12)) {'name': p.name, 'proMonat': _eur(p.monthlyCents)}
        ],
        'versicherungenMonat': _eur(policyMonthly),
        if (emergencyTargetCents != null) 'notgroschenZiel': _eur(emergencyTargetCents!),
        if (emergencyTargetCents != null || emergencyHaveCents > 0) 'notgroschenVorhanden': _eur(emergencyHaveCents),
        if (savingsRatePercent != null) 'sparquoteProzent': savingsRatePercent,
        if (runwayMonths != null) 'reichweiteMonate': runwayMonths,
      },
      'vorsorge': _vorsorgeJson(),
      'splits': [
        for (final g in splits.take(8))
          {
            'name': g.name,
            'meinSaldo': _eur(g.myCents),
            'salden': [
              for (final s in g.salden.take(8)) {'name': s.name, 'saldo': _eur(s.cents)}
            ],
            if (g.ausgleich.isNotEmpty)
              'ausgleich': [
                for (final a in g.ausgleich.take(6)) {'von': a.von, 'an': a.an, 'betrag': _eur(a.cents)}
              ],
          }
      ],
      'prognose': _forecastJson(),
      'plus': {
        'aktiv': plus.active,
        if (plus.plan != null) 'plan': plus.plan,
        'testphase': plus.trial,
        'gekuendigt': plus.cancelled,
        if (plus.bis != null) 'periodeBis': plus.bis,
        if (plus.fragenRest != null) 'gratisFragenUebrig': plus.fragenRest,
        if (plus.scansRest != null) 'gratisScansUebrig': plus.scansRest,
      },
    };
  }

  Map<String, dynamic> _vorsorgeJson() {
    final v = vorsorge;
    if (v == null) return {'eingerichtet': false};
    final i = v.input;
    return {
      'eingerichtet': true,
      'alter': i.age,
      'rentenalter': i.retireAge,
      'jahreBisRente': v.yearsLeft,
      'wunschNettoMonat': _eur(i.desiredNetCents),
      'gesetzlichMonat': _eur(i.statutoryCents),
      'betriebsrenteMonat': _eur(i.bavCents),
      'riesterMonat': _eur(i.riesterCents),
      'kapital': _eur(v.capitalCents),
      'kapitalAlsMonat': _eur(v.capitalAsMonthlyCents),
      'gedecktMonat': _eur(v.coveredMonthlyCents),
      'lueckeMonat': _eur(v.gapMonthlyCents),
      'extraSparenMonat': _eur(v.saveExtraMonthlyCents),
      'hinweis': 'Orientierung, keine Rentenberatung',
    };
  }

  Map<String, dynamic> _forecastJson() {
    final f = forecast;
    if (f == null) return {'vorhanden': false};
    return {
      'vorhanden': true,
      'ueblichesEinkommen': _eur(f.incomeCents),
      'fixkosten': _eur(f.fixedCents),
      'sparzieleMonat': _eur(f.goalsCents),
      'variabelAusgegeben': _eur(f.spentCents),
      'freiBisMonatsende': _eur(f.freeCents),
      'proTag': _eur(f.perDayCents),
      'tempo': switch (f.pace) {
        ForecastPace.relaxed => 'entspannt',
        ForecastPace.tight => 'knapp',
        ForecastPace.over => 'ueberzogen',
      },
      'nochFaellig': [
        for (final d in f.due.take(8)) {'name': d.name, 'betrag': _eur(d.cents), 'datum': _day(d.date)}
      ],
      'durchKontostandBegrenzt': f.limitedByBalance,
    };
  }
}

class MonthSummary {
  final DateTime month;
  final int income;
  final int expenses;
  final Map<String, int> byCategory;
  const MonthSummary(this.month, this.income, this.expenses, this.byCategory);

  bool get hasData => income > 0 || expenses > 0;
}
