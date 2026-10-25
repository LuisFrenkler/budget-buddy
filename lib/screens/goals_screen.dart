import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/goal.dart';
import '../services/buddy_service.dart';
import '../services/goals_service.dart';
import '../services/plus_service.dart';
import '../utils/dates.dart';
import '../utils/money.dart';
import '../utils/theme.dart';
import '../widgets/buddy_orb.dart';
import 'plus_screen.dart';

// usual monthly surplus, the base of every plan
int _surplus() {
  final s = BuddyService.snapshot();
  return s.avgIncome - s.avgExpenses;
}

// Starts a new goal, or opens the Plus page when the free goal is used.
Future<void> addGoal(BuildContext context) async {
  if (!PlusService.allowed(PlusFeature.goal, current: GoalsService.all().where((g) => !g.reached).length)) {
    return showPlus(context, reason: 'Mehr Ziele, mehr Träume');
  }
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => const _NewGoal(),
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
            icon: Icon(Icons.more_horiz_rounded, color: AppColors.textDim),
            color: AppColors.surfaceAlt,
            onSelected: (_) async {
              await GoalsService.delete(goal.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('${goal.name} gelöscht'),
                  action: SnackBarAction(label: 'Rückgängig', onPressed: () => GoalsService.save(goal)),
                ));
              }
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Ziel löschen'))],
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
                  style: TextStyle(fontSize: 13.5, height: 1.4, color: plan.onTrack ? AppColors.text : AppColors.warning)),
            ),
          ]),
        ),
        if (!goal.reached) ...[
          const SizedBox(height: 12),
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

  static Future<void> _deposit(BuildContext context, Goal goal) async {
    final controller = TextEditingController();
    final cents = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Für ${goal.name} zurücklegen'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(hintText: 'Betrag', suffixText: '€'),
          onSubmitted: (v) => Navigator.pop(context, Money.parseToCents(v)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
          TextButton(
              onPressed: () => Navigator.pop(context, Money.parseToCents(controller.text)),
              child: const Text('Zurücklegen')),
        ],
      ),
    );
    if (cents == null || cents <= 0) return;
    final wasReached = goal.reached;
    goal.savedCents += cents;
    await GoalsService.save(goal);
    HapticFeedback.mediumImpact();
    if (!wasReached && goal.reached && context.mounted) _celebrate(context, goal);
  }

  static void _celebrate(BuildContext context, Goal goal) {
    HapticFeedback.heavyImpact();
    showDialog(
      context: context,
      builder: (context) => Dialog(
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
      ),
    );
  }
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

class _NewGoal extends StatefulWidget {
  const _NewGoal();

  @override
  State<_NewGoal> createState() => _NewGoalState();
}

class _NewGoalState extends State<_NewGoal> {
  final _name = TextEditingController();
  final _amount = TextEditingController();
  String _emoji = '🏖️';
  DateTime? _deadline;

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
    await GoalsService.save(Goal(
      id: const Uuid().v4(),
      name: _name.text.trim(),
      emoji: _emoji,
      targetCents: cents,
      deadline: _deadline,
      createdAt: DateTime.now(),
    ));
    await PlusService.count(PlusFeature.goal);
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
        const Text('Neues Sparziel', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
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
              initialDate: _deadline ?? DateTime(now.year, now.month + 6, now.day),
              firstDate: DateTime(now.year, now.month + 1, now.day),
              lastDate: DateTime(now.year + 10),
            );
            if (d != null) setState(() => _deadline = d);
          },
          icon: const Icon(Icons.event_rounded, size: 18),
          label: Text(_deadline == null ? 'Bis wann? (optional)' : 'bis ${Dates.full(_deadline!)}'),
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
          child: const Text('Ziel anlegen', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}
