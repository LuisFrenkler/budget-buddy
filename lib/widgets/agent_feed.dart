// The centre of the app: what Ahead found on its own and asks a yes for,
// what it is waiting on, and what already came back. The chat is the input
// below it, not the start.
import 'package:flutter/material.dart';
import '../l10n/l10n.dart';
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
import '../utils/theme.dart';

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
  int _recovered = 0;

  @override
  void initState() {
    super.initState();
    _load();
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
      if (_finds.any((f) => f.kind == FindKind.tax || f.kind == FindKind.money)) ProductEvents.track(ProductEvents.findShown);
      if (_recovered > 0) ProductEvents.track(ProductEvents.moneyRecovered);
    } catch (_) {
      _finds = const [];
      _recovered = 0;
    }
  }

  Future<void> _open(AgentFind f) async {
    if (f.kind == FindKind.tax) ProductEvents.track(ProductEvents.findYesTax);
    if (f.kind == FindKind.money) {
      ProductEvents.track(ProductEvents.findYesMoney);
      widget.onAsk(f.question!);
      return;
    }
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => f.year == null ? const RefundCheckScreen() : TaxScreen(year: f.year)));
    if (mounted) setState(_load);
  }

  Future<void> _later(AgentFind f) async {
    ProductEvents.track(ProductEvents.findLater);
    await AheadAgent.snooze(f.id);
    if (mounted) setState(_load);
  }

  @override
  Widget build(BuildContext context) {
    final open = AheadAgent.openCents(_finds);
    final asks = _finds.where((f) => f.kind == FindKind.tax || f.kind == FindKind.money).length;
    final String label;
    final String? amount;
    if (_recovered > 0) {
      label = tr('Ahead hat dir zurückgeholt');
      amount = Money.format(_recovered);
    } else if (open > 0) {
      label = tr('Ahead hat für dich gefunden');
      amount = tr('mind. {x}', {'x': Money.format(open)});
    } else {
      label = tr('Ahead hält für dich Ausschau');
      amount = null;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.name != null)
        Text(tr('Hey {name}', {'name': widget.name!}),
            textAlign: TextAlign.center, style: TextStyle(fontSize: 15.5, color: AppColors.textDim)),
      const SizedBox(height: 4),
      Text(label,
          key: const Key('agent-label'),
          textAlign: TextAlign.center,
          style: TextStyle(
              fontFamily: AppFonts.display, fontSize: 20, letterSpacing: -0.5, height: 1.2, color: AppColors.textDim)),
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
      if (_recovered > 0 && open > 0)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(tr('und mindestens {x} liegen noch bereit', {'x': Money.format(open)}),
              textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: AppColors.textDim)),
        ),
      const SizedBox(height: 8),
      Text(
        asks == 0
            ? tr('Ich prüfe Steuer, Verträge und Fristen von selbst und melde mich, sobald ich etwas finde.')
            : asks == 1
                ? tr('Eine Sache wartet auf dein Ja.')
                : tr('{n} Sachen warten auf dein Ja.', {'n': asks}),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 14, color: AppColors.textDim, height: 1.35),
      ),
      const SizedBox(height: 16),
      for (final f in _finds) _card(f),
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
    return Padding(
      key: Key('find-${f.id}'),
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
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
                onPressed: () => _open(f),
                child: Text(f.action, style: TextStyle(fontWeight: FontWeight.w600, color: asks ? AppColors.glow : null)),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
