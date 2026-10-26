import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/budget.dart';
import '../models/transaction.dart';
import '../services/account_service.dart';
import '../services/bank_sync.dart';
import '../services/db.dart';
import '../services/demo_data.dart';
import '../services/history.dart';
import '../services/settings_service.dart';
import '../services/insights_service.dart';
import '../services/price_service.dart';
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
    '1M': 'im letzten Monat',
    '3M': 'in 3 Monaten',
    '6M': 'in 6 Monaten',
    '1J': 'im letzten Jahr',
  };
  String _range = '1M';
  ChartPoint? _scrub;

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

  // pull to refresh: new bank bookings and current prices in one go
  Future<void> _refresh() async {
    HapticFeedback.selectionClick();
    String? problem;
    try {
      final added = await BankSync.run();
      if (added > 0 && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(duration: const Duration(milliseconds: 2800), content: Text('$added neue ${added == 1 ? 'Buchung' : 'Buchungen'}')));
      }
    } catch (_) {
      problem = 'Bank gerade nicht erreichbar';
    }
    try {
      await PriceService.refreshAll();
    } catch (_) {}
    await SplitService.refreshAll();
    await _loadDepot();
    if (problem != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(milliseconds: 2800), content: Text(problem)));
    }
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
          final cash = DB.sumOf(tx, isIncome: true) - DB.sumOf(tx, isIncome: false)
              + Settings.openingBalanceCents;
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
                  const RecapBanner(),
                  if (!OnboardingService.hidden && !OnboardingService.complete) ...[
                    const GettingStartedCard(),
                    const SizedBox(height: 24),
                  ],
                  // without the real balance a chart of "−3,20 €" would only confuse
                  if (!OnboardingService.balanceKnown && depotNow == 0)
                    _balancePrompt(cash)
                  else
                    ..._netWorth(tx, cash, depotNow),
                  const SizedBox(height: 28),
                  _accountsCard(tx, cash, depotNow),
                  ..._forecast(tx),
                  const SizedBox(height: 16),
                  const BuddyCard(),
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

  // what is still free this month; needs some income history
  List<Widget> _forecast(List<Transaction> tx) {
    final f = ForecastService.build(tx, goals: GoalsService.all());
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
                    style: TextStyle(fontSize: 13, color: total > 0 ? AppColors.positive : AppColors.textDim),
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
        Material(
          color: AppColors.surfaceAlt,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
            child: SizedBox(
              width: 40,
              height: 40,
              child: Center(child: _initial()),
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
        from: DateTime(now.year, now.month, now.day - (_days - 1)), opening: Settings.openingBalanceCents);
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
      ChartHeader(
        label: 'Gesamtvermögen',
        cents: cash + depotNow,
        startCents: points.isEmpty ? cash + depotNow : points.first.cents,
        period: _periods[_range]!,
        scrub: _scrub,
        startDate: points.isEmpty ? null : points.first.date,
      ),
      const SizedBox(height: 16),
      InteractiveChart(points: points, onScrub: (p) => setState(() => _scrub = p)),
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

    return Container(
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          _accountRow(
            icon: Icons.account_balance_wallet_rounded,
            color: AppColors.primary,
            title: Settings.bankName.isNotEmpty ? Settings.bankName : 'Konto',
            value: cash,
            change: '${Money.signed(monthNet)} im Monat',
            up: monthNet >= 0,
            onTap: () => widget.onOpen(1, segment: 0),
          ),
          Divider(height: 1, indent: 72, color: AppColors.border),
          _accountRow(
            icon: Icons.trending_up_rounded,
            color: AppColors.accentBlue,
            title: 'Depot',
            value: depotNow,
            change: invested == 0
                ? 'Noch keine Positionen'
                : '${Money.percent(gain / invested * 100, digits: 2)} gesamt',
            up: gain >= 0,
            onTap: () => widget.onOpen(2),
          ),
        ],
      ),
    );
  }

  Widget _accountRow({
    required IconData icon,
    required Color color,
    required String title,
    required int value,
    required String change,
    required bool up,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(change,
                      style: TextStyle(fontSize: 13, color: up ? AppColors.positive : AppColors.error),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: Settings.hideAmounts,
              builder: (_, hidden, __) => Text(hidden ? Money.hidden : Money.format(value),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
        height: 132,
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
    final budgets = DB.getBudgets()
        .where((b) => !today.isBefore(b.startDate) && today.isBefore(b.endDate.add(const Duration(days: 1))))
        .toList();
    if (budgets.isEmpty) return const [];
    return [
      const SizedBox(height: 28),
      SectionTitle('Budgets', action: 'Alle', onAction: () => widget.onOpen(1, segment: 1)),
      const SizedBox(height: 8),
      SizedBox(
        height: 150,
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
                          child: Text('${(b.spentCents / b.limitCents * 100).round()} %',
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
                  style: TextStyle(fontSize: 11, color: b.isOver ? AppColors.error : AppColors.textDim),
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
    final now = DateTime.now();
    final month = DB.inMonth(tx, now);
    final last = DB.inMonth(tx, DateTime(now.year, now.month - 1));
    final insights = InsightsService.generate(
      thisByCat: DB.categoriesOf(month, isIncome: false),
      lastByCat: DB.categoriesOf(last, isIncome: false),
      thisExpenses: DB.sumOf(month, isIncome: false),
      lastExpenses: DB.sumOf(last, isIncome: false),
    );
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
