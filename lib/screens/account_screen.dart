import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../widgets/sync_pill.dart';
import '../models/money_account.dart';
import '../models/transaction.dart';
import '../services/money_accounts.dart';
import '../widgets/account_sheet.dart';
import '../widgets/add_account_choice.dart';
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
  final ScrollController? scroll;

  const AccountScreen({super.key, required this.segment, this.scroll});

  // the account shown, null = all together; new bookings go to it
  static final selected = ValueNotifier<String?>(null);

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  static const _ranges = ['1M', '3M', '6M', '1J', 'Max'];
  static const _periods = {
    '1M': 'in 30 Tagen',
    '3M': 'in 3 Monaten',
    '6M': 'in 6 Monaten',
    '1J': 'in 12 Monaten',
    'Max': 'seit Beginn',
  };
  String _range = '3M';
  // the point under the finger while scrubbing; only the chart header listens
  final _scrub = ValueNotifier<ChartPoint?>(null);

  String _search = '';
  bool _searching = false;
  TxKind _kind = TxKind.all;

  // ids swiped away but not yet gone from the box, so the Dismissible
  // leaves the tree immediately instead of waiting for Hive's notification
  final _hidden = <String>{};

  DateTime _rangeStart(List<Transaction> tx) {
    final now = DateTime.now();
    switch (_range) {
      // in days, like the labels say; "a month back" from the 31st would land
      // on the 3rd of the month before
      case '1M':
        return DateTime(now.year, now.month, now.day - 30);
      case '3M':
        return DateTime(now.year, now.month, now.day - 91);
      case '6M':
        return DateTime(now.year, now.month, now.day - 182);
      case '1J':
        return DateTime(now.year, now.month, now.day - 365);
      default:
        return History.firstDay(tx) ?? now;
    }
  }

  @override
  Widget build(BuildContext context) {
    // settings carry the linked bank, its last sync and the opening balance
    return ListenableBuilder(
      listenable: Listenable.merge(
          [Hive.box('transactions').listenable(), Hive.box('settings').listenable(), AccountScreen.selected]),
      builder: (context, _) => ValueListenableBuilder<int>(
        valueListenable: widget.segment,
        builder: (context, segment, _) {
          final all = DB.getTx().where((t) => !_hidden.contains(t.id)).toList();
          // one account, or all of them together
          // an account removed meanwhile falls back to all accounts
          final chosen = MoneyAccounts.byId(AccountScreen.selected.value);
          final account = MoneyAccounts.several ? (chosen ?? MoneyAccounts.main) : MoneyAccounts.main;
          final one = (AccountScreen.selected.value != null && chosen != null) || !MoneyAccounts.several;
          final tx = one ? MoneyAccounts.bookingsOf(account.id, all) : all;
          final opening = one ? MoneyAccounts.openingOf(account) : MoneyAccounts.openingTotal;
          final balance = DB.balanceOf(tx) + opening;
          final points = History.dailyBalance(tx, from: _rangeStart(tx), opening: opening);
          final synced = one ? account.link != null : Settings.bankState.isNotEmpty;

          return SafeArea(
            bottom: false,
            // pull down to fetch new bookings from the linked bank
            child: RefreshIndicator(
              color: AppColors.primary,
              notificationPredicate: (_) => Settings.bankState.isNotEmpty,
              onRefresh: () => _syncBank(context),
              child: CustomScrollView(
                controller: widget.scroll,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Text('Konto', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                            const SizedBox(width: 12),
                            // shrinks rather than overflows with large text or a long bank name
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: synced
                                      ? SyncPill(
                                          label: one ? (account.bank ?? Settings.bankName) : Settings.bankName,
                                          last: Settings.lastSync,
                                          onSync: () => _syncBank(context))
                                      : one
                                          // kept by hand: the real balance can be set any time
                                          ? TextButton.icon(
                                              onPressed: () => showBalanceSheet(context, account: account),
                                              icon: const Icon(Icons.edit_rounded, size: 16),
                                              label: const Text('Kontostand anpassen'),
                                              style: TextButton.styleFrom(foregroundColor: AppColors.textDim),
                                            )
                                          : const SizedBox.shrink(),
                                ),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 12),
                          _accountChips(all),
                          const SizedBox(height: 16),
                          ChartHeader(
                            label: one && MoneyAccounts.several ? account.name : 'Kontostand',
                            cents: balance,
                            startCents: points.isEmpty ? balance : points.first.cents,
                            period: _periods[_range]!,
                            scrubbing: _scrub,
                            startDate: points.isEmpty ? null : points.first.date,
                            showPercent: false,
                          ),
                          const SizedBox(height: 16),
                          InteractiveChart(points: points, onScrub: (p) => _scrub.value = p),
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

  // Alle · each account with its balance · + Konto; tapping the chosen one
  // again opens its settings
  Widget _accountChips(List<Transaction> all) {
    final accounts = MoneyAccounts.all;
    final selected = MoneyAccounts.several ? AccountScreen.selected.value : MoneyAccount.main;
    Widget chip(String label, bool active, VoidCallback onTap, {IconData? icon}) => Semantics(
          button: true,
          selected: active,
          child: Material(
            color: active ? AppColors.primary.withValues(alpha: 0.18) : AppColors.surface,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onTap,
              child: Container(
                constraints: const BoxConstraints(minHeight: 36),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: active ? AppColors.primary : AppColors.border),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (icon != null) ...[Icon(icon, size: 16, color: AppColors.primaryText), const SizedBox(width: 4)],
                  Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ),
        );
    return SizedBox(
      height: 38,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        if (accounts.length > 1) ...[
          chip('Alle', selected == null, () => AccountScreen.selected.value = null),
          const SizedBox(width: 8),
        ],
        for (final a in accounts) ...[
          chip('${a.name} · ${Money.format(MoneyAccounts.balanceOf(a, all))}', selected == a.id, () {
            HapticFeedback.selectionClick();
            if (selected == a.id) {
              showAccountSheet(context, account: a);
            } else {
              AccountScreen.selected.value = a.id;
            }
          }),
          const SizedBox(width: 8),
        ],
        // a real bank first, by hand second
        chip(MoneyAccounts.several ? 'Konto' : 'Konto oder Bank hinzufügen', false,
            () => showAddAccountChoice(context, byHand: () async {
              final added = await showAccountSheet(context);
              if (added != null) AccountScreen.selected.value = added.id;
            }), icon: Icons.add_rounded),
      ]),
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
                  color: g.net > 0 ? AppColors.positiveText : AppColors.textDim,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _dismissible(Transaction t) {
    return Dismissible(
      key: Key(t.id),
      // only allow swipe from right to left; bank bookings would come back with the next sync
      direction: t.id.startsWith(BankSync.prefix) ? DismissDirection.none : DismissDirection.endToStart,
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

// what a sync brought, in one sentence; shared with pull-to-refresh
Future<void> _syncBank(BuildContext context) async {
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
