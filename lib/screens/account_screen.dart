import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/transaction.dart';
import '../services/bank_sync.dart';
import '../services/db.dart';
import '../services/history.dart';
import '../services/settings_service.dart';
import '../utils/dates.dart';
import '../utils/money.dart';
import '../utils/theme.dart';
import '../widgets/interactive_chart.dart';
import '../widgets/segmented.dart';
import '../services/tx_search.dart';
import '../widgets/getting_started.dart';
import '../widgets/tx_row.dart';
import 'budget_screen.dart';
import 'stats_screen.dart';

// The account: balance with an interactive chart, then switchable sections
// for transactions, budgets and the monthly analysis.
class AccountScreen extends StatefulWidget {
  // 0 = Umsätze, 1 = Budgets, 2 = Analyse; shared so other tabs can jump here
  final ValueNotifier<int> segment;

  const AccountScreen({super.key, required this.segment});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  static const _ranges = ['1M', '3M', '6M', '1J', 'Max'];
  static const _periods = {
    '1M': 'im letzten Monat',
    '3M': 'in 3 Monaten',
    '6M': 'in 6 Monaten',
    '1J': 'im letzten Jahr',
    'Max': 'seit Beginn',
  };
  String _range = '3M';
  ChartPoint? _scrub;

  String _search = '';
  bool _searching = false;
  TxKind _kind = TxKind.all;

  // ids swiped away but not yet gone from the box, so the Dismissible
  // leaves the tree immediately instead of waiting for Hive's notification
  final _hidden = <String>{};

  DateTime _rangeStart(List<Transaction> tx) {
    final now = DateTime.now();
    switch (_range) {
      case '1M':
        return DateTime(now.year, now.month - 1, now.day);
      case '3M':
        return DateTime(now.year, now.month - 3, now.day);
      case '6M':
        return DateTime(now.year, now.month - 6, now.day);
      case '1J':
        return DateTime(now.year - 1, now.month, now.day);
      default:
        return History.firstDay(tx) ?? now;
    }
  }

  @override
  Widget build(BuildContext context) {
    // settings carry the linked bank, its last sync and the opening balance
    return ListenableBuilder(
      listenable: Listenable.merge([Hive.box('transactions').listenable(), Hive.box('settings').listenable()]),
      builder: (context, _) => ValueListenableBuilder<int>(
        valueListenable: widget.segment,
        builder: (context, segment, _) {
          final tx = DB.getTx().where((t) => !_hidden.contains(t.id)).toList();
          final balance = DB.sumOf(tx, isIncome: true) - DB.sumOf(tx, isIncome: false) + Settings.openingBalanceCents;
          final points = History.dailyBalance(tx, from: _rangeStart(tx), opening: Settings.openingBalanceCents);

          return SafeArea(
            bottom: false,
            // pull down to fetch new bookings from the linked bank
            child: RefreshIndicator(
              color: AppColors.primary,
              notificationPredicate: (_) => Settings.bankState.isNotEmpty,
              onRefresh: () => _SyncPill.sync(context),
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Text('Konto', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                            const Spacer(),
                            if (Settings.bankState.isNotEmpty)
                              const _SyncPill()
                            else
                              // kept by hand: the real balance can be set any time
                              TextButton.icon(
                                onPressed: () => showBalanceSheet(context),
                                icon: const Icon(Icons.edit_rounded, size: 16),
                                label: const Text('Kontostand anpassen'),
                                style: TextButton.styleFrom(foregroundColor: AppColors.textDim),
                              ),
                          ]),
                          const SizedBox(height: 20),
                          ChartHeader(
                            label: 'Kontostand',
                            cents: balance,
                            startCents: points.isEmpty ? balance : points.first.cents,
                            period: _periods[_range]!,
                            scrub: _scrub,
                            startDate: points.isEmpty ? null : points.first.date,
                            showPercent: false,
                          ),
                          const SizedBox(height: 16),
                          InteractiveChart(points: points, onScrub: (p) => setState(() => _scrub = p)),
                          const SizedBox(height: 12),
                          RangeSelector(
                            labels: _ranges,
                            selected: _range,
                            onChanged: (r) => setState(() => _range = r),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: PinnedHeader(
                      child: Segmented(
                        labels: const ['Umsätze', 'Budgets', 'Analyse'],
                        index: segment,
                        onChanged: (i) => widget.segment.value = i,
                      ),
                    ),
                  ),
                  if (segment == 0) ..._transactionSlivers(tx),
                  if (segment == 1)
                    const SliverPadding(
                      padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
                      sliver: SliverToBoxAdapter(child: BudgetView()),
                    ),
                  if (segment == 2)
                    const SliverPadding(
                      padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
                      sliver: SliverToBoxAdapter(child: StatsView()),
                    ),
                  // room for the floating navigation bar
                  const SliverToBoxAdapter(child: SizedBox(height: 110)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _transactionSlivers(List<Transaction> tx) {
    final rows = _groupByMonth(_filter(tx));
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
        sliver: SliverToBoxAdapter(
          child: _searching
              ? Padding(padding: const EdgeInsets.only(top: 8), child: _searchField())
              : Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _searching = true),
                    icon: const Icon(Icons.search_rounded, size: 18),
                    label: const Text('Suchen'),
                    style: TextButton.styleFrom(foregroundColor: AppColors.textDim),
                  ),
                ),
        ),
      ),
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
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverList.builder(
            itemCount: rows.length,
            itemBuilder: (_, i) {
              final r = rows[i];
              return r is _DayGroup ? _dayHeader(r) : _dismissible(r as Transaction);
            },
          ),
        ),
    ];
  }

  // search field, quick filters and what the hits add up to
  Widget _searchField() {
    final hits = _filter(DB.getTx());
    final active = _search.trim().isNotEmpty || _kind != TxKind.all;
    Widget chip(String label, TxKind k) => ChoiceChip(
          label: Text(label),
          selected: _kind == k,
          showCheckmark: false,
          side: BorderSide(color: _kind == k ? AppColors.primary : AppColors.border),
          selectedColor: AppColors.primary.withValues(alpha: 0.2),
          onSelected: (_) => setState(() => _kind = k),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(
        autofocus: true,
        onChanged: (v) => setState(() => _search = v),
        decoration: InputDecoration(
          hintText: 'Rewe, 23,75, über 100, Oktober …',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => setState(() {
              _searching = false;
              _search = '';
              _kind = TxKind.all;
            }),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Row(children: [
        chip('Alle', TxKind.all),
        const SizedBox(width: 8),
        chip('Ausgaben', TxKind.expenses),
        const SizedBox(width: 8),
        chip('Einnahmen', TxKind.income),
      ]),
      if (active) ...[
        const SizedBox(height: 10),
        Text(
          hits.isEmpty
              ? 'Keine Treffer'
              : '${hits.length} ${hits.length == 1 ? 'Umsatz' : 'Umsätze'} · zusammen ${Money.signed(TxSearch.total(hits))}',
          style: TextStyle(color: AppColors.textDim, fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ],
    ]);
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(Icons.receipt_long_rounded, size: 56, color: AppColors.textDim),
          const SizedBox(height: 16),
          const Text('Noch keine Umsätze', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Tippe auf + um deine erste Buchung zu erfassen.',
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim)),
        ],
      ),
    );
  }

  // filters transactions by the search text and the quick filters
  List<Transaction> _filter(List<Transaction> tx) => TxSearch.filter(tx, _search, kind: _kind);

  // flattens the (newest first) list into month headers followed by their rows
  // one group per day, newest first, like a banking app statement
  List<Object> _groupByMonth(List<Transaction> tx) {
    final rows = <Object>[];
    _DayGroup? group;
    for (final t in tx) {
      final day = DateTime(t.date.year, t.date.month, t.date.day);
      if (group == null || group.day != day) {
        group = _DayGroup(day);
        rows.add(group);
      }
      group.net += t.isIncome ? t.amountCents : -t.amountCents;
      group.count++;
      rows.add(t);
    }
    return rows;
  }

  static String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) return 'Heute';
    if (diff == 1) return 'Gestern';
    final label = '${Dates.weekdays[d.weekday - 1]}, ${Dates.dayMonth(d)}';
    return d.year == now.year ? label : '$label ${d.year}';
  }

  Widget _dayHeader(_DayGroup g) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 4),
      child: Row(
        children: [
          Text(_dayLabel(g.day),
              style: TextStyle(color: AppColors.textDim, fontSize: 13, fontWeight: FontWeight.w700)),
          const Spacer(),
          // with one booking the sum would only repeat its amount
          if (g.count > 1)
            Text(Money.signed(g.net),
              style: TextStyle(
                  color: g.net > 0 ? AppColors.positive : AppColors.textDim,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _dismissible(Transaction t) {
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
      child: TxRow(t, showDay: false),
    );
  }

  // deletes right away and offers an undo instead of asking first
  void _deleteTx(Transaction t) {
    HapticFeedback.mediumImpact();
    setState(() => _hidden.add(t.id));
    DB.deleteTx(t.id);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(persist: false, duration: const Duration(seconds: 5), 
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
}

// header row of one month in the transaction list
class _DayGroup {
  final DateTime day;
  int net = 0;
  int count = 0;
  _DayGroup(this.day);
}

// Small "ING · vor 3 Min." button next to the title of a linked account;
// tapping it fetches new bookings.
class _SyncPill extends StatefulWidget {
  const _SyncPill();

  // syncs and reports the outcome; shared with pull-to-refresh
  static Future<void> sync(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    String text;
    try {
      final added = await BankSync.run();
      text = added == 0 ? 'Alles aktuell' : '$added neue ${added == 1 ? 'Buchung' : 'Buchungen'}';
    } catch (_) {
      text = 'Bank gerade nicht erreichbar';
    }
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(duration: const Duration(milliseconds: 2800), content: Text(text)));
  }

  @override
  State<_SyncPill> createState() => _SyncPillState();
}

class _SyncPillState extends State<_SyncPill> {
  bool _busy = false;

  String get _when {
    final last = Settings.lastSync;
    if (last == null) return '';
    final d = DateTime.now().difference(last);
    if (d.inMinutes < 1) return ' · jetzt';
    if (d.inMinutes < 60) return ' · ${d.inMinutes} Min.';
    if (d.inHours < 24) return ' · ${d.inHours} Std.';
    return ' · ${Dates.dayMonth(last)}';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: _busy
            ? null
            : () async {
                HapticFeedback.selectionClick();
                setState(() => _busy = true);
                await _SyncPill.sync(context);
                if (mounted) setState(() => _busy = false);
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _busy
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.sync_rounded, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Text('${Settings.bankName}$_when',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textDim)),
          ]),
        ),
      ),
    );
  }
}
