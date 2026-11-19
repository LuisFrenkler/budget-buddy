// The centre of the app: what Ahead found on its own and asks a yes for,
// what it is waiting on, and what already came back. The chat is the input
// below it, not the start.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/l10n.dart';
import '../screens/contracts_screen.dart';
import '../screens/plus_screen.dart';
import '../screens/refund_check_screen.dart';
import '../screens/tax_screen.dart';
import '../services/ahead_agent.dart';
import '../services/buddy_service.dart';
import '../services/db.dart';
import '../services/goals_service.dart';
import '../services/hints_service.dart';
import '../services/plus_service.dart';
import '../services/product_events.dart';
import '../services/settings_service.dart';
import '../utils/money.dart';
import '../utils/motion.dart';
import '../utils/theme.dart';
import 'pressable.dart';

class AgentFeed extends StatefulWidget {
  final String? name;
  // a find Ahead handles in the conversation: the agent loop asks before acting
  final ValueChanged<String> onAsk;
  const AgentFeed({super.key, this.name, required this.onAsk});

  @override
  State<AgentFeed> createState() => _AgentFeedState();
}

class _AgentFeedState extends State<AgentFeed> {
  List<AgentFind> _finds = const [];
  bool _all = false;
  int _recovered = 0;
  // the find put away with "Später", still on screen while its card leaves
  String? _leaving;

  @override
  void initState() {
    super.initState();
    _load();
    AheadAgent.changed.addListener(_reload);
  }

  @override
  void dispose() {
    AheadAgent.changed.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (mounted) setState(_load);
  }

  void _load() {
    try {
      final tx = DB.getTx();
      List<Hint> hints = const [];
      try {
        hints = HintsService.current(
          tx: tx,
          budgets: DB.getBudgets(),
          goals: GoalsService.all(),
          subscription: PlusService.subscription.value,
          bankValidUntil: Settings.bankValidUntil,
          freeCents: BuddyService.freeCents(),
          balanceCents: BuddyService.cashCents(),
        );
      } catch (_) {}
      _finds = AheadAgent.run(tx: tx, hints: hints);
      _recovered = AheadAgent.recoveredCents(tx: tx);
      // anonymous, once per install: no amount, no kind of contract
      // per kind of find, so the yes rate of each kind can be read later
      for (final f in _finds) {
        if (f.kind == FindKind.tax || f.kind == FindKind.money) {
          ProductEvents.track(ProductEvents.findShown, kind: ProductEvents.kindOf(f.id));
        }
      }
      if (_recovered > 0) ProductEvents.track(ProductEvents.moneyRecovered);
    } catch (_) {
      _finds = const [];
      _recovered = 0;
    }
  }

  Future<void> _open(AgentFind f) async {
    // one haptic per yes: a find for the conversation gets its own from sending
    if (f.kind != FindKind.money || f.contract != null) HapticFeedback.lightImpact();
    if (f.kind == FindKind.tax) ProductEvents.track(ProductEvents.findYesTax, kind: 'tax');
    if (f.kind == FindKind.money) {
      ProductEvents.track(ProductEvents.findYesMoney, kind: ProductEvents.kindOf(f.id));
      // the ready letter where the find is about one contract, else the conversation
      if (f.contract == null || !await showCancellationLetter(context, f.contract!)) widget.onAsk(f.question!);
      if (mounted) setState(_load);
      return;
    }
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => f.year == null ? const RefundCheckScreen() : TaxScreen(year: f.year)));
    if (mounted) setState(_load);
  }

  Future<void> _later(AgentFind f) async {
    // the list closes under the finger: a second tap in that time must not put away this or the next find
    if (_leaving != null) return;
    HapticFeedback.lightImpact();
    ProductEvents.track(ProductEvents.findLater, kind: ProductEvents.kindOf(f.id));
    setState(() => _leaving = f.id);
    try {
      // saved before the exit plays: leaving the screen mid-way loses nothing
      await AheadAgent.snooze(f.id);
      await Future.delayed(Motion.base);
    } finally {
      if (mounted) {
        setState(() {
          _leaving = null;
          _load();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // a find that is leaving no longer counts: the headline answers the tap at once
    final live = _finds.where((f) => f.id != _leaving).toList();
    final open = AheadAgent.openCents(live);
    final yearly = AheadAgent.yearlyCents(live);
    final asks = live.where((f) => f.kind == FindKind.tax || f.kind == FindKind.money).length;
    final String label;
    final String? amount;
    if (_recovered > 0) {
      label = tr('Ahead hat dir zurückgeholt');
      amount = Money.format(_recovered);
    } else if (open > 0) {
      label = tr('Ahead hat für dich gefunden');
      amount = tr('mind. {x}', {'x': Money.format(open)});
    } else if (AheadAgent.upToCents(live) > 0) {
      label = tr('Ahead hat für dich gefunden');
      amount = tr('bis zu {x}', {'x': Money.format(AheadAgent.upToCents(live))});
    } else {
      // a money find without a sure amount (the contracts to go through) is still a find
      label = yearly > 0 || live.any((f) => f.kind == FindKind.money)
          ? tr('Ahead hat für dich gefunden')
          : tr('Ahead hält für dich Ausschau');
      amount = null;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.name != null)
        Text(tr('Hey {name}', {'name': widget.name!}),
            textAlign: TextAlign.center, style: TextStyle(fontSize: 15.5, color: AppColors.textDim)),
      const SizedBox(height: 4),
      // a changed headline fades in and makes room softly; the first paint stays still
      AnimatedSize(
        duration: Motion.base, // never zero here: a size change may not finish inside its own layout
        curve: Motion.out,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: Motion.base,
          reverseDuration: Duration.zero, // the old amount leaves at once: never two numbers on top of each other
          switchInCurve: Motion.out,
          child: Column(
            key: ValueKey('$label|$amount'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(label,
                  key: const Key('agent-label'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: AppFonts.display,
                      fontSize: 20,
                      letterSpacing: -0.5,
                      height: 1.2,
                      color: AppColors.textDim)),
              if (amount != null) ...[
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(amount,
                      key: const Key('agent-amount'),
                      style: TextStyle(
                          fontFamily: AppFonts.display,
                          fontSize: 52,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -2,
                          height: 1.05,
                          color: AppColors.glow)),
                ),
              ],
            ],
          ),
        ),
      ),
      if (_recovered > 0 && open > 0)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(tr('und mindestens {x} liegen noch bereit', {'x': Money.format(open)}),
              textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: AppColors.textDim)),
        ),
      // costs that can stop are saved, not paid back: never in the big number
      if (yearly > 0)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
              amount == null
                  ? tr('{x} im Jahr, die du sparen kannst', {'x': Money.format(yearly)})
                  : tr('dazu {x} im Jahr, die du sparen kannst', {'x': Money.format(yearly)}),
              key: const Key('agent-yearly'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.textDim)),
        ),
      // nothing found: what Ahead is doing, in one short line; with finds the cards speak for themselves
      if (asks == 0) ...[
        const SizedBox(height: 8),
        Text(
          tr('Steuer, Verträge und Fristen prüfe ich von selbst.'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: AppColors.textDim, height: 1.35),
        ),
      ],
      const SizedBox(height: 14),
      // three at a time: the start stays readable, the rest is one tap away
      for (final f in _all ? _finds : _finds.take(3)) _card(f),
      if (!_all && _finds.length > 3)
        Center(
          child: TextButton(
            key: const Key('finds-all'),
            onPressed: () => setState(() => _all = true),
            child: Text(tr('Alle {n} anzeigen', {'n': _finds.length})),
          ),
        ),
      Center(
        child: TextButton(
          key: const Key('guarantee-link'),
          style: TextButton.styleFrom(foregroundColor: AppColors.textDim),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlusScreen())),
          // the size on the text, not on the button: a button text style would drop the app font
          child: const Text('Ahead Plus', style: TextStyle(fontSize: 13)),
        ),
      ),
    ]);
  }

  Widget _card(AgentFind f) {
    final (icon, color) = switch (f.kind) {
      FindKind.tax => (Icons.receipt_long_outlined, AppColors.glow),
      FindKind.money => (Icons.savings_outlined, AppColors.glow),
      FindKind.waiting => (Icons.hourglass_empty_rounded, AppColors.textDim),
      FindKind.done => (Icons.check_circle_outline_rounded, AppColors.positiveText),
    };
    final asks = f.kind == FindKind.tax || f.kind == FindKind.money;
    final leaving = _leaving == f.id;
    // "Später": the card fades and the list closes over it, instead of a cut
    return ClipRect(
      key: Key('find-${f.id}'),
      child: AnimatedAlign(
        alignment: Alignment.topCenter,
        heightFactor: leaving ? 0 : 1,
        duration: Motion.move(context, Motion.base),
        curve: Motion.out,
        child: AnimatedOpacity(
          opacity: leaving ? 0 : 1,
          duration: Motion.press,
          curve: Motion.color,
          child: IgnorePointer(
            ignoring: leaving,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Pressable(
                builder: (states) => Material(
                  color: AppColors.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: AppColors.hairline)),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 20, color: color)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(f.title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, height: 1.25)),
                            if (f.kind == FindKind.money && (f.cents ?? 0) > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  f.yearly
                                      ? tr('{x} im Jahr', {'x': Money.format(f.cents!)})
                                      : tr('{x} zurückholen', {'x': Money.format(f.cents!)}),
                                  key: Key('amount-${f.id}'),
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.glow),
                                ),
                              ),
                            if (f.text.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(f.text, style: TextStyle(fontSize: 13.5, color: AppColors.textDim, height: 1.35)),
                            ],
                          ]),
                        ),
                      ]),
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        if (asks)
                          TextButton(
                              key: Key('later-${f.id}'), onPressed: () => _later(f), child: Text(tr('Später'))),
                        TextButton(
                          key: Key('go-${f.id}'),
                          statesController: states,
                          onPressed: () => _open(f),
                          child: Text(f.action, style: TextStyle(fontWeight: FontWeight.w600, color: asks ? AppColors.glow : null)),
                        ),
                      ]),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
