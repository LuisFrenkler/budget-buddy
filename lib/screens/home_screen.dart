import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/db.dart';
import '../services/demo_data.dart';
import '../models/transaction.dart';
import '../utils/theme.dart';
import '../utils/money.dart';
import '../widgets/big_number.dart';
import '../widgets/line_chart.dart';
import 'add_screen.dart';
import 'budget_screen.dart';
import 'stats_screen.dart';
import 'depot_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // current tab index (0 = home, 1 = budget, 2 = stats, 3 = depot)
  int _tab = 0;

  // search text for filtering transactions
  String _search = '';
  bool _searching = false;

  // ids swiped away but not yet gone from the box, so the Dismissible
  // leaves the tree immediately instead of waiting for Hive's notification
  final _hidden = <String>{};

  static const _monthNames = ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
                              'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'];
  static const _shortMonths = ['Jan.', 'Feb.', 'März', 'Apr.', 'Mai', 'Juni',
                               'Juli', 'Aug.', 'Sep.', 'Okt.', 'Nov.', 'Dez.'];

  @override
  void initState() {
    super.initState();
    // create default badges if they dont exist yet
    DB.initBadges();
  }

  @override
  Widget build(BuildContext context) {
    // rebuild the whole shell (tabs, nav) when the theme mode toggles,
    // so every tab re-reads the current colors instead of keeping stale ones
    return ValueListenableBuilder<bool>(
      valueListenable: ThemeController.isDark,
      builder: (context, _, __) => Scaffold(
        body: IndexedStack(
          index: _tab,
          children: [
            _homeTab(),
            BudgetScreen(),
            StatsScreen(),
            DepotScreen(),
          ],
        ),
        // custom floating pill navigation with the add button in the middle
        bottomNavigationBar: _floatingNav(),
      ),
    );
  }

  // content
  Widget _homeTab() {
    return ValueListenableBuilder<Box>(
      valueListenable: Hive.box('transactions').listenable(),
      builder: (context, _, __) => ValueListenableBuilder<Box>(
        // the depot value is part of the net worth shown on top
        valueListenable: Hive.box('holdings').listenable(),
        builder: (context, _, __) {
          // load everything once and aggregate in memory
          final tx = DB.getTx().where((t) => !_hidden.contains(t.id)).toList();
          final cash = DB.sumOf(tx, isIncome: true) - DB.sumOf(tx, isIncome: false);
          final depot = DB.portfolioValue();
          final thisMonth = DB.inMonth(tx, DateTime.now());
          final monthNet = DB.sumOf(thisMonth, isIncome: true) - DB.sumOf(thisMonth, isIncome: false);
          final rows = _groupByMonth(_filter(tx));

          return SafeArea(
            bottom: false,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _topBar(),
                        const SizedBox(height: 28),
                        _summary(cash, depot, monthNet, thisMonth.isNotEmpty),
                        if (tx.length >= 2) ...[
                          const SizedBox(height: 20),
                          LineChart(_balanceSeries(tx), color: AppColors.primary, height: 110),
                        ],
                        const SizedBox(height: 28),
                        if (tx.isNotEmpty) _listHeader(),
                        if (_searching) ...[const SizedBox(height: 8), _searchField()],
                      ],
                    ),
                  ),
                ),

                // show empty message or the lazily built transaction list
                if (tx.isEmpty)
                  SliverToBoxAdapter(child: _emptyState())
                else if (rows.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(child: Text('Keine Treffer', style: TextStyle(color: AppColors.textDim))),
                    ),
                  )
                else
                  SliverPadding(
                    // bottom space so the last row clears the navigation bar
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
                    sliver: SliverList.builder(
                      itemCount: rows.length,
                      itemBuilder: (_, i) {
                        final r = rows[i];
                        return r is _MonthGroup ? _monthHeader(r) : _txRow(r as Transaction);
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  // wordmark on the left, profile avatar on the right (opens the profile)
  Widget _topBar() {
    return Row(
      children: [
        Text.rich(
          TextSpan(children: [
            TextSpan(text: 'Budget', style: TextStyle(color: AppColors.text)),
            const TextSpan(text: 'Buddy', style: TextStyle(color: AppColors.primary)),
          ]),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5),
        ),
        const Spacer(),
        Material(
          color: AppColors.surfaceAlt,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _openProfile,
            child: const SizedBox(
              width: 40,
              height: 40,
              child: Icon(Icons.person_rounded, color: AppColors.primary, size: 22),
            ),
          ),
        ),
      ],
    );
  }

  // big number on top: net worth (or cash balance without a depot)
  Widget _summary(int cash, int depot, int monthNet, bool hasMonth) {
    final hasDepot = depot > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BigNumber(
          label: hasDepot ? 'Gesamtvermögen' : 'Kontostand',
          cents: hasDepot ? cash + depot : cash,
          below: hasMonth ? ChangeLabel(cents: monthNet, suffix: 'diesen Monat') : null,
        ),
        if (hasDepot) ...[
          const SizedBox(height: 16),
          Row(children: [
            _splitPill('Konto', cash, AppColors.primary, null),
            const SizedBox(width: 10),
            _splitPill('Depot', depot, AppColors.accentBlue, () => setState(() => _tab = 3)),
          ]),
        ],
      ],
    );
  }

  // small tile showing one part of the net worth
  Widget _splitPill(String label, int cents, Color color, VoidCallback? onTap) {
    return Expanded(
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(fontSize: 12, color: AppColors.textDim)),
                    const SizedBox(height: 2),
                    Text(Money.format(cents),
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // running cash balance after each transaction day, oldest first
  List<double> _balanceSeries(List<Transaction> newestFirst) {
    final series = <double>[];
    int running = 0;
    DateTime? lastDay;
    for (final t in newestFirst.reversed) {
      running += t.isIncome ? t.amountCents : -t.amountCents;
      final day = DateTime(t.date.year, t.date.month, t.date.day);
      // one point per day: overwrite the point of the same day
      if (day == lastDay) {
        series[series.length - 1] = running / 100;
      } else {
        series.add(running / 100);
        lastDay = day;
      }
    }
    // keep the chart readable for long histories
    return series.length > 180 ? series.sublist(series.length - 180) : series;
  }

  // custom floating pill navigation bar
  Widget _floatingNav() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      height: 66,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _navItem(Icons.home_rounded, 'Start', 0),
          _navItem(Icons.account_balance_wallet_rounded, 'Budget', 1),
          Expanded(child: Center(child: _addButton())),
          _navItem(Icons.pie_chart_rounded, 'Statistik', 2),
          _navItem(Icons.trending_up_rounded, 'Depot', 3),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int i) {
    final active = _tab == i;
    final color = active ? AppColors.primary : AppColors.textDim;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_tab != i) HapticFeedback.selectionClick();
          setState(() => _tab = i);
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: color,
                    fontWeight: active ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      ),
    );
  }

  // round green add button in the middle of the navigation
  Widget _addButton() {
    return Material(
      color: AppColors.primary,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          HapticFeedback.lightImpact();
          _addTx();
        },
        child: const SizedBox(
          width: 48,
          height: 48,
          child: Icon(Icons.add_rounded, color: Colors.white, size: 28),
        ),
      ),
    );
  }

  // "Transaktionen" title with a search toggle
  Widget _listHeader() {
    return Row(
      children: [
        const Text('Transaktionen', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const Spacer(),
        IconButton(
          icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded, color: AppColors.textDim),
          onPressed: () => setState(() {
            _searching = !_searching;
            if (!_searching) _search = '';
          }),
        ),
      ],
    );
  }

  // text field to search/filter transactions
  Widget _searchField() {
    return TextField(
      autofocus: true,
      onChanged: (v) => setState(() => _search = v),
      decoration: const InputDecoration(
        hintText: 'Kategorie oder Beschreibung',
        prefixIcon: Icon(Icons.search_rounded),
      ),
    );
  }

  // shown when there are no transactions yet
  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 120),
      child: Column(
        children: [
          Icon(Icons.receipt_long_rounded, size: 56, color: AppColors.textDim),
          const SizedBox(height: 16),
          const Text('Noch keine Transaktionen', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Erfasse deine erste Buchung oder schau dir die App mit Beispieldaten an.',
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim, height: 1.4)),
          const SizedBox(height: 24),
          ElevatedButton(onPressed: _addTx, child: const Text('Transaktion hinzufügen')),
          const SizedBox(height: 8),
          TextButton(onPressed: _loadDemo, child: const Text('Mit Beispieldaten ausprobieren')),
        ],
      ),
    );
  }

  // filters transactions by the search text (category or note)
  List<Transaction> _filter(List<Transaction> tx) {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return tx;
    return tx
        .where((t) => t.category.toLowerCase().contains(q) || (t.note?.toLowerCase().contains(q) ?? false))
        .toList();
  }

  // flattens the (newest first) list into month headers followed by their rows
  List<Object> _groupByMonth(List<Transaction> tx) {
    final rows = <Object>[];
    _MonthGroup? group;
    for (final t in tx) {
      if (group == null || group.year != t.date.year || group.month != t.date.month) {
        group = _MonthGroup(t.date.year, t.date.month);
        rows.add(group);
      }
      group.net += t.isIncome ? t.amountCents : -t.amountCents;
      rows.add(t);
    }
    return rows;
  }

  Widget _monthHeader(_MonthGroup g) {
    final name = _monthNames[g.month - 1];
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 6),
      child: Row(
        children: [
          Text(g.year == DateTime.now().year ? name : '$name ${g.year}',
              style: TextStyle(color: AppColors.textDim, fontSize: 13, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(Money.signed(g.net), style: TextStyle(color: AppColors.textDim, fontSize: 13)),
        ],
      ),
    );
  }

  // "Heute", "Gestern" or e.g. "5. Jan."
  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Heute';
    if (diff == 1) return 'Gestern';
    return '${d.day}. ${_shortMonths[d.month - 1]}';
  }

  // one calm transaction row: description as title, category and day below
  Widget _txRow(Transaction t) {
    final note = t.note?.trim() ?? '';
    final title = note.isNotEmpty ? note : t.category;
    final subtitle = note.isNotEmpty ? '${t.category} · ${_dayLabel(t.date)}' : _dayLabel(t.date);

    return Dismissible(
      key: Key(t.id),
      // only allow swipe from right to left
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(14)),
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      onDismissed: (_) => _deleteTx(t),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _addTx(tx: t),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              CategoryAvatar(t.category, isIncome: t.isIncome),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(fontSize: 13, color: AppColors.textDim),
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // income in green, expenses in the normal text color
              Text(
                t.amountText,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: t.isIncome ? AppColors.primary : AppColors.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openProfile() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
  }

  // opens the add/edit transaction screen
  void _addTx({Transaction? tx}) async {
    // navigate to add screen and wait for result
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AddScreen(tx: tx)),
    );

    // if transaction was saved, show success message
    if (result == true && mounted) {
      HapticFeedback.lightImpact();
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tx == null ? 'Hinzugefügt' : 'Aktualisiert'),
      ));
    }
  }

  // deletes right away and offers an undo instead of asking first
  void _deleteTx(Transaction t) {
    HapticFeedback.mediumImpact();
    setState(() => _hidden.add(t.id));
    DB.deleteTx(t.id);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text('${t.note?.trim().isNotEmpty == true ? t.note!.trim() : t.category} gelöscht'),
      action: SnackBarAction(
        label: 'Rückgängig',
        textColor: AppColors.primary,
        // re-add the exact same transaction (same id) to restore it
        onPressed: () async {
          await DB.addTx(t);
          if (mounted) setState(() => _hidden.remove(t.id));
        },
      ),
    ));
  }

  Future<void> _loadDemo() async {
    await DemoData.load();
    if (mounted) setState(() {});
  }
}

// header row of one month in the transaction list
class _MonthGroup {
  final int year;
  final int month;
  int net = 0;
  _MonthGroup(this.year, this.month);
}
