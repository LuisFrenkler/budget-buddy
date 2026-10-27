import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/goal.dart';
import '../services/auto_save.dart';
import '../services/buddy_service.dart';
import '../services/db.dart';
import '../services/goals_service.dart';
import '../services/plus_service.dart';
import '../utils/dates.dart';
import '../utils/money.dart';
import '../utils/theme.dart';
import '../widgets/buddy_orb.dart';
import '../widgets/confetti.dart';
import 'plus_screen.dart';

// usual monthly surplus, the base of every plan
int _surplus() {
  final s = BuddyService.snapshot();
  return s.avgIncome - s.avgExpenses;
}

// Starts a new goal, or opens the Plus page when the free goal is used.
Future<void> addGoal(BuildContext context, {String? name, int? cents}) async {
  if (!PlusService.allowed(PlusFeature.goal, current: GoalsService.all().where((g) => !g.reached).length)) {
    return showPlus(context, reason: 'Mehr Ziele, mehr Träume');
  }
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _NewGoal(name: name, cents: cents),
  );
}

class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box>(
      valueListenable: Hive.box('goals').listenable(),
      builder: (context, _, __) {
        final goals = GoalsService.all();
        final saved = goals.fold<int>(0, (s, g) => s + g.savedCents);
        return Scaffold(
          appBar: AppBar(title: const Text('Sparziele')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => addGoal(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Neues Ziel', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          body: goals.isEmpty
              ? _empty(context)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                  children: [
                    Text('Schon zurückgelegt', style: TextStyle(color: AppColors.textDim, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(Money.format(saved),
                        style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w700, letterSpacing: -1.5)),
                    const SizedBox(height: 20),
                    for (final g in goals) GoalCard(g),
                  ],
                ),
        );
      },
    );
  }

  Widget _empty(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('🎯', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            const Text('Worauf sparst du?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('Urlaub, Notgroschen, neues Handy: Leg ein Ziel an, und Buddy rechnet dir aus, wie du es schaffst.',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim, height: 1.4)),
          ]),
        ),
      );
}

class GoalCard extends StatelessWidget {
  final Goal goal;
  const GoalCard(this.goal, {super.key});

  @override
  Widget build(BuildContext context) {
    final plan = GoalsService.plan(goal, avgSurplusCents: _surplus());
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(22)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          GoalRing(goal, size: 60),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(goal.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('${Money.format(goal.savedCents)} von ${Money.format(goal.targetCents)}',
                  style: TextStyle(color: AppColors.textDim, fontSize: 14)),
              if (goal.deadline != null)
                Text('bis ${Dates.full(goal.deadline!)}', style: TextStyle(color: AppColors.textDim, fontSize: 13)),
            ]),
          ),
          PopupMenuButton<String>(
            tooltip: 'Mehr',
            icon: Icon(Icons.more_horiz_rounded, color: AppColors.textDim),
            color: AppColors.surfaceAlt,
            onSelected: (choice) async {
              switch (choice) {
                case 'edit':
                  await showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: AppColors.surface,
                    showDragHandle: true,
                    builder: (_) => _NewGoal(editing: goal),
                  );
                case 'take':
                  await _deposit(context, goal, take: true);
                case 'delete':
                  await GoalsService.delete(goal.id);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(persist: false, duration: const Duration(seconds: 5),
                      content: Text('${goal.name} gelöscht'),
                      action: SnackBarAction(label: 'Rückgängig', onPressed: () => GoalsService.save(goal)),
                    ));
                  }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Ziel bearbeiten')),
              if (goal.savedCents > 0) const PopupMenuItem(value: 'take', child: Text('Geld entnehmen')),
              const PopupMenuItem(value: 'delete', child: Text('Ziel löschen')),
            ],
          ),
        ]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(14)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(padding: EdgeInsets.only(top: 2), child: BuddyOrb(size: 20)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(plan.text,
                  style: TextStyle(fontSize: 13.5, height: 1.4, color: plan.onTrack ? AppColors.text : AppColors.warningText)),
            ),
          ]),
        ),
        if (!goal.reached) ...[
          const SizedBox(height: 10),
          _autoRow(context),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.16), foregroundColor: AppColors.primary),
              onPressed: () => _deposit(context, goal),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Geld zurücklegen'),
            ),
          ),
        ],
      ]),
    );
  }

  // "Automatisch sparen": what is switched on, tap to change
  Widget _autoRow(BuildContext context) {
    final parts = [
      if (goal.monthlyCents > 0) '${Money.format(goal.monthlyCents)} im Monat',
      if (goal.roundUp) 'Aufrunden',
    ];
    final plus = PlusService.active.value;
    // set up earlier, Plus ended since: shown as paused, nothing is lost
    final paused = goal.automated && !plus;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          if (!plus) {
            await showPlus(context, reason: 'Sparziele, die sich von selbst füllen');
            if (!PlusService.active.value || !context.mounted) return;
          }
          await showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: AppColors.surface,
            showDragHandle: true,
            builder: (_) => _AutoSaveSheet(goal),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Row(children: [
            Icon(goal.automated && !paused ? Icons.bolt_rounded : Icons.bolt_outlined,
                size: 20, color: goal.automated && !paused ? AppColors.positive : AppColors.textDim),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                paused
                    ? 'Autopilot pausiert · mit Plus geht es weiter'
                    : goal.automated
                        ? 'Automatisch: ${parts.join(' · ')}'
                        : 'Automatisch sparen einrichten',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                    color: goal.automated && !paused ? AppColors.text : AppColors.primary),
              ),
            ),
            if (!plus && !paused)
              Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: AppColors.heroBrand), borderRadius: BorderRadius.circular(999)),
                child: const Text('PLUS', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
              ),
            Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textDim),
          ]),
        ),
      ),
    );
  }

  // puts money aside, or with [take] takes some out again (plans change);
  // either way with an undo
  static Future<void> _deposit(BuildContext context, Goal goal, {bool take = false}) async {
    final controller = TextEditingController();
    // one tap for the usual amounts: the plan's monthly rate, round sums, the rest
    final rate = goal.monthlyCents > 0 ? goal.monthlyCents : goal.monthlyNeeded(DateTime.now());
    final quick = take
        ? <(String, int)>[('Alles ${Money.format(goal.savedCents)}', goal.savedCents)]
        : <(String, int)>[
            if (rate != null && rate > 0 && rate < goal.remainingCents) ('Monatsrate ${Money.format(rate)}', rate),
            for (final c in [5000, 10000])
              if (c < goal.remainingCents) (Money.format(c), c),
            ('Rest ${Money.format(goal.remainingCents)}', goal.remainingCents),
          ];
    final cents = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(take ? 'Aus ${goal.name} entnehmen' : 'Für ${goal.name} zurücklegen'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(hintText: 'Betrag', suffixText: '€'),
            onSubmitted: (v) => Navigator.pop(context, Money.parseToCents(v)),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (label, c) in quick)
              ActionChip(
                label: Text(label),
                side: BorderSide(color: AppColors.border),
                onPressed: () => Navigator.pop(context, c),
              ),
          ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
          TextButton(
              onPressed: () => Navigator.pop(context, Money.parseToCents(controller.text)),
              child: Text(take ? 'Entnehmen' : 'Zurücklegen')),
        ],
      ),
    );
    if (cents == null || cents <= 0) return;
    final before = goal.savedCents;
    final wasReached = goal.reached;
    goal.savedCents = take ? (before - cents).clamp(0, before) : before + cents;
    await GoalsService.save(goal);
    HapticFeedback.mediumImpact();
    if (!context.mounted) return;
    final moved = (goal.savedCents - before).abs();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 5),
      content: Text(take ? '${Money.raw(moved)} aus ${goal.name} entnommen' : '${Money.raw(moved)} für ${goal.name} zurückgelegt'),
      action: SnackBarAction(label: 'Rückgängig', onPressed: () {
        goal.savedCents = before;
        GoalsService.save(goal);
      }),
    ));
    if (!take && !wasReached && goal.reached) celebrateGoal(context, goal);
  }

}

// "Ziel erreicht!" with a burst of confetti
void celebrateGoal(BuildContext context, Goal goal) {
    HapticFeedback.heavyImpact();
    showDialog(
      context: context,
      builder: (context) => Stack(children: [
        const Positioned.fill(child: ConfettiBurst()),
        Center(child: Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.4, end: 1),
              duration: const Duration(milliseconds: 700),
              curve: Curves.elasticOut,
              builder: (_, v, child) => Transform.scale(scale: v, child: child),
              child: Text(goal.emoji, style: const TextStyle(fontSize: 72)),
            ),
            const SizedBox(height: 16),
            const Text('Ziel erreicht!', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('${Money.format(goal.targetCents)} für ${goal.name}. Stark, dass du drangeblieben bist.',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim, height: 1.4)),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: () => Navigator.pop(context),
              child: const Text('Feiern 🎉'),
            ),
          ]),
        ),
      )),
      ]),
    );
}

// progress ring with the goal's emoji in the middle
class GoalRing extends StatelessWidget {
  final Goal goal;
  final double size;
  const GoalRing(this.goal, {super.key, this.size = 56});

  @override
  Widget build(BuildContext context) {
    final color = goal.reached ? AppColors.positive : AppColors.primary;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: goal.progress),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (_, p, __) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(p, color, AppColors.surfaceAlt),
          child: Center(child: Text(goal.emoji, style: TextStyle(fontSize: size * 0.4))),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double p;
  final Color color, track;
  _RingPainter(this.p, this.color, this.track);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.09;
    final rect = Offset(stroke / 2, stroke / 2) & Size(size.width - stroke, size.height - stroke);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false, paint..color = track);
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * p, false, paint..color = color);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.p != p || old.color != color;
}

// A new goal, or an existing one to change (name, target, date); what is
// saved already and the autopilot stay as they are.
class _NewGoal extends StatefulWidget {
  final String? name;
  final int? cents;
  final Goal? editing;
  const _NewGoal({this.name, this.cents, this.editing});

  @override
  State<_NewGoal> createState() => _NewGoalState();
}

class _NewGoalState extends State<_NewGoal> {
  late final _name = TextEditingController(text: widget.editing?.name ?? widget.name ?? '');
  late final _amount = TextEditingController(
      text: widget.editing != null
          ? _euros(widget.editing!.targetCents)
          : widget.cents == null
              ? ''
              : '${widget.cents! ~/ 100}');
  late String _emoji = widget.editing?.emoji ?? '🏖️';
  late DateTime? _deadline = widget.editing?.deadline;

  static String _euros(int cents) =>
      (cents / 100).toStringAsFixed(2).replaceAll('.', ',').replaceAll(RegExp(r',00$'), '');

  static const _ideas = [
    ('🏖️', 'Urlaub', '1200'),
    ('🛟', 'Notgroschen', '3000'),
    ('📱', 'Neues Handy', '900'),
    ('🚗', 'Auto', '8000'),
    ('🎓', 'Weiterbildung', '1500'),
    ('🎁', 'Geschenke', '400'),
  ];

  int? get _cents => Money.parseToCents(_amount.text);

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final cents = _cents;
    if (cents == null || cents <= 0 || _name.text.trim().isEmpty) return;
    final old = widget.editing;
    await GoalsService.save(Goal(
      id: old?.id ?? const Uuid().v4(),
      name: _name.text.trim(),
      emoji: _emoji,
      targetCents: cents,
      savedCents: old?.savedCents ?? 0,
      deadline: _deadline,
      createdAt: old?.createdAt ?? DateTime.now(),
      monthlyCents: old?.monthlyCents ?? 0,
      lastMonthly: old?.lastMonthly,
      roundUp: old?.roundUp ?? false,
      roundUpSince: old?.roundUpSince,
      roundedIds: old?.roundedIds,
    ));
    if (old == null) await PlusService.count(PlusFeature.goal);
    HapticFeedback.mediumImpact();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cents = _cents;
    final preview = cents == null || cents <= 0
        ? null
        : GoalsService.plan(
            Goal(id: '', name: '', emoji: _emoji, targetCents: cents, deadline: _deadline, createdAt: DateTime.now()),
            avgSurplusCents: _surplus());
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.editing == null ? 'Neues Sparziel' : 'Ziel bearbeiten',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        if (widget.editing == null)
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final i in _ideas)
            ChoiceChip(
              selected: _name.text == i.$2,
              showCheckmark: false,
              label: Text('${i.$1} ${i.$2}'),
              onSelected: (_) => setState(() {
                _emoji = i.$1;
                _name.text = i.$2;
                _amount.text = i.$3;
              }),
            ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: _name,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Wofür?'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: TextField(
              controller: _amount,
              onChanged: (_) => setState(() {}),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Betrag', suffixText: '€'),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () async {
            final now = DateTime.now();
            final d = await showDatePicker(
              context: context,
              initialDate: _deadline != null && _deadline!.isAfter(now)
                  ? _deadline!
                  : DateTime(now.year, now.month + 6, now.day),
              firstDate: DateTime(now.year, now.month, now.day + 1),
              lastDate: DateTime(now.year + 10),
            );
            if (d != null) setState(() => _deadline = d);
          },
          icon: const Icon(Icons.event_rounded, size: 18),
          label: Text(_deadline == null ? 'Bis wann? (optional)' : 'bis ${Dates.full(_deadline!)}'),
        ),
        if (_deadline != null)
          TextButton(
            onPressed: () => setState(() => _deadline = null),
            child: Text('Ohne Datum', style: TextStyle(color: AppColors.textDim)),
          ),
        if (preview != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(14)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const BuddyOrb(size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(preview.text, style: const TextStyle(fontSize: 13.5, height: 1.4))),
            ]),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            disabledBackgroundColor: AppColors.surfaceAlt,
            disabledForegroundColor: AppColors.textDim,
          ),
          onPressed: (cents ?? 0) > 0 && _name.text.trim().isNotEmpty ? _save : null,
          child: Text(widget.editing == null ? 'Ziel anlegen' : 'Speichern',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

// Sets up saving on autopilot for one goal.
class _AutoSaveSheet extends StatefulWidget {
  final Goal goal;
  const _AutoSaveSheet(this.goal);

  @override
  State<_AutoSaveSheet> createState() => _AutoSaveSheetState();
}

class _AutoSaveSheetState extends State<_AutoSaveSheet> {
  late bool _roundUp = widget.goal.roundUp;
  // the amount the user set, with its cents; empty until they choose one
  late final _monthly = TextEditingController(
      text: widget.goal.monthlyCents > 0 ? _euros(widget.goal.monthlyCents) : '');
  late final int _estimate = AutoSave.roundUpEstimate(DB.getTx(), DateTime.now());
  late final String _suggested = _suggestion();

  static String _euros(int cents) =>
      (cents / 100).toStringAsFixed(2).replaceAll('.', ',').replaceAll(RegExp(r',00$'), '');

  // what the deadline needs, else a tenth of the usual surplus, in full 10 €;
  // only offered, never filled in for the user
  String _suggestion() {
    final need = widget.goal.monthlyNeeded(DateTime.now()) ?? (_surplus() ~/ 10);
    if (need <= 0) return '';
    return '${((need / 1000).ceil() * 10)}';
  }

  // the first of next month, when a new monthly amount starts counting
  static DateTime get _nextMonth {
    final now = DateTime.now();
    return DateTime(now.year, now.month + 1, 1);
  }

  // another goal that already rounds up: one coffee can only be rounded up once
  Goal? get _otherRounding =>
      GoalsService.all().where((g) => g.id != widget.goal.id && g.roundUp).firstOrNull;

  @override
  void dispose() {
    _monthly.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final g = widget.goal;
    final cents = Money.parseToCents(_monthly.text) ?? 0;
    final wasRounding = g.roundUp;
    final before = g.monthlyCents;
    g.monthlyCents = cents < 0 ? 0 : cents;
    // a new or changed amount counts from next month: nothing is added
    // behind the user's back for a month they did not plan it for
    if (g.monthlyCents > 0 && g.monthlyCents != before) g.lastMonthly = AutoSave.monthKey(DateTime.now());
    g.roundUp = _roundUp;
    // rounding starts with today's bookings, not the whole history
    if (_roundUp && !wasRounding) {
      g.roundUpSince = DateTime.now();
      g.roundedIds = [];
      final other = _otherRounding;
      if (other != null) {
        other.roundUp = false;
        await GoalsService.save(other);
      }
    }
    await GoalsService.save(g);
    final added = await AutoSave.run();
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(milliseconds: 2800), 
        content: Text(g.automated
            ? '${g.name} spart jetzt automatisch${added > 0 ? ' · ${Money.format(added)} schon dazu' : ''}'
            : 'Automatisches Sparen aus')));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${widget.goal.emoji} ${widget.goal.name} automatisch füllen',
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        Text('Jeden Monat', style: TextStyle(color: AppColors.textDim, fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 8),
        TextField(
          controller: _monthly,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: _suggested.isEmpty ? '0' : _suggested,
            suffixText: '€ am Monatsanfang',
            suffixStyle: TextStyle(fontSize: 14, color: AppColors.textDim, fontWeight: FontWeight.w600),
          ),
        ),
        if (_suggested.isNotEmpty && _monthly.text.isEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _monthly.text = _suggested),
              icon: const Icon(Icons.auto_awesome_rounded, size: 16),
              label: Text('Buddy schlägt $_suggested € vor'),
            ),
          )
        else if ((Money.parseToCents(_monthly.text) ?? 0) > 0 &&
            Money.parseToCents(_monthly.text) != widget.goal.monthlyCents)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text('Zählt ab dem ${Dates.full(_nextMonth)}.',
                style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
          ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(16)),
          child: SwitchListTile(
            value: _roundUp,
            onChanged: (v) => setState(() => _roundUp = v),
            title: const Text('Ausgaben aufrunden', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
                'Kaffee 3,20 € → 0,80 € fürs Ziel.${_estimate > 0 ? ' Bei dir wären das etwa ${Money.format(_estimate)} im Monat.' : ''}'
                '${!widget.goal.roundUp && _otherRounding != null ? ' Rundet bisher für „${_otherRounding!.name}“, das hört dann auf.' : ''}',
                style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.35)),
          ),
        ),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline_rounded, size: 16, color: AppColors.textDim),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                'BudgetBuddy zählt mit, bewegt aber kein Geld. Richte für den Monatsbetrag am besten einen '
                'Dauerauftrag auf dein Sparkonto ein.',
                style: TextStyle(color: AppColors.textDim, fontSize: 12, height: 1.4)),
          ),
        ]),
        const SizedBox(height: 18),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: _save,
          child: const Text('Speichern', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}
