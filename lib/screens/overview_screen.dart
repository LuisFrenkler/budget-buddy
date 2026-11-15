import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'account_screen.dart';
import '../models/money_account.dart';
import '../services/money_accounts.dart';
import '../widgets/sync_pill.dart';
import '../models/transaction.dart';
import '../services/account_service.dart';
import '../services/bank_sync.dart';
import '../services/db.dart';
import '../services/ledger_busy.dart';
import '../services/demo_data.dart';
import '../services/history.dart';
import '../services/settings_service.dart';
import '../services/price_service.dart';
import '../utils/dates.dart';
import '../utils/money.dart';
import '../utils/theme.dart';
import '../widgets/brand.dart';
import '../widgets/user_avatar.dart';
import '../widgets/interactive_chart.dart';
import '../widgets/segmented.dart';
import '../widgets/tx_row.dart';
import 'buddy_screen.dart';
import 'budget_screen.dart';
import 'smart_entry_sheet.dart';
import '../services/goals_service.dart';
import 'connections_screen.dart';
import 'contracts_screen.dart';
import 'splits_screen.dart';
import '../widgets/transfer_sheet.dart';
import '../services/split_service.dart';
import '../services/contracts.dart';
import '../widgets/getting_started.dart';
import '../services/onboarding_service.dart';
import '../services/forecast_service.dart';
import '../services/notification_service.dart';
import '../services/auto_save.dart';
import '../services/weekly_report.dart';
import '../services/buddy_tips.dart';
import '../services/buddy_service.dart';
import '../services/buddy_suggestions.dart';
import '../services/category_coach.dart';
import '../services/wealth.dart';
import '../widgets/forecast_card.dart';
import '../widgets/misc_sort_sheet.dart';
import 'weekly_report_screen.dart';
import 'profile_screen.dart';
import 'goals_screen.dart';
import 'wealth_screen.dart';
import '../widgets/weekly_story.dart';
import '../services/plus_service.dart';
import '../l10n/l10n.dart';
import '../services/hints_service.dart';

// The start screen: one calm money story, Buddy tip, Polster, deeper topics
// live under "Für dich" and in Profil.
class OverviewScreen extends StatefulWidget {
  // switch to another tab (1 = Konto, 2 = Depot), optionally to a section
  final void Function(int tab, {int? segment}) onOpen;
  final ScrollController? scroll;

  OverviewScreen({super.key, required this.onOpen, this.scroll});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  // 1T is yesterday and today; cash and depot are both one value per day
  static const _ranges = {'1T': 2, '1W': 7, '1M': 30, '3M': 91, '1J': 365};
  String _range = '1M';
  // the point under the finger while scrubbing; only the chart header listens
  final _scrub = ValueNotifier<ChartPoint?>(null);
  DateTime? _lastSideEffects;

  // depot value per day for the current range (loaded asynchronously)
  List<int>? _depot;
  // eight-day depot series for the honest week-over-week pulse on Start
  List<int>? _depotWeek;
  int get _days => _ranges[_range]!;

  @override
  void initState() {
    super.initState();
    _loadDepot();
    _loadDepotWeek();
    Hive.box('holdings').listenable().addListener(_loadDepot);
    Hive.box('holdings').listenable().addListener(_loadDepotWeek);
    BankSync.smileTick.addListener(_onSmile);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onSmile());
  }

  @override
  void dispose() {
    BankSync.smileTick.removeListener(_onSmile);
    Hive.box('holdings').listenable().removeListener(_loadDepot);
    Hive.box('holdings').listenable().removeListener(_loadDepotWeek);
    super.dispose();
  }

  // a quieter sync (app start, stale refresh) sorted bookings and nobody
  // else is about to say so
  void _onSmile() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _showSmile());
  }

  void _showSmile() {
    if (!mounted || BankSync.smileHeld) return;
    final smile = BankSync.takeSmile();
    if (smile.smarter <= 0) return;
    HapticFeedback.lightImpact();
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      duration: Duration(milliseconds: 3200),
      content:
          Text(BankSync.syncedLine(added: smile.added, smarter: smile.smarter)),
    ));
  }

  Future<void> _loadDepotWeek() async {
    final series = await PriceService.portfolioHistory(days: 8);
    if (mounted) setState(() => _depotWeek = series.isEmpty ? null : series);
  }

  // the oldest of the fetched numbers behind the total: the bank's bookings
  // and the live prices; null when nothing comes from outside
  DateTime? _fetchedAt() {
    final times = [
      if (Settings.bankState.isNotEmpty && Settings.lastSync != null)
        Settings.lastSync!,
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
    // hold until the sentence is built, so the quiet smile is not said twice
    BankSync.holdSmile(true);
    try {
      if (Settings.bankState.isNotEmpty) {
        try {
          final claimed = BankSync.claimSmile(await BankSync.run());
          parts.add(BankSync.syncedLine(
            added: claimed.added,
            smarter: claimed.smarter,
            none: tr('Keine neuen Buchungen'),
          ));
          if (claimed.smarter > 0) HapticFeedback.lightImpact();
        } catch (_) {
          parts.add(tr('Bank gerade nicht erreichbar'));
          trouble = true;
        }
      }
      if (DB.getHoldings().isNotEmpty) {
        try {
          final r = await PriceService.refreshAll();
          if (r.live > 0) parts.add(tr('Kurse aktualisiert'));
        } catch (_) {
          parts.add(tr('Kurse gerade nicht erreichbar'));
          trouble = true;
        }
      }
      await SplitService.refreshAll();
      await _loadDepot();
      if (!mounted) return;
      final leftover = BankSync.takeSmile();
      if (leftover.smarter > 0 &&
          !parts.any((p) => p.contains('eingeordnet'))) {
        parts.insert(
            0,
            BankSync.syncedLine(
                added: leftover.added, smarter: leftover.smarter));
      }
      final now = DateTime.now();
      final time =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      final warm = parts.any((p) => p.contains('eingeordnet'));
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: Duration(milliseconds: warm ? 3200 : 2400),
        content: Text(parts.isEmpty
            ? tr('Alles aktuell · Stand {time}', {'time': time})
            : tr('{x} · Stand {time}', {'x': parts.join(' · '), 'time': time})),
        backgroundColor: trouble ? AppColors.warning : null,
      ));
      // so SyncPill can show failure, not a fake "fresh"
      if (trouble) throw tr('sync incomplete');
    } finally {
      BankSync.holdSmile(false);
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
          LedgerBusy.on,
        ]),
        builder: (context, _) {
          final tx = DB.getTx();
          // the money on every account together (frozen while vault/bank rewrite)
          final cash = LedgerBusy.cashOr(
              DB.balanceOf(tx) + MoneyAccounts.openingTotal);
          final depotNow = DB.portfolioValue();
          final empty = tx.isEmpty && depotNow == 0;
          // throttle side-effects. Hive can fire often during import/sync
          final now = DateTime.now();
          if (_lastSideEffects == null ||
              now.difference(_lastSideEffects!) > Duration(seconds: 2)) {
            _lastSideEffects = now;
            NotificationService.syncSoon();
            AutoSave.runSoon();
          }

          return AmbientGlow(
            align: const Alignment(1.3, -1.2),
            size: 1.3,
            child: SafeArea(
            bottom: false,
            child: RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _refresh,
              child: ListView(
                controller: widget.scroll,
                physics: AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(20, 8, 20, 120),
                children: [
                  _topBar(),
                  SizedBox(height: 24),
                  if (empty) ...[
                    _welcome(),
                    if (!OnboardingService.hidden) ...[
                      SizedBox(height: 20),
                      GettingStartedCard(),
                    ],
                    SizedBox(height: 20),
                    _quickActions(),
                  ] else ...[
                    if (DemoData.active) _demoBanner(),
                    // Buddy first: what to do now, before any chart
                    _buddyBrief(tx, cash),
                    const SizedBox(height: 24),
                    if (!OnboardingService.hidden &&
                        !OnboardingService.complete) ...[
                      GettingStartedCard(),
                      const SizedBox(height: 24),
                    ],
                    // one ask at a time: don't stack GettingStarted + balance prompt
                    if (!OnboardingService.balanceKnown &&
                        (OnboardingService.hidden ||
                            OnboardingService.complete))
                      _balancePrompt(cash)
                    else if (OnboardingService.balanceKnown)
                      ..._netWorth(tx, cash, depotNow),
                    const SizedBox(height: 16),
                    _accountsCard(tx, cash, depotNow),
                    const SizedBox(height: 16),
                    _quickActions(),
                    if (OnboardingService.balanceKnown) ...[
                      ..._forecast(tx, cash),
                      // tip + Polster only once money is trusted
                      ..._bridge(tx, cash, depotNow),
                    ],
                    ..._recent(tx),
                    ..._weeklyStory(tx),
                    ..._forYou(tx),
                  ],
                ],
              ),
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
            Icon(Icons.account_balance_wallet_rounded,
                color: AppColors.primary, size: 30),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Wie viel hast du gerade?'),
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(tr('Einmal eintragen, dann stimmt es.'),
                        style: TextStyle(
                            color: AppColors.textDim,
                            fontSize: 13,
                            height: 1.35)),
                  ]),
            ),
            Icon(Icons.chevron_right_rounded, color: AppColors.primary),
          ]),
        ),
      ),
    );
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
            const Icon(Icons.science_rounded,
                color: AppColors.warning, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(tr('Du siehst Beispieldaten'),
                  style:
                      TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
            ),
            TextButton(onPressed: _removeDemo, child: Text(tr('Entfernen'))),
          ]),
        ),
      );

  Future<void> _removeDemo() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Beispieldaten entfernen?')),
        content: Text(
            tr('Beispiele weg. Deine eigenen Einträge bleiben.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('Abbrechen'))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('Entfernen'))),
        ],
      ),
    );
    if (ok != true) return;
    await DemoData.remove();
    HapticFeedback.mediumImpact();
    if (mounted) setState(() {});
  }

  // daily habit number: what is still free this month (mounted when we know the balance)
  List<Widget> _forecast(List<Transaction> tx, int cash) {
    final forecast = ForecastService.build(tx,
        goals: GoalsService.all(), balanceCents: cash);
    if (forecast == null) {
      if (tx.isEmpty) return const [];
      return [
        const SizedBox(height: 16),
        Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () {
              HapticFeedback.selectionClick();
              showSmartEntry(context);
            },
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(children: [
                Icon(Icons.insights_outlined, color: AppColors.primaryText),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    tr('Für „noch frei“ brauchst du eine Einnahme.'),
                    style: TextStyle(color: AppColors.textDim, height: 1.35, fontSize: 14),
                  ),
                ),
                Icon(Icons.add_rounded, color: AppColors.primaryText),
              ]),
            ),
          ),
        ),
      ];
    }
    return [
      const SizedBox(height: 16),
      ForecastCard(forecast),
    ];
  }

  // Buddy's one line on top of the overview: the number that matters this
  // month and, when something stands out, what to do about it. One tap and
  // the conversation starts right there.
  Widget _buddyBrief(List<Transaction> tx, int cash) {
    MonthForecast? f;
    try {
      f = OnboardingService.balanceKnown
          ? ForecastService.build(tx, goals: GoalsService.all(), balanceCents: cash)
          : null;
    } catch (_) {}
    // the most important hint of the day beats the general tip
    Hint? top;
    try {
      final best = HintsService.top(HintsService.current(
        tx: tx,
        budgets: DB.getBudgets(),
        goals: GoalsService.all(),
        subscription: PlusService.subscription.value,
        bankValidUntil: Settings.bankValidUntil,
        freeCents: f?.freeCents,
        balanceCents: BuddyService.cashCents(),
      ));
      // urgent hints still win; a yearly subscription tip speaks only when nothing heavier is waiting
      if (best != null && best.question != null && (best.weight >= 45 || best.kind == HintKind.subTip)) {
        top = best;
      }
    } catch (_) {}
    final tip = top != null
        ? BuddyTip('${top.title}${RegExp(r'[.!?]$').hasMatch(top.title) ? '' : '.'} ${top.text}', top.question!)
        : BuddyTips.pick(tx: tx, budgets: DB.getBudgets(), balanceCents: cash);
    final hidden = Settings.hideAmounts.value;
    final String headline;
    final String question;
    if (f != null && f.freeCents >= 0) {
      headline = tr('**{x}** sind bis Monatsende noch frei, etwa {y} pro Tag.', {
        'x': hidden ? Money.hidden : Money.format(f.freeCents),
        'y': hidden ? Money.hidden : Money.format(f.perDayCents),
      });
      question = tr('Wie viel ist diesen Monat noch frei?');
    } else if (f != null) {
      headline = tr('Diesen Monat wird es knapp: **{x}** fehlen bis Monatsende.',
          {'x': hidden ? Money.hidden : Money.format(-f.freeCents)});
      question = tr('Wie komme ich diesen Monat noch hin?');
    } else {
      headline = tr('Frag mich, was du dir diesen Monat leisten kannst.');
      question = tr('Kann ich mir 800 € Urlaub leisten?');
    }
    // Buddy speaks from copper light, like on the landing page
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: CopperLight(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () => BuddyScreen.open(context, tip?.question ?? question),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const BrandMark(size: 22, inverse: true),
                  const SizedBox(width: 8),
                  Text(tr('Buddy sagt'),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xCCFFFFFF))),
                ]),
                const SizedBox(height: 10),
                RichMarkdown(headline, glossary: false, fontSize: 18, color: Colors.white),
                if (tip != null) ...[
                  const SizedBox(height: 6),
                  Text(tip.text, style: const TextStyle(color: Color(0xD9FFF7F0), fontSize: 14, height: 1.4)),
                ],
                const SizedBox(height: 14),
                // looks like the chat's input: the way in is to ask
                Container(
                  height: 44,
                  padding: const EdgeInsets.fromLTRB(14, 0, 4, 0),
                  decoration: BoxDecoration(
                    color: const Color(0x29FFFFFF),
                    border: Border.all(color: const Color(0x38FFFFFF)),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: Text(tip?.question ?? question,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Color(0xE6FFFFFF), fontSize: 14)),
                    ),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: const Icon(Icons.arrow_upward_rounded, color: Color(0xFF17120E), size: 19),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  // Buddy tip + wealth/vorsorge bridge under the habit number
  List<Widget> _bridge(List<Transaction> tx, int cash, int depotNow) {
    final emergency = Wealth.emergency(tx);
    final out = <Widget>[const SizedBox(height: 16)];

    // one calm Polster row, not a second mini-dashboard of 3 chips
    out.add(_bridgeChip(
      Icons.savings_outlined,
      tr('Notgroschen'),
      emergency.targetCents <= 0
          ? tr('Polster einrichten')
          : emergency.ready
              ? tr('Polster steht')
              : tr('Noch {x} bis zum Polster', {'x': Money.format(emergency.missingCents)}),
      () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const WealthScreen())),
    ));
    return out;
  }

  Widget _bridgeChip(
      IconData icon, String title, String value, VoidCallback onTap,
      {String? footnote}) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
          child: Row(children: [
            Icon(icon, size: 22, color: AppColors.primaryText),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textDim,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(value,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            height: 1.2)),
                    if (footnote != null) ...[
                      const SizedBox(height: 2),
                      Text(footnote,
                          style: TextStyle(
                              fontSize: 11.5, color: AppColors.textDim)),
                    ],
                  ]),
            ),
            Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
          ]),
        ),
      ),
    );
  }

  // one gradient card + single CTA into the shareable 9:16 story
  List<Widget> _weeklyStory(List<Transaction> tx) {
    final report = WeeklyReportService.build(tx);
    if (report == null) return const [];
    final fresh = !WeeklyReportScreen.seen(report);
    return [
      const SizedBox(height: 28),
      Container(
        padding: const EdgeInsets.all(1.25),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: AppColors.border,
        ),
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20.75),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    if (fresh)
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            color: AppColors.primary, shape: BoxShape.circle),
                      ),
                    Expanded(
                      child: Text(
                        fresh
                            ? tr('Deine Wochen-Story ist da')
                            : tr('Wochen-Story · KW {week}', {'week': report.week}),
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text(report.headline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: AppColors.textDim,
                          fontSize: 14,
                          height: 1.35)),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () async {
                      await presentWeeklyStory(context, report);
                      if (mounted) setState(() {});
                    },
                    icon: const Icon(Icons.auto_stories_rounded, size: 18),
                    label: Text(tr('Ansehen'),
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ]),
          ),
        ),
      ),
    ];
  }

  // only signal tiles, no second dashboard
  List<Widget> _forYou(List<Transaction> tx) {
    final tiles = <Widget>[];

    final misc = CategoryCoach.miscCount();
    if (misc > 0) {
      tiles.add(_forYouTile(
        Icons.category_rounded,
        tr('Buchungen einordnen'),
        tr('{misc} in Sonstiges · Händler antippen', {'misc': misc}),
        () => showMiscSortSheet(context),
      ));
    }

    if (GoalsService.all().where((g) => !g.reached).isEmpty) {
      tiles.add(_forYouTile(
        Icons.flag_rounded,
        tr('Sparziel anlegen'),
        PlusService.active.value
            ? tr('Worauf sparst du?')
            : tr('1 Ziel gratis · Autopilot später mit Plus'),
        () => addGoal(context),
      ));
    }

    final contracts = Contracts.detect(tx);
    final raised = contracts.where((c) => c.priceChange > 0).length;
    if (raised > 0) {
      tiles.add(_forYouTile(
        Icons.receipt_long_rounded,
        tr('Abos teurer geworden'),
        tr('{raised} {x} mit Preisanstieg', {'raised': raised, 'x': raised == 1 ? tr('Vertrag') : tr('Verträge')}),
        () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const ContractsScreen())),
        subtitleColor: AppColors.warningText,
      ));
    }

    if (Hive.isBoxOpen('splits') && SplitService.all().isNotEmpty) {
      final total = SplitService.myTotal();
      if (total != 0) {
        tiles.add(_forYouTile(
          Icons.call_split_rounded,
          tr('Geteilte Ausgaben'),
          total > 0
              ? tr('Du bekommst {x}', {'x': Money.format(total)})
              : tr('Du schuldest {x}', {'x': Money.format(-total)}),
          () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const SplitsScreen())),
          subtitleColor:
              total > 0 ? AppColors.positiveText : AppColors.errorText,
        ));
      }
    }

    final today = DateTime.now();
    final budgets = DB.getBudgets().where((b) => b.covers(today)).toList();
    if (budgets.isEmpty) {
      final suggestions = BudgetSuggest.top();
      if (suggestions.isNotEmpty) {
        tiles.add(_forYouTile(
          Icons.pie_chart_rounded,
          tr('Budgets vorschlagen'),
          tr('Aus deinen Ausgaben · {suggestions} Kategorien', {'suggestions': suggestions.length}),
          () => showBudgetSuggestSheet(context, suggestions),
        ));
      }
    } else {
      final tight = budgets
          .where((b) => b.isOver || b.remainingCents <= b.limitCents * 0.2)
          .length;
      if (tight > 0) {
        tiles.add(_forYouTile(
          Icons.pie_chart_rounded,
          tr('Budgets knapp'),
          tr('{tight} {x} knapp oder drüber', {'tight': tight, 'x': L10n.isDe ? (tight == 1 ? tr('Kategorie') : tr('Kategorien')) : (tight == 1 ? tr('Kategorie') : tr('Kategorien')).toLowerCase()}),
          () => widget.onOpen(1, segment: 1),
          subtitleColor: AppColors.warningText,
        ));
      }
    }

    if (tiles.isEmpty) return const [];
    final shown = tiles.take(3).toList();
    return [
      const SizedBox(height: 28),
      Text(tr('Für dich'),
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < shown.length; i++) ...[
              if (i > 0) Divider(height: 1, color: AppColors.border),
              shown[i],
            ],
          ],
        ),
      ),
    ];
  }

  Widget _forYouTile(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap, {
    bool badge = false,
    Color? subtitleColor,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Icon(icon, size: 22, color: AppColors.primaryText),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 15)),
              const SizedBox(height: 2),
              Text(subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      color: subtitleColor ?? AppColors.textDim,
                      height: 1.3)),
            ]),
          ),
          if (badge) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: AppColors.primary, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
        ]),
      ),
    );
  }

  // wordmark on the left, profile avatar on the right
  Widget _topBar() {
    final name = AccountService.current.value?.name;
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
            tooltip: hidden ? tr('Beträge zeigen') : tr('Beträge verbergen'),
            onPressed: () {
              HapticFeedback.selectionClick();
              Settings.setHideAmounts(!hidden);
            },
            icon: Icon(
                hidden
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                color: AppColors.textDim),
          ),
        ),
        const SizedBox(width: 4),
        Semantics(
          button: true,
          label: tr('Profil'),
          excludeSemantics: true,
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ProfileScreen())),
              child: UserAvatar(
                  name: name, size: 40, fontSize: 16, brandGradient: false),
            ),
          ),
        ),
      ],
    );
  }

  // one-tap actions under the hero (Revolut / Cash App style)
  Widget _quickActions() {
    Widget chip(IconData icon, String label, VoidCallback onTap,
        {Color? color}) {
      final c = color ?? AppColors.primary;
      return Expanded(
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: c.withValues(alpha: 0.14), shape: BoxShape.circle),
                  child: Icon(icon, color: c, size: 20),
                ),
                const SizedBox(height: 8),
                Text(label,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ),
      );
    }

    final bankLinked = Settings.bankState.isNotEmpty;
    return Row(children: [
      chip(Icons.chat_bubble_outline_rounded, tr('Buddy'), () => BuddyScreen.open(context),
          color: AppColors.primary),
      const SizedBox(width: 10),
      chip(Icons.edit_note_rounded, tr('Erfassen'), () => showSmartEntry(context),
          color: AppColors.primary),
      const SizedBox(width: 10),
      chip(
          Icons.group_rounded,
          tr('Geteilt'),
          () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const SplitsScreen())),
          color: AppColors.primary),
      if (!bankLinked && !MoneyAccounts.several) ...[
        const SizedBox(width: 10),
        chip(
            Icons.account_balance_rounded,
            tr('Bank'),
            () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ConnectionsScreen())),
            color: AppColors.primary),
      ] else ...[
        const SizedBox(width: 10),
        chip(Icons.swap_horiz_rounded, tr('Transfer'),
            () => showTransferSheet(context),
            color: AppColors.primary),
      ],
    ]);
  }

  // net worth headline, chart and range buttons
  List<Widget> _netWorth(List<Transaction> tx, int cash, int depotNow) {
    final now = DateTime.now();
    final debts = Wealth.debtTotal();
    final net = Wealth.netWorthCents(cashCents: cash, depotCents: depotNow);
    final cashPts = History.dailyBalance(tx,
        from: DateTime(now.year, now.month, now.day - (_days - 1)),
        opening: MoneyAccounts.openingTotal);
    final depot = _depot;
    final points = [
      for (int i = 0; i < cashPts.length; i++)
        ChartPoint(
          cashPts[i].date,
          // date-aligned depot history when loaded, today's value until then
          cashPts[i].cents +
              (depot != null && depot.length == cashPts.length
                  ? depot[i]
                  : depotNow) -
              debts,
        ),
    ];
    return [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: ChartHeader(
            label: debts > 0 ? tr('Nettovermögen') : tr('Gesamtvermögen'),
            cents: net,
            startCents: points.isEmpty ? net : points.first.cents,
            period: RangeSelector.periods[_range]!,
            scrubbing: _scrub,
            startDate: points.isEmpty ? null : points.first.date,
          ),
        ),
        SyncPill(last: _fetchedAt(), onSync: _refresh),
      ]),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: GestureDetector(
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const WealthScreen())),
          child: Text(
              debts > 0
                  ? tr('Konto + Depot − {x} Schulden', {'x': Money.format(debts)})
                  : tr('Konto + Depot'),
              style: TextStyle(
                  color: AppColors.textDim,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600)),
        ),
      ),
      if (Wealth.moment(tx: tx, now: now) ??
              Wealth.weekOverWeekPulse(
                tx,
                cashCents: cash,
                depotCents: depotNow,
                depotThenCents: _depotWeek != null && _depotWeek!.length >= 2
                    ? _depotWeek!.first
                    : null,
                opening: MoneyAccounts.openingTotal,
                now: now,
              )
          case final pulse?)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            Icon(Icons.trending_up_rounded,
                size: 16, color: AppColors.positiveText),
            const SizedBox(width: 6),
            Expanded(
              child: Text(pulse,
                  style: TextStyle(
                      color: AppColors.positiveText,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      const SizedBox(height: 16),
      InteractiveChart(points: points, onScrub: (p) => _scrub.value = p),
      const SizedBox(height: 12),
      RangeSelector(
        labels: [for (final r in _ranges.keys) tr(r)],
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
    final monthNet =
        DB.sumOf(month, isIncome: true) - DB.sumOf(month, isIncome: false);
    final invested = DB.portfolioInvested();
    final gain = depotNow - invested;
    final known = OnboardingService.balanceKnown;
    final hasHoldings = DB.getHoldings().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
      ),
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
                color:
                    a.kind == 'spar' ? AppColors.positive : AppColors.primary,
                title: a.name,
                value: Money.format(MoneyAccounts.balanceOf(a, tx)),
                change: () {
                  final net =
                      DB.balanceOf(MoneyAccounts.bookingsOf(a.id, month));
                  return net == 0
                      ? MoneyAccount.kinds[a.kind]!
                      : tr('{x} im {y}', {'x': Money.signed(net), 'y': Dates.month(DateTime.now())});
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
              title: Settings.bankName.isNotEmpty ? Settings.bankName : tr('Konto'),
              // without the real balance the sum of bookings means nothing
              value: known ? Money.format(cash) : tr('Eintragen'),
              change: known
                  ? tr('{x} im {y}', {'x': Money.signed(monthNet), 'y': Dates.month(DateTime.now())})
                  : tr('Kontostand fehlt noch'),
              up: !known || monthNet == 0 ? null : monthNet > 0,
              onTap: () => widget.onOpen(1, segment: 0),
            ),
            Divider(height: 1, indent: 72, color: AppColors.border),
          ],
          _accountRow(
            icon: Icons.trending_up_rounded,
            color: AppColors.primary,
            title: tr('Depot'),
            value: Money.format(depotNow),
            change: !hasHoldings
                ? tr('Noch keine Positionen')
                : invested == 0
                    ? tr('Ohne Kaufpreis')
                    : tr('{x} gesamt', {'x': Money.percent(gain / invested * 100, digits: 2)}),
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
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
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
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis),
                    ),
                    Text(value,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 2),
                  Text(change,
                      style: TextStyle(fontSize: 13, color: changeColor),
                      overflow: TextOverflow.ellipsis),
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

  List<Widget> _recent(List<Transaction> tx) {
    if (tx.isEmpty) return const [];
    return [
      const SizedBox(height: 28),
      SectionTitle(tr('Letzte Umsätze'),
          action: tr('Alle'), onAction: () => widget.onOpen(1, segment: 0)),
      for (final t in tx.take(4)) TxRow(t),
    ];
  }

  // empty Start: one primary job, get real money in
  Widget _welcome() {
    final name = AccountService.current.value?.firstName;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(name == null || name.isEmpty ? tr('Dein Überblick') : tr('Hallo {name}', {'name': name}),
          style: const TextStyle(fontFamily: AppFonts.display, 
              fontSize: 28, fontWeight: FontWeight.w600, letterSpacing: -0.6)),
      const SizedBox(height: 8),
      Text(
        tr('Bank oder erste Ausgabe.'),
        style: TextStyle(color: AppColors.textDim, height: 1.45, fontSize: 15),
      ),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.65)),
        ),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.account_balance_rounded,
                  color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Bank verbinden'),
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16)),
                    Text(tr('Login nur bei deiner Bank'),
                        style: TextStyle(
                            color: AppColors.textDim,
                            fontSize: 12.5,
                            height: 1.35)),
                  ]),
            ),
          ]),
          const SizedBox(height: 14),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () {
              HapticFeedback.selectionClick();
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ConnectionsScreen()));
            },
            child: Text(tr('Jetzt verbinden'),
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () {
              HapticFeedback.selectionClick();
              showSmartEntry(context);
            },
            child: Text(tr('Oder manuell erfassen')),
          ),
          TextButton(
            onPressed: () async {
              HapticFeedback.selectionClick();
              await DemoData.load();
              if (mounted) setState(() {});
            },
            child: Text(tr('Beispieldaten ansehen'),
                style: TextStyle(color: AppColors.textDim)),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      BuddyCard(chips: BuddySuggestions.pick(BuddyService.snapshot())),
    ]);
  }
}
