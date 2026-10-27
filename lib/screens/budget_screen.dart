import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/budget.dart';
import '../services/contracts.dart';
import '../services/db.dart';
import '../utils/theme.dart';
import '../widgets/big_number.dart';
import '../utils/money.dart';
import '../widgets/tx_row.dart';

// Budgets as a section of the account screen (not scrollable on its own).
class BudgetView extends StatelessWidget {
  const BudgetView({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box>(
      valueListenable: Hive.box('budgets').listenable(),
      builder: (_, __, ___) => ValueListenableBuilder<Box>(
        valueListenable: Hive.box('transactions').listenable(),
        builder: (context, __, ___) {
          // the running ones: every month adds a new record, past months are history
          final today = DateTime.now();
          final start = DateTime(today.year, today.month, today.day);
          final budgets = DB.getBudgets().where((b) => !b.endDate.isBefore(start)).toList()
            ..sort((a, b) => b.progress.compareTo(a.progress));
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (budgets.isEmpty) _emptyState() else ...budgets.map((b) => _BudgetCard(b)),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: () => showAddBudgetDialog(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Budget hinzufügen'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // shown when no budgets exist yet
  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(Icons.savings_outlined, size: 56, color: AppColors.textDim),
          const SizedBox(height: 16),
          const Text('Noch keine Budgets', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Lege ein Limit pro Kategorie fest und behalte es im Blick.',
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim)),
        ],
      ),
    );
  }
}

// color of a budget: green, yellow from 80 %, red when over the limit
Color budgetColor(Budget b, {DateTime? now}) {
  if (b.isOver) return AppColors.error;
  final pace = budgetPace(b, now: now);
  // spending ahead of the calendar is the early warning
  if (b.progress >= 0.9 || (pace != null && b.progress > pace + 0.1)) return AppColors.warning;
  return AppColors.positive;
}

// share of the budget period that has passed (0..1), null outside the period
double? budgetPace(Budget b, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final start = DateTime(b.startDate.year, b.startDate.month, b.startDate.day);
  final end = DateTime(b.endDate.year, b.endDate.month, b.endDate.day + 1);
  if (today.isBefore(start) || !today.isBefore(end)) return null;
  return today.difference(start).inMinutes / end.difference(start).inMinutes;
}

// single budget card with an animated progress bar; tap shows its spending
class _BudgetCard extends StatefulWidget {
  final Budget budget;
  const _BudgetCard(this.budget);

  @override
  State<_BudgetCard> createState() => _BudgetCardState();
}

class _BudgetCardState extends State<_BudgetCard> {
  // swiped away: leave the tree at once instead of waiting for Hive
  bool _gone = false;

  Budget get budget => widget.budget;

  @override
  Widget build(BuildContext context) {
    if (_gone) return const SizedBox.shrink();
    final color = budgetColor(budget);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Dismissible(
        key: Key('${budget.category}_${budget.startDate.millisecondsSinceEpoch}'),
        // only allow swipe from right to left
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(18)),
          child: const Icon(Icons.delete_rounded, color: Colors.white),
        ),
        onDismissed: (_) => _delete(context),
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => _showSpending(context),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CategoryAvatar(budget.category, isIncome: false, size: 38),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(budget.category, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                          Text(_period(), style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
                        ]),
                      ),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(
                          budget.isOver
                              ? '${Money.format(budget.spentCents - budget.limitCents)} drüber'
                              : '${Money.format(budget.remainingCents)} übrig',
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: budget.isOver ? AppColors.errorText : AppColors.text),
                        ),
                        // the limit itself is where it changes
                        Semantics(
                          button: true,
                          label: 'Limit ändern',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => showAddBudgetDialog(context, editing: budget),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Text('von ${Money.format(budget.limitCents)}',
                                    style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
                                const SizedBox(width: 4),
                                Icon(Icons.edit_rounded, size: 13, color: AppColors.textDim),
                              ]),
                            ),
                          ),
                        ),
                      ]),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // progress bar fills up when shown; the tick marks where
                  // spending would be at an even pace today
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: budget.progress),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, __) => LayoutBuilder(
                      builder: (context, box) {
                        final pace = budgetPace(budget);
                        return Stack(clipBehavior: Clip.none, children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: v,
                              backgroundColor: AppColors.surfaceAlt,
                              valueColor: AlwaysStoppedAnimation(color),
                              minHeight: 8,
                            ),
                          ),
                          if (pace != null)
                            Positioned(
                              left: (box.maxWidth * pace - 1).clamp(0, box.maxWidth - 2),
                              top: -3,
                              child: Container(
                                width: 2,
                                height: 14,
                                decoration: BoxDecoration(
                                    color: AppColors.text.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(1)),
                              ),
                            ),
                        ]);
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(_footer(), style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _period() {
    if (!DB.isMonthly(budget)) return budget.dateRange;
    final now = DateTime.now();
    final end = DateTime(budget.endDate.year, budget.endDate.month, budget.endDate.day);
    final left = end.difference(DateTime(now.year, now.month, now.day)).inDays + 1;
    if (left < 1 || left > 31) return 'Monatlich · ${budget.dateRange}';
    return 'Monatlich · noch $left ${left == 1 ? 'Tag' : 'Tage'}';
  }

  // spent so far and what that leaves per day
  String _footer() {
    final spent = '${Money.format(budget.spentCents)} ausgegeben';
    final pace = budgetPace(budget);
    if (pace == null || budget.isOver) return spent;
    final now = DateTime.now();
    final end = DateTime(budget.endDate.year, budget.endDate.month, budget.endDate.day);
    final days = end.difference(DateTime(now.year, now.month, now.day)).inDays + 1;
    final ahead = budget.progress > pace + 0.1;
    return '$spent · ≈ ${Money.format(budget.remainingCents ~/ days)} pro Tag'
        '${ahead ? ' · schneller als geplant' : ''}';
  }

  // transactions that count towards this budget
  void _showSpending(BuildContext context) {
    final start = DateTime(budget.startDate.year, budget.startDate.month, budget.startDate.day);
    final end = DateTime(budget.endDate.year, budget.endDate.month, budget.endDate.day + 1);
    final tx = DB.getTx()
        .where((t) =>
            !t.isIncome && t.category == budget.category && !t.date.isBefore(start) && t.date.isBefore(end))
        .toList();
    showTransactionsSheet(context, title: budget.category, subtitle: budget.dateRange, tx: tx);
  }

  // deletes right away and offers an undo
  void _delete(BuildContext context) {
    HapticFeedback.mediumImpact();
    setState(() => _gone = true);
    DB.deleteBudget(budget);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(persist: false, duration: const Duration(seconds: 5), 
      content: Text('Budget ${budget.category} gelöscht'),
      action: SnackBarAction(
        label: 'Rückgängig',
        textColor: AppColors.primary,
        onPressed: () => DB.addBudget(budget),
      ),
    ));
  }
}

// shows dialog to create a new budget (default: the current month)
// New monthly budget as a sheet. Buddy preselects the category with the
// highest spending that has no budget yet and suggests its usual amount.
void showAddBudgetDialog(BuildContext context, {String? category, Budget? editing}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    builder: (_) => _BudgetSheet(category: category, editing: editing),
  );
}

class _BudgetSheet extends StatefulWidget {
  final String? category; // preselected, e.g. from a Buddy answer
  final Budget? editing; // a running budget whose limit changes
  const _BudgetSheet({this.category, this.editing});

  @override
  State<_BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends State<_BudgetSheet> {
  final _limit = TextEditingController();
  late final Map<String, int> _usual = _usualSpending();
  late final Set<String> _taken = {
    for (final b in DB.getBudgets())
      if (!DateTime.now().isBefore(b.startDate) && !DateTime.now().isAfter(b.endDate.add(const Duration(days: 1))))
        b.category
  };
  String? _category;

  bool get _editing => widget.editing != null;

  // the button only works with a limit, instead of a message hidden under the sheet
  bool get _valid => _category != null && (Money.parseToCents(_limit.text) ?? 0) > 0;

  @override
  void initState() {
    super.initState();
    final b = widget.editing;
    if (b != null) {
      _category = b.category;
      _limit.text = (b.limitCents / 100).toStringAsFixed(2).replaceAll('.', ',').replaceAll(RegExp(r',00$'), '');
      return;
    }
    // the asked-for category, else the biggest one without a budget yet
    final open = _usual.entries.where((e) => !_taken.contains(e.key)).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final wanted = widget.category;
    if (wanted != null && !_taken.contains(wanted)) {
      _pick(wanted);
    } else if (open.isNotEmpty) {
      _pick(open.first.key);
    }
  }

  @override
  void dispose() {
    _limit.dispose();
    super.dispose();
  }

  // average monthly spending per category over the last three full months
  static Map<String, int> _usualSpending() {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month - 3);
    final to = DateTime(now.year, now.month);
    final sums = <String, int>{};
    final tx = DB.getTx();
    // rent and subscriptions are fixed, a budget would not change them
    final fixed = {for (final c in Contracts.detect(tx)) for (final p in c.payments) p.id};
    for (final t in tx) {
      if (t.isIncome || fixed.contains(t.id) || t.date.isBefore(from) || !t.date.isBefore(to)) continue;
      sums[t.category] = (sums[t.category] ?? 0) + t.amountCents;
    }
    return {for (final e in sums.entries) e.key: e.value ~/ 3};
  }

  void _pick(String category) {
    setState(() => _category = category);
    final usual = _usual[category];
    // a round suggestion a little under the usual, so the budget nudges
    _limit.text = usual == null || usual < 1000 ? '' : '${(usual * 0.9 / 1000).round() * 10}';
  }

  Future<void> _save() async {
    if (!_valid) return;
    final b = widget.editing;
    // a new limit applies to the running month and is carried into the next ones
    final saving = b != null
        ? _saveBudget(context, b.category, _limit.text, b.startDate, b.endDate)
        : _saveBudget(context, _category, _limit.text, DateTime.now(), DateTime.now(), monthly: true);
    final saved = await saving;
    if (saved && mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(milliseconds: 2800),
          content: Text(_editing
              ? 'Neues Limit für $_category: ${Money.raw(Money.parseToCents(_limit.text)!)} im Monat'
              : 'Budget für $_category steht. Es gilt jeden Monat, bis du es löschst.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final usual = _category == null ? null : _usual[_category];
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(_editing ? 'Limit für $_category' : 'Monatsbudget',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
            _editing
                ? 'Gilt ab sofort und in den nächsten Monaten.'
                : 'Ein Limit pro Monat für eine Kategorie. Buddy sagt Bescheid, bevor es knapp wird.',
            style: TextStyle(color: AppColors.textDim, height: 1.4)),
        const SizedBox(height: 16),
        if (!_editing)
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in Categories.expense)
            ChoiceChip(
              selected: _category == c['name'],
              showCheckmark: false,
              side: BorderSide(color: AppColors.border),
              selectedColor: Categories.color(c['name']!).withValues(alpha: 0.22),
              avatar: Icon(Categories.icon(c['name']!), size: 18, color: Categories.color(c['name']!)),
              label: Text(c['name']!),
              onSelected: _taken.contains(c['name']) ? null : (_) => _pick(c['name']!),
            ),
        ]),
        const SizedBox(height: 16),
        TextField(
          controller: _limit,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          autofocus: _editing,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _save(),
          decoration: InputDecoration(
            hintText: 'z. B. 300',
            suffixText: '€ im Monat',
            suffixStyle: TextStyle(fontSize: 16, color: AppColors.textDim, fontWeight: FontWeight.w600),
          ),
        ),
        if (usual != null && usual > 0) ...[
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.auto_awesome_rounded, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Du gibst dafür im Schnitt ${Money.format(usual)} im Monat aus.',
                  style: TextStyle(color: AppColors.textDim, fontSize: 13)),
            ),
          ]),
        ],
        const SizedBox(height: 18),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: _valid ? _save : null,
          child: Text(_editing ? 'Speichern' : 'Budget anlegen',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

// validates input and saves the budget; returns true on success
Future<bool> _saveBudget(BuildContext context, String? category, String limitText, DateTime startDate,
    DateTime endDate, {bool monthly = false}) async {
  // a monthly budget covers the current calendar month and repeats
  if (monthly) {
    startDate = DateTime(startDate.year, startDate.month, 1);
    endDate = DateTime(startDate.year, startDate.month + 1, 0);
  }
  final messenger = ScaffoldMessenger.of(context);
  if (category == null) {
    messenger.showSnackBar(const SnackBar(duration: Duration(milliseconds: 2800), content: Text('Kategorie wählen')));
    return false;
  }
  // input is whole euros -> convert to cents
  final limitCents = Money.parseToCents(limitText);
  if (limitCents == null || limitCents <= 0) {
    messenger.showSnackBar(const SnackBar(duration: Duration(milliseconds: 2800), content: Text('Limit eingeben')));
    return false;
  }
  // dates normalized to midnight
  await DB.addBudget(Budget(
    category: category,
    limitCents: limitCents,
    startDate: DateTime(startDate.year, startDate.month, startDate.day),
    endDate: DateTime(endDate.year, endDate.month, endDate.day),
  ));
  HapticFeedback.lightImpact();
  return true;
}
