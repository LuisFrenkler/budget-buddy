import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'account_screen.dart';
import '../models/money_account.dart';
import '../services/money_accounts.dart';
import '../widgets/sync_pill.dart';
import '../models/budget.dart';
import '../models/transaction.dart';
import '../services/buddy_tips.dart';
import '../services/account_service.dart';
import '../services/bank_sync.dart';
import '../services/db.dart';
import '../services/demo_data.dart';
import '../services/history.dart';
import '../services/settings_service.dart';
import '../services/insights_service.dart';
import '../services/price_service.dart';
import '../utils/dates.dart';
import '../utils/money.dart';
import '../utils/theme.dart';
import '../widgets/brand.dart';
import '../widgets/interactive_chart.dart';
import '../widgets/segmented.dart';
import '../widgets/tx_row.dart';
import 'buddy_screen.dart';
import 'budget_screen.dart';
import 'goals_screen.dart';
import 'recap_screen.dart';
import '../services/goals_service.dart';
import 'connections_screen.dart';
import 'contracts_screen.dart';
import 'subscription_screen.dart';
import 'splits_screen.dart';
import '../services/split_service.dart';
import '../services/hints_service.dart';
import '../services/plus_service.dart';
import '../widgets/hints_bell.dart';
import '../widgets/forecast_card.dart';
import '../widgets/getting_started.dart';
import '../services/onboarding_service.dart';
import '../services/forecast_service.dart';
import '../services/notification_service.dart';
import '../services/auto_save.dart';
import '../services/weekly_report.dart';
import 'weekly_report_screen.dart';
import 'profile_screen.dart';

// The start screen: total net worth with an interactive chart and a glance at
// account, depot, budgets and recent activity. Everything leads deeper.
class OverviewScreen extends StatefulWidget {
  // switch to another tab (1 = Konto, 2 = Depot), optionally to a section
  final void Function(int tab, {int? segment}) onOpen;

  const OverviewScreen({super.key, required this.onOpen});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  static const _ranges = {'1M': 30, '3M': 91, '6M': 182, '1J': 365};
  static const _periods = {
    '1M': 'in 30 Tagen',
    '3M': 'in 3 Monaten',
    '6M': 'in 6 Monaten',
    '1J': 'in 12 Monaten',
  };
  String _range = '1M';
  // the point under the finger while scrubbing; only the chart header listens
  final _scrub = ValueNotifier<ChartPoint?>(null);

  // depot value per day for the current range (loaded asynchronously)
  List<int>? _depot;

  int get _days => _ranges[_range]!;

  @override
  void initState() {
    super.initState();
    _loadDepot();
    Hive.box('holdings').listenable().addListener(_loadDepot);
  }

  @override
  void dispose() {
    Hive.box('holdings').listenable().removeListener(_loadDepot);
    super.dispose();
  }

  // the oldest of the fetched numbers behind the total: the bank's bookings
  // and the live prices; null when nothing comes from outside
  DateTime? _fetchedAt() {
    final times = [
      if (Settings.bankState.isNotEmpty && Settings.lastSync != null) Settings.lastSync!,
      for (final h in DB.getHoldings())
        if (h.priceAt != null) h.priceAt!,
    ];
    return times.isEmpty ? null : times.reduce((a, b) => a.isBefore(b) ? a : b);
  }

  // pull to refresh: new bank bookings and current prices in one go
  // always ends with one sentence on what happened, so pulling never feels ignored
  Future<void> _refresh() async {
    HapticFeedback.selectionClick();
    final parts = <String>[];
    var trouble = false;
    if (Settings.bankState.isNotEmpty) {
      try {
        final added = await BankSync.run();
        parts.add(added > 0 ? '$added neue ${added == 1 ? 'Buchung' : 'Buchungen'}' : 'Keine neuen Buchungen');
      } catch (_) {
        parts.add('Bank gerade nicht erreichbar');
        trouble = true;
      }
    }
    if (DB.getHoldings().isNotEmpty) {
      try {
        final r = await PriceService.refreshAll();
        if (r.live > 0) parts.add('Kurse aktualisiert');
      } catch (_) {
        parts.add('Kurse gerade nicht erreichbar');
        trouble = true;
      }
    }
    await SplitService.refreshAll();
    await _loadDepot();
    if (!mounted) return;
    final now = DateTime.now();
    final time = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(milliseconds: 2400),
      content: Text(parts.isEmpty ? 'Alles aktuell · Stand $time' : '${parts.join(' · ')} · Stand $time'),
      backgroundColor: trouble ? AppColors.warning : null,
    ));
  }

  Future<void> _loadDepot() async {
    final days = _days;
    final series = await PriceService.portfolioHistory(days: days);
    // ignore late results of a range that is no longer selected
    if (mounted && days == _days) setState(() => _depot = series);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box>(
      valueListenable: Hive.box('transactions').listenable(),
      // settings carry the linked bank and its opening balance
      builder: (context, _, __) => ListenableBuilder(
        listenable: Listenable.merge([
          Hive.box('budgets').listenable(),
          Hive.box('settings').listenable(),
          Hive.box('goals').listenable(),
          if (Hive.isBoxOpen('splits')) Hive.box('splits').listenable(),
        ]),
        builder: (context, _) {
          final tx = DB.getTx();
          // the money on every account together
          final cash = DB.balanceOf(tx) + MoneyAccounts.openingTotal;
          final depotNow = DB.portfolioValue();
          final empty = tx.isEmpty && depotNow == 0;
          // data changed: hints and reminders may have, too
          NotificationService.syncSoon();
          AutoSave.runSoon();

          return SafeArea(
            bottom: false,
            child: RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _refresh,
              child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
              children: [
                _topBar(),
                const SizedBox(height: 24),
                if (empty) ...[
                  _welcome(),
                  // joined a group before any own bookings: it still belongs here
                  ..._splits(),
                ] else ...[
                  if (DemoData.active) _demoBanner(),
                  const RecapBanner(),
                  if (!OnboardingService.hidden && !OnboardingService.complete) ...[
                    const GettingStartedCard(),
                    const SizedBox(height: 24),
                  ],
                  // without the real balance a chart of "−3,20 €" would only confuse
                  if (!OnboardingService.balanceKnown)
                    _balancePrompt(cash)
                  else
                    ..._netWorth(tx, cash, depotNow),
                  const SizedBox(height: 28),
                  _accountsCard(tx, cash, depotNow),
                  ..._forecast(tx, cash),
                  const SizedBox(height: 16),
                  BuddyCard(tip: BuddyTips.pick(tx: tx, budgets: DB.getBudgets())),
                  ..._weekly(tx),
                  const SizedBox(height: 16),
                  const ContractsCard(),
                  ..._splits(),
                  ..._goals(),
                  ..._budgets(),
                  ..._insight(tx),
                  ..._recent(tx),
                ],
              ],
            ),
            ),
          );
        },
      ),
    );
  }

  Widget _balancePrompt(int cash) {
    return Material(
      color: AppColors.primary.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => showBalanceSheet(context),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            const Icon(Icons.account_balance_wallet_rounded, color: AppColors.primary, size: 30),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Wie viel hast du gerade?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 2),
                Text('Trag deinen Kontostand ein, dann zeigt BudgetBuddy dein Vermögen und was frei ist.',
                    style: TextStyle(color: AppColors.textDim, fontSize: 13, height: 1.35)),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.primary),
          ]),
        ),
      ),
    );
  }

  // the room two lines of text need beyond their normal size at the user's text scale
  static double _extraTextHeight(BuildContext context) {
    final scaled = MediaQuery.textScalerOf(context).scale(13) - 13;
    return scaled <= 0 ? 0 : scaled * 2.4;
  }

  // sample data never passes for the user's own money
  Widget _demoBanner() => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            const Icon(Icons.science_rounded, color: AppColors.warning, size: 18),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Du siehst Beispieldaten', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
            ),
            TextButton(onPressed: _removeDemo, child: const Text('Entfernen')),
          ]),
        ),
      );

  Future<void> _removeDemo() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Beispieldaten entfernen?'),
        content: const Text('Alle Beispiel-Umsätze, -Budgets, -Ziele und das Beispiel-Depot verschwinden. '
            'Was du selbst eingetragen hast, bleibt.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Entfernen')),
        ],
      ),
    );
    if (ok != true) return;
    await DemoData.remove();
    HapticFeedback.mediumImpact();
    if (mounted) setState(() {});
  }

  // what is still free this month; needs some income history. With a known
  // balance it never promises more than the account holds.
  List<Widget> _forecast(List<Transaction> tx, int cash) {
    final f = ForecastService.build(tx,
        goals: GoalsService.all(), balanceCents: OnboardingService.balanceKnown ? cash : null);
    if (f == null) return [];
    return [const SizedBox(height: 16), ForecastCard(f)];
  }

  // shared spending, once there is a group
  List<Widget> _splits() {
    if (!Hive.isBoxOpen('splits') || SplitService.all().isEmpty) return [];
    final total = SplitService.myTotal();
    return [
      const SizedBox(height: 16),
      Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SplitsScreen())),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: const Color(0xFF14B8A6).withValues(alpha: 0.16), shape: BoxShape.circle),
                child: const Icon(Icons.call_split_rounded, color: Color(0xFF14B8A6), size: 21),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Geteilt', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  Text(
                    total == 0
                        ? 'Alles ausgeglichen'
                        : total > 0
                            ? 'Du bekommst ${Money.format(total)}'
                            : 'Du schuldest ${Money.format(-total)}',
                    style: TextStyle(fontSize: 13, color: total > 0 ? AppColors.positiveText : AppColors.textDim),
                  ),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
            ]),
          ),
        ),
      ),
    ];
  }

  // this week's report, until it has been opened
  List<Widget> _weekly(List<Transaction> tx) {
    final report = WeeklyReportService.build(tx);
    if (report == null || WeeklyReportScreen.seen(report)) return [];
    final change = report.change;
    return [
      const SizedBox(height: 16),
      Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () async {
            HapticFeedback.selectionClick();
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const WeeklyReportScreen()));
            if (mounted) setState(() {});
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.insights_rounded, color: AppColors.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Dein Wochenbericht · KW ${report.week}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(
                    change == null
                        ? '${Money.format(report.spentCents)} ausgegeben'
                        : (change * 100).round().abs() <= 3
                            ? '${Money.format(report.spentCents)} · wie immer'
                            : '${Money.format(report.spentCents)} · ${change > 0 ? '+' : '−'}${(change * 100).round().abs()} % zum Schnitt',
                    style: TextStyle(color: AppColors.textDim, fontSize: 13),
                  ),
                ]),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
            ]),
          ),
        ),
      ),
    ];
  }

  // takes the user to where a hint can be acted on
  void _openHint(HintTarget target) {
    Widget? page;
    switch (target) {
      case HintTarget.budgets:
        return widget.onOpen(1, segment: 1);
      case HintTarget.transactions:
        return widget.onOpen(1, segment: 0);
      case HintTarget.contracts:
        page = const ContractsScreen();
      case HintTarget.subscription:
        page = const SubscriptionScreen();
      case HintTarget.connections:
        page = const ConnectionsScreen();
      case HintTarget.goals:
        page = const GoalsScreen();
      case HintTarget.splits:
        page = const SplitsScreen();
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => page!));
  }

  // the signed-in user's initial, or a person for guests
  Widget _initial() {
    final name = AccountService.current.value?.name ?? '';
    if (name.isEmpty) return const Icon(Icons.person_rounded, color: AppColors.primary, size: 22);
    return Text(name[0].toUpperCase(),
        style: const TextStyle(color: AppColors.primary, fontSize: 17, fontWeight: FontWeight.w800));
  }

  // wordmark on the left, profile avatar on the right
  Widget _topBar() {
    return Row(
      children: [
        const BrandMark(size: 30),
        const SizedBox(width: 10),
        const Wordmark(size: 20),
        const Spacer(),
        HintsBell(
          hints: HintsService.current(
            tx: DB.getTx(),
            budgets: DB.getBudgets(),
            goals: GoalsService.all(),
            subscription: PlusService.subscription.value,
            bankValidUntil: Settings.bankValidUntil,
          ),
          onOpen: _openHint,
          onChanged: () => setState(() {}),
        ),
        // privacy mode: hide all balances with one tap
        ValueListenableBuilder<bool>(
          valueListenable: Settings.hideAmounts,
          builder: (_, hidden, __) => IconButton(
            tooltip: hidden ? 'Beträge zeigen' : 'Beträge verbergen',
            onPressed: () {
              HapticFeedback.selectionClick();
              Settings.setHideAmounts(!hidden);
            },
            icon: Icon(hidden ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: AppColors.textDim),
          ),
        ),
        const SizedBox(width: 4),
        Semantics(
          button: true,
          label: 'Profil',
          excludeSemantics: true,
          child: Material(
            color: AppColors.surfaceAlt,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
              // 44 pt: a comfortable tap target
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(child: _initial()),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // net worth headline, chart and range buttons
  List<Widget> _netWorth(List<Transaction> tx, int cash, int depotNow) {
    final now = DateTime.now();
    final cashPts = History.dailyBalance(tx,
        from: DateTime(now.year, now.month, now.day - (_days - 1)), opening: MoneyAccounts.openingTotal);
    final depot = _depot;
    final points = [
      for (int i = 0; i < cashPts.length; i++)
        ChartPoint(
          cashPts[i].date,
          // date-aligned depot history when loaded, today's value until then
          cashPts[i].cents + (depot != null && depot.length == cashPts.length ? depot[i] : depotNow),
        ),
    ];
    return [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: ChartHeader(
            label: 'Gesamtvermögen',
            cents: cash + depotNow,
            startCents: points.isEmpty ? cash + depotNow : points.first.cents,
            period: _periods[_range]!,
            scrubbing: _scrub,
            startDate: points.isEmpty ? null : points.first.date,
          ),
        ),
        SyncPill(last: _fetchedAt(), onSync: _refresh),
      ]),
      const SizedBox(height: 16),
      InteractiveChart(points: points, onScrub: (p) => _scrub.value = p),
      const SizedBox(height: 12),
      RangeSelector(
        labels: _ranges.keys.toList(),
        selected: _range,
        onChanged: (r) {
          setState(() {
            _range = r;
            _depot = null;
          });
          _loadDepot();
        },
      ),
    ];
  }

  // account and depot as two tappable rows
  Widget _accountsCard(List<Transaction> tx, int cash, int depotNow) {
    final month = DB.inMonth(tx, DateTime.now());
    final monthNet = DB.sumOf(month, isIncome: true) - DB.sumOf(month, isIncome: false);
    final invested = DB.portfolioInvested();
    final gain = depotNow - invested;
    final known = OnboardingService.balanceKnown;
    final hasHoldings = DB.getHoldings().isNotEmpty;

    return Container(
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          if (MoneyAccounts.several)
            // every account on its own line; a tap opens it on Konto
            for (final a in MoneyAccounts.all) ...[
              _accountRow(
                icon: a.kind == 'spar'
                    ? Icons.savings_rounded
                    : a.kind == 'bar'
                        ? Icons.payments_rounded
                        : Icons.account_balance_wallet_rounded,
                color: a.kind == 'spar' ? AppColors.positive : AppColors.primary,
                title: a.name,
                value: Money.format(MoneyAccounts.balanceOf(a, tx)),
                change: () {
                  final net = DB.balanceOf(MoneyAccounts.bookingsOf(a.id, month));
                  return net == 0 ? MoneyAccount.kinds[a.kind]! : '${Money.signed(net)} im ${Dates.month(DateTime.now())}';
                }(),
                up: null,
                onTap: () {
                  AccountScreen.selected.value = a.id;
                  widget.onOpen(1, segment: 0);
                },
              ),
              Divider(height: 1, indent: 72, color: AppColors.border),
            ]
          else ...[
            _accountRow(
              icon: Icons.account_balance_wallet_rounded,
              color: AppColors.primary,
              title: Settings.bankName.isNotEmpty ? Settings.bankName : 'Konto',
              // without the real balance the sum of bookings means nothing
              value: known ? Money.format(cash) : 'Eintragen',
              change: known ? '${Money.signed(monthNet)} im ${Dates.month(DateTime.now())}' : 'Kontostand fehlt noch',
              up: !known || monthNet == 0 ? null : monthNet > 0,
              onTap: () => widget.onOpen(1, segment: 0),
            ),
            Divider(height: 1, indent: 72, color: AppColors.border),
          ],
          _accountRow(
            icon: Icons.trending_up_rounded,
            color: AppColors.accentBlue,
            title: 'Depot',
            value: Money.format(depotNow),
            change: !hasHoldings
                ? 'Noch keine Positionen'
                : invested == 0
                    ? 'Ohne Kaufpreis'
                    : '${Money.percent(gain / invested * 100, digits: 2)} gesamt',
            up: !hasHoldings || invested == 0 || gain == 0 ? null : gain > 0,
            onTap: () => widget.onOpen(2),
          ),
        ],
      ),
    );
  }

  // [up]: null for plain information, which stays neutral; masked amounts
  // don't reveal their direction through colour either
  Widget _accountRow({
    required IconData icon,
    required Color color,
    required String title,
    required String value,
    required String change,
    required bool? up,
    required VoidCallback onTap,
  }) {
    final changeColor = up == null || Money.masked
        ? AppColors.textDim
        : up
            ? AppColors.positiveText
            : AppColors.errorText;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        // name and value on top, the change below across the full width,
        // so nothing is cut off on small phones
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(title,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis),
                    ),
                    Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 2),
                  Text(change, style: TextStyle(fontSize: 13, color: changeColor), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
          ],
        ),
      ),
    );
  }

  // savings goals as a row of rings, with a tile to start a new one
  List<Widget> _goals() {
    final goals = GoalsService.all();
    return [
      const SizedBox(height: 28),
      Row(children: [
        const Text('Sparziele', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const Spacer(),
        if (goals.isNotEmpty)
          TextButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GoalsScreen())),
            child: const Text('Alle'),
          ),
      ]),
      const SizedBox(height: 8),
      SizedBox(
        // grows with the system text size, so rings and names never clip
        height: 132 + _extraTextHeight(context),
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final g in goals)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Material(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GoalsScreen())),
                    child: SizedBox(
                      width: 128,
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        GoalRing(g, size: 58),
                        const SizedBox(height: 10),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(g.name,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        Text('${(g.progress * 100).round()} %', style: TextStyle(fontSize: 12, color: AppColors.textDim)),
                      ]),
                    ),
                  ),
                ),
              ),
            Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => addGoal(context),
                child: SizedBox(
                  width: 128,
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.15), shape: BoxShape.circle),
                      child: const Icon(Icons.add_rounded, color: AppColors.primary, size: 28),
                    ),
                    const SizedBox(height: 10),
                    const Text('Neues Ziel', style: TextStyle(fontWeight: FontWeight.w600)),
                    Text(goals.isEmpty ? 'z. B. Urlaub' : 'mit Sparplan', style: TextStyle(fontSize: 12, color: AppColors.textDim)),
                  ]),
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  // current budgets as small progress rings
  List<Widget> _budgets() {
    final today = DateTime.now();
    final budgets = DB.getBudgets().where((b) => b.covers(today)).toList();
    if (budgets.isEmpty) return const [];
    return [
      const SizedBox(height: 28),
      SectionTitle('Budgets', action: 'Alle', onAction: () => widget.onOpen(1, segment: 1)),
      const SizedBox(height: 8),
      SizedBox(
        height: 150 + _extraTextHeight(context),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: budgets.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, i) => _budgetRing(budgets[i]),
        ),
      ),
    ];
  }

  Widget _budgetRing(Budget b) {
    final color = budgetColor(b);
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => widget.onOpen(1, segment: 1),
        child: SizedBox(
          width: 128,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                SizedBox(
                  width: 64,
                  height: 64,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: b.progress),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, __) => Stack(
                      fit: StackFit.expand,
                      children: [
                        CircularProgressIndicator(
                          value: v,
                          strokeWidth: 6,
                          strokeCap: StrokeCap.round,
                          backgroundColor: AppColors.surfaceAlt,
                          valueColor: AlwaysStoppedAnimation(color),
                        ),
                        Center(
                          child: Text('${b.percentUsed} %',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(b.category,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    overflow: TextOverflow.ellipsis),
                Text(
                  b.isOver ? '${Money.format(b.spentCents - b.limitCents)} drüber' : '${Money.format(b.remainingCents)} übrig',
                  style: TextStyle(fontSize: 11, color: b.isOver ? AppColors.errorText : AppColors.textDim),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // the most relevant insight of this month, leads to the analysis
  List<Widget> _insight(List<Transaction> tx) {
    final insights = InsightsService.forMonth(tx, DateTime.now());
    if (insights.isEmpty) return const [];
    return [
      const SizedBox(height: 28),
      Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => widget.onOpen(1, segment: 2),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_rounded, color: AppColors.warning),
                const SizedBox(width: 12),
                Expanded(child: Text(insights.first, style: const TextStyle(height: 1.35))),
                Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _recent(List<Transaction> tx) {
    if (tx.isEmpty) return const [];
    return [
      const SizedBox(height: 28),
      SectionTitle('Letzte Umsätze', action: 'Alle', onAction: () => widget.onOpen(1, segment: 0)),
      for (final t in tx.take(4)) TxRow(t),
    ];
  }

  // first launch without any data
  // first start without data: a short hello, then the guided first steps
  Widget _welcome() {
    final name = AccountService.current.value?.firstName;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(name == null || name.isEmpty ? 'Willkommen 👋' : 'Hallo $name 👋',
          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
      const SizedBox(height: 6),
      Text('In fünf kurzen Schritten weiß BudgetBuddy, was du ausgeben kannst und wo du sparst.',
          style: TextStyle(color: AppColors.textDim, height: 1.4, fontSize: 15)),
      const SizedBox(height: 20),
      const GettingStartedCard(),
      const SizedBox(height: 12),
      TextButton.icon(
        onPressed: () => DemoData.load(),
        icon: const Icon(Icons.auto_awesome_rounded, size: 18),
        label: const Text('Erst mal mit Beispieldaten umschauen'),
      ),
    ]);
  }
}
