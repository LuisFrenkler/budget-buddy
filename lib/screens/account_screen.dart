import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../widgets/sync_pill.dart';
import '../models/money_account.dart';
import '../models/transaction.dart';
import '../services/money_accounts.dart';
import '../widgets/account_sheet.dart';
import '../widgets/agent_bar.dart';
import '../widgets/add_account_choice.dart';
import '../services/bank_sync.dart';
import '../services/db.dart';
import '../services/history.dart';
import '../services/insights_service.dart';
import '../services/ledger_busy.dart';
import '../services/settings_service.dart';
import '../utils/dates.dart';
import '../utils/money.dart';
import '../utils/theme.dart';
import '../widgets/interactive_chart.dart';
import '../widgets/pressable.dart';
import '../widgets/segmented.dart';
import '../services/tx_search.dart';
import '../widgets/getting_started.dart';
import '../widgets/tx_row.dart';
import 'budget_screen.dart';
import 'connections_screen.dart';
import 'smart_entry_sheet.dart';
import 'stats_screen.dart';
import '../l10n/l10n.dart';

// The account: balance with an interactive chart, then switchable sections
// for transactions, budgets and the monthly analysis.
class AccountScreen extends StatefulWidget {
  // 0 = Umsätze, 1 = Budgets, 2 = Analyse; shared so other tabs can jump here
  final ValueNotifier<int> segment;
  final ScrollController? scroll;

  AccountScreen({super.key, required this.segment, this.scroll});

  // the account shown, null = all together; new bookings go to it
  static final selected = ValueNotifier<String?>(null);

  // Profil shortcuts into this tab: 1 = Budgets, 2 = Analyse. The shell reads it once.
  static final pendingSegment = ValueNotifier<int?>(null);

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  // 1T is yesterday against today; Max stays because the bookings are local
  static const _ranges = ['1T', '1W', '1M', '3M', '1J', 'Max']; // l10n: data
  String _range = '3M';
  // the point under the finger while scrubbing; only the chart header listens
  final _scrub = ValueNotifier<ChartPoint?>(null);

  String _search = '';
  bool _searching = false;
  TxKind _kind = TxKind.all;
  bool _sonstigesOnly = false;

  // ids swiped away but not yet gone from the box, so the Dismissible
  // leaves the tree immediately instead of waiting for Hive's notification
  final _hidden = <String>{};

  DateTime _rangeStart(List<Transaction> tx) {
    final now = DateTime.now();
    switch (_range) {
      // in days, like the labels say; "a month back" from the 31st would land
      // on the 3rd of the month before. 1T includes yesterday so the line exists.
      case '1T':
        return DateTime(now.year, now.month, now.day - 1);
      case '1W':
        return DateTime(now.year, now.month, now.day - 6);
      case '1M':
        return DateTime(now.year, now.month, now.day - 30);
      case '3M':
        return DateTime(now.year, now.month, now.day - 91);
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
      listenable: Listenable.merge([
        Hive.box('transactions').listenable(),
        Hive.box('settings').listenable(),
        AccountScreen.selected
      ]),
      builder: (context, _) => ValueListenableBuilder<int>(
        valueListenable: widget.segment,
        builder: (context, segment, _) {
          final all = DB.getTx().where((t) => !_hidden.contains(t.id)).toList();
          // one account, or all of them together
          // an account removed meanwhile falls back to all accounts
          final chosen = MoneyAccounts.byId(AccountScreen.selected.value);
          final account = MoneyAccounts.several
              ? (chosen ?? MoneyAccounts.main)
              : MoneyAccounts.main;
          final one =
              (AccountScreen.selected.value != null && chosen != null) ||
                  !MoneyAccounts.several;
          final tx = one ? MoneyAccounts.bookingsOf(account.id, all) : all;
          final opening = one
              ? MoneyAccounts.openingOf(account)
              : MoneyAccounts.openingTotal;
          // during vault/bank writes the live sum is briefly wrong; freeze the
          // Gesamtzahl. A single other-account row keeps live (can't reuse total).
          final live = DB.balanceOf(tx) + opening;
          final balance = (MoneyAccounts.several && one)
              ? live
              : LedgerBusy.cashOr(live);
          final points =
              History.dailyBalance(tx, from: _rangeStart(tx), opening: opening);
          final synced =
              one ? account.link != null : Settings.bankState.isNotEmpty;

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
                    padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _agentBar(tx),
                          // one quiet row under Ahead: the bank or the balance on the left, adding on the right
                          Row(children: [
                            // shrinks rather than overflows with large text or a long bank name
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: synced
                                      ? SyncPill(
                                          label: one
                                              ? (account.bank ??
                                                  Settings.bankName)
                                              : Settings.bankName,
                                          last: Settings.lastSync,
                                          onSync: () => _syncBank(context))
                                      : one
                                          // kept by hand: the real balance can be set any time
                                          ? TextButton.icon(
                                              onPressed: () => showBalanceSheet(
                                                  context,
                                                  account: account),
                                              icon: Icon(
                                                  Icons.edit_rounded,
                                                  size: 16),
                                              label: Text(
                                                  tr('Kontostand anpassen')),
                                              style: TextButton.styleFrom(
                                                  padding: EdgeInsets.zero,
                                                  foregroundColor:
                                                      AppColors.textDim),
                                            )
                                          : SizedBox.shrink(),
                                ),
                              ),
                            ),
                            // adding by hand: quick entry, receipt, keypad, transfer
                            TextButton.icon(
                              key: const Key('add-booking'),
                              style: TextButton.styleFrom(foregroundColor: AppColors.textDim),
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                HomeScreen.addMenu?.call();
                              },
                              icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                              // the word says what the plus adds
                              label: Text(tr('Buchung hinzufügen')),
                            ),
                          ]),

                          _accountChips(all),
                          SizedBox(height: 16),
                          ChartHeader(
                            label: one && MoneyAccounts.several
                                ? account.name
                                : tr('Kontostand'),
                            cents: balance,
                            startCents:
                                points.isEmpty ? balance : points.first.cents,
                            period: RangeSelector.periods[_range]!,
                            scrubbing: _scrub,
                            startDate:
                                points.isEmpty ? null : points.first.date,
                            showPercent: false,
                          ),
                          SizedBox(height: 16),
                          InteractiveChart(
                              points: points, onScrub: (p) => _scrub.value = p),
                          SizedBox(height: 12),
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
                        labels: [tr('Umsätze'), tr('Budgets'), tr('Analyse')],
                        index: segment,
                        onChanged: (i) => widget.segment.value = i,
                      ),
                    ),
                  ),
                  if (segment == 0) ..._transactionSlivers(tx),
                  if (segment != 0)
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (one && MoneyAccounts.several)
                                Padding(
                                  padding: EdgeInsets.only(bottom: 10),
                                  child: Text(
                                      tr('Für alle Konten.'),
                                      style: TextStyle(
                                          color: AppColors.textDim,
                                          fontSize: 13)),
                                ),
                              segment == 1 ? BudgetView() : StatsView(),
                            ]),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 40)),
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
    final selected = MoneyAccounts.several
        ? AccountScreen.selected.value
        : MoneyAccount.main;
    Widget chip(String label, bool active, VoidCallback onTap,
            {IconData? icon}) =>
        Semantics(
          button: true,
          selected: active,
          child: Material(
            color: active
                ? AppColors.primary.withValues(alpha: 0.18)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onTap,
              child: Container(
                constraints: const BoxConstraints(minHeight: 36),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: active ? AppColors.primary : AppColors.border),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16, color: AppColors.primaryText),
                    const SizedBox(width: 4)
                  ],
                  Text(label,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ),
        );
    return SizedBox(
      height: 38,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        if (accounts.length > 1) ...[
          chip(tr('Alle'), selected == null, () {
            AccountScreen.selected.value = null;
            setState(() => _sonstigesOnly = false);
          }),
          const SizedBox(width: 8),
        ],
        for (final a in accounts) ...[
          chip(
              MoneyAccounts.several
                  ? '${tr(a.name)} · ${Money.format(MoneyAccounts.balanceOf(a, all))}'
                  : tr(a.name),
              selected == a.id, () {
            HapticFeedback.selectionClick();
            if (selected == a.id) {
              showAccountSheet(context, account: a);
            } else {
              AccountScreen.selected.value = a.id;
              setState(() => _sonstigesOnly = false);
            }
          }),
          const SizedBox(width: 8),
        ],
        // a real bank first, by hand second
        chip(
            tr('Konto'),
            false,
            () => showAddAccountChoice(context, byHand: () async {
                  final added = await showAccountSheet(context);
                  if (added != null) AccountScreen.selected.value = added.id;
                }),
            icon: Icons.add_rounded),
      ]),
    );
  }

  // Ahead on Konto: bookings still waiting for a category first, then this
  // month against the last (or its biggest item); with neither, the plain offer
  Widget _agentBar(List<Transaction> tx) {
    final misc = _sonstigesCount(tx);
    if (misc > 0) {
      return AgentBar(
        line: misc == 1
            ? tr('**Eine Buchung** steckt noch in Sonstiges.')
            : tr('**{n} Buchungen** stecken noch in Sonstiges.', {'n': misc}),
        question: tr('Sonstiges aufräumen'),
      );
    }
    String? change;
    try {
      change = InsightsService.forMonth(tx, DateTime.now(), max: 1).firstOrNull;
    } catch (_) {}
    return change != null
        ? AgentBar(line: change, question: tr('Was fällt dir an meinen Ausgaben diesen Monat auf?'))
        : AgentBar(line: tr('Frag mich zu deinem Konto.'), question: tr('Was fällt dir an meinem Konto auf?'));
  }

  int _sonstigesCount(List<Transaction> tx) =>
      tx.where((t) => t.isSpending && t.category == 'Sonstiges').length;

  List<Widget> _transactionSlivers(List<Transaction> tx) {
    final rows = _groupByMonth(_filter(tx));
    final misc = _sonstigesCount(tx);
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
        sliver: SliverToBoxAdapter(
          child: _searching
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _searchField(tx))
              : Row(children: [
                  if (misc > 0)
                    FilterChip(
                      label: Text('${tr('Sonstiges')} · $misc'),
                      selected: _sonstigesOnly,
                      showCheckmark: false,
                      side: BorderSide(
                          color: _sonstigesOnly
                              ? AppColors.warning
                              : AppColors.border),
                      selectedColor: AppColors.warning.withValues(alpha: 0.18),
                      onSelected: (on) => setState(() => _sonstigesOnly = on),
                    ),
                  const Spacer(),
                  IconButton(
                    tooltip: tr('Suchen'),
                    onPressed: () => setState(() => _searching = true),
                    icon: Icon(Icons.search_rounded, color: AppColors.textDim),
                  ),
                ]),
        ),
      ),
      if (tx.isEmpty)
        SliverToBoxAdapter(child: _emptyState())
      else if (rows.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 40, 32, 32),
            child: Column(children: [
              Icon(Icons.search_off_rounded,
                  size: 40, color: AppColors.textDim),
              const SizedBox(height: 12),
              Text(tr('Keine Treffer'),
                  style: TextStyle(
                      color: AppColors.textDim, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => setState(() {
                  _search = '';
                  _kind = TxKind.all;
                  _sonstigesOnly = false;
                  _searching = false;
                }),
                child: Text(tr('Filter zurücksetzen')),
              ),
            ]),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverList.builder(
            itemCount: rows.length,
            itemBuilder: (_, i) {
              final r = rows[i];
              return r is _DayGroup
                  ? _dayHeader(r)
                  : _dismissible(r as Transaction);
            },
          ),
        ),
    ];
  }

  // search field, quick filters and what the hits add up to (same account list as the rows)
  Widget _searchField(List<Transaction> tx) {
    final hits = _filter(tx);
    final active = _search.trim().isNotEmpty || _kind != TxKind.all;
    Widget chip(String label, TxKind k) => ChoiceChip(
          label: Text(label),
          selected: _kind == k,
          showCheckmark: false,
          side: BorderSide(
              color: _kind == k ? AppColors.primary : AppColors.border),
          selectedColor: AppColors.primary.withValues(alpha: 0.2),
          onSelected: (_) => setState(() => _kind = k),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(
        autofocus: true,
        onChanged: (v) => setState(() => _search = v),
        decoration: InputDecoration(
          hintText: tr('Rewe, 23,75, über 100, Oktober …'),
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => setState(() {
              _searching = false;
              _search = '';
              _kind = TxKind.all;
              _sonstigesOnly = false;
            }),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Row(children: [
        chip(tr('Alle'), TxKind.all),
        const SizedBox(width: 8),
        chip(tr('Ausgaben'), TxKind.expenses),
        const SizedBox(width: 8),
        chip(tr('Einnahmen'), TxKind.income),
      ]),
      if (active) ...[
        const SizedBox(height: 10),
        Text(
          hits.isEmpty
              ? tr('Keine Treffer')
              : '${hits.length} ${hits.length == 1 ? 'Umsatz' : 'Umsätze'} · zusammen ${Money.signed(TxSearch.total(hits))}',
          style: TextStyle(
              color: AppColors.textDim,
              fontWeight: FontWeight.w600,
              fontSize: 13),
        ),
      ],
    ]);
  }

  Widget _emptyState() {
    final bankLinked = Settings.bankState.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(bankLinked ? Icons.sync_rounded : Icons.receipt_long_rounded,
              size: 56, color: AppColors.textDim),
          const SizedBox(height: 16),
          Text(
              bankLinked ? tr('Noch keine Umsätze sichtbar') : tr('Noch keine Umsätze'),
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Pressable(
            builder: (states) => FilledButton.icon(
              statesController: states,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48)),
              onPressed: bankLinked
                  ? () => _syncBank(context)
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ConnectionsScreen())),
              icon: Icon(
                  bankLinked
                      ? Icons.sync_rounded
                      : Icons.account_balance_rounded,
                  size: 18),
              label: Text(bankLinked
                  ? tr('Jetzt synchronisieren')
                  : tr('Bank verbinden')),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => showSmartEntry(context),
            child: Text(bankLinked
                ? tr('Ausgabe manuell erfassen')
                : tr('Erste Ausgabe tippen')),
          ),
        ],
      ),
    );
  }

  // filters transactions by the search text and the quick filters
  List<Transaction> _filter(List<Transaction> tx) => TxSearch.filter(
        tx,
        _search,
        kind: _kind,
        category: _sonstigesOnly ? 'Sonstiges' : null, // l10n: data
      );

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
    if (diff == 0) return tr('Heute');
    if (diff == 1) return tr('Gestern');
    final label = '${Dates.weekdays[d.weekday - 1]}, ${Dates.dayMonth(d)}';
    return d.year == now.year ? label : '$label ${d.year}';
  }

  Widget _dayHeader(_DayGroup g) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 4),
      child: Row(
        children: [
          Text(_dayLabel(g.day),
              style: TextStyle(
                  color: AppColors.textDim,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
          const Spacer(),
          // with one booking the sum would only repeat its amount
          if (g.count > 1)
            ValueListenableBuilder<bool>(
              valueListenable: Settings.hideAmounts,
              builder: (_, hidden, __) => Text(Money.signed(g.net),
                  style: TextStyle(
                      color: hidden
                          ? AppColors.textDim
                          : (g.net > 0
                              ? AppColors.positiveText
                              : AppColors.textDim),
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }

  Widget _dismissible(Transaction t) {
    return Dismissible(
      key: Key(t.id),
      // only allow swipe from right to left; bank bookings would come back with the next sync
      direction: t.id.startsWith(BankSync.prefix)
          ? DismissDirection.none
          : DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
            color: AppColors.error, borderRadius: BorderRadius.circular(14)),
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
    messenger.showSnackBar(SnackBar(
      persist: false,
      duration: const Duration(seconds: 5),
      content: Text(
          tr('{x} gelöscht', {'x': t.note?.trim().isNotEmpty == true ? t.note!.trim() : t.category})),
      action: SnackBarAction(
        label: tr('Rückgängig'),
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
  BankSync.holdSmile(true);
  try {
    final claimed = BankSync.claimSmile(await BankSync.run());
    final text =
        BankSync.syncedLine(added: claimed.added, smarter: claimed.smarter);
    if (claimed.smarter > 0) HapticFeedback.lightImpact();
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      duration: Duration(milliseconds: claimed.smarter > 0 ? 3200 : 2800),
      content: Text(text),
    ));
  } catch (_) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
        duration: Duration(milliseconds: 2800),
        content: Text(tr('Bank gerade nicht erreichbar'))));
    rethrow; // SyncPill must show failure, not a fresh sync
  } finally {
    BankSync.holdSmile(false);
  }
}
