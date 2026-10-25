import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/budget.dart';
import '../models/transaction.dart';
import '../services/account_service.dart';
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
import 'budget_screen.dart';
import 'connections_screen.dart';
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
        listenable: Listenable.merge([Hive.box('budgets').listenable(), Hive.box('settings').listenable()]),
        builder: (context, _) {
          final tx = DB.getTx();
          final cash = DB.sumOf(tx, isIncome: true) - DB.sumOf(tx, isIncome: false)
              + Settings.openingBalanceCents;
          final depotNow = DB.portfolioValue();
          final empty = tx.isEmpty && depotNow == 0;

          return SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
              children: [
                _topBar(),
                const SizedBox(height: 24),
                if (empty)
                  _welcome()
                else ...[
                  ..._netWorth(tx, cash, depotNow),
                  const SizedBox(height: 28),
                  _accountsCard(tx, cash, depotNow),
                  ..._budgets(),
                  ..._insight(tx),
                  ..._recent(tx),
                ],
              ],
            ),
          );
        },
      ),
    );
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
  Widget _welcome() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Willkommen 👋', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('Verbinde dein Girokonto, dann kommen Kontostand und Umsätze von selbst. '
              'Oder erfasse deine Buchungen von Hand.',
              style: TextStyle(color: AppColors.textDim, height: 1.4)),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ConnectionsScreen())),
              icon: const Icon(Icons.account_balance_rounded, size: 20),
              label: const Text('Bankkonto verbinden'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.surfaceAlt, foregroundColor: AppColors.text),
              onPressed: () => TxRow.openEditor(context),
              child: const Text('Selbst erfassen'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => DemoData.load(),
              child: const Text('Mit Beispieldaten ausprobieren'),
            ),
          ),
        ],
      ),
    );
  }
}
