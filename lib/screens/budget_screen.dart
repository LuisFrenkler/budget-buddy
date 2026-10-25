import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/budget.dart';
import '../services/db.dart';
import '../utils/theme.dart';
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
          // load all budgets from database
          final budgets = DB.getBudgets();
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
Color budgetColor(Budget b) {
  if (b.isOver) return AppColors.error;
  if (b.progress >= 0.8) return AppColors.warning;
  return AppColors.positive;
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
                      Icon(Categories.icon(budget.category), size: 20, color: AppColors.textDim),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(budget.category,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                      ),
                      Text(Money.format(budget.spentCents),
                          style: TextStyle(fontWeight: FontWeight.w700, color: color)),
                      Text(' / ${Money.format(budget.limitCents)}',
                          style: TextStyle(color: AppColors.textDim)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // progress bar fills up when shown
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: budget.progress),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, __) => ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: v,
                        backgroundColor: AppColors.surfaceAlt,
                        valueColor: AlwaysStoppedAnimation(color),
                        minHeight: 8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(budget.dateRange, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                      const Spacer(),
                      Text(
                        budget.isOver
                            ? '${Money.format(budget.spentCents - budget.limitCents)} drüber'
                            : '${Money.format(budget.remainingCents)} übrig',
                        style: TextStyle(
                          color: budget.isOver ? AppColors.error : AppColors.textDim,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
    messenger.showSnackBar(SnackBar(
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
void showAddBudgetDialog(BuildContext context) {
  // variables for the form
  String? selectedCategory;
  final limitController = TextEditingController();
  final now = DateTime.now();
  var startDate = DateTime(now.year, now.month, 1);
  var endDate = DateTime(now.year, now.month + 1, 0);

  showDialog(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Neues Budget'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Kategorie', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              // category chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in Categories.expense)
                    ChoiceChip(
                      label: Text(c['name']!),
                      selected: selectedCategory == c['name'],
                      onSelected: (_) => setDialogState(() => selectedCategory = c['name']),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Limit (€)', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: limitController,
                keyboardType: TextInputType.number,
                // only allow digits
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  hintText: 'z.B. 200',
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Zeitraum', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _dateButton(dialogContext, startDate, (d) => setDialogState(() => startDate = d)),
                  ),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('bis')),
                  // end date cant be before start date
                  Expanded(
                    child: _dateButton(dialogContext, endDate, (d) => setDialogState(() => endDate = d),
                        firstDate: startDate),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () async {
              if (await _saveBudget(dialogContext, selectedCategory, limitController.text, startDate, endDate) &&
                  dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    ),
  );
}

// button that opens date picker
Widget _dateButton(BuildContext context, DateTime date, ValueChanged<DateTime> onPicked, {DateTime? firstDate}) {
  return InkWell(
    onTap: () async {
      final picked = await showDatePicker(
        context: context,
        initialDate: date,
        firstDate: firstDate ?? DateTime(2020),
        lastDate: DateTime(2035),
      );
      if (picked != null) onPicked(picked);
    },
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(8)),
      child: Text('${date.day}.${date.month}.${date.year}', textAlign: TextAlign.center),
    ),
  );
}

// validates input and saves the budget; returns true on success
Future<bool> _saveBudget(
    BuildContext context, String? category, String limitText, DateTime startDate, DateTime endDate) async {
  final messenger = ScaffoldMessenger.of(context);
  if (category == null) {
    messenger.showSnackBar(const SnackBar(content: Text('Kategorie wählen')));
    return false;
  }
  // input is whole euros -> convert to cents
  final limitCents = Money.parseToCents(limitText);
  if (limitCents == null || limitCents <= 0) {
    messenger.showSnackBar(const SnackBar(content: Text('Limit eingeben')));
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
