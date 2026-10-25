import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/budget.dart';
import '../services/db.dart';
import '../utils/theme.dart';
import '../utils/money.dart';

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});
  
  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box>(
      valueListenable: Hive.box('budgets').listenable(),
      builder: (_, __, ___) => ValueListenableBuilder<Box>(
        valueListenable: Hive.box('transactions').listenable(),
        builder: (_, __, ___) {
          // load all budgets from database
          final budgets = DB.getBudgets();
          
          return Scaffold(
            appBar: AppBar(
              title: const Text('Budgets'),
              // add button in app bar
              actions: [
                IconButton(icon: const Icon(Icons.add), onPressed: _showAddDialog),
              ],
            ),
            // show empty state or list of budgets
            body: budgets.isEmpty ? _buildEmptyState() : _buildBudgetList(budgets),
            // floating button to add new budget
            floatingActionButton: FloatingActionButton.extended(
              heroTag: 'fab_budget',
              onPressed: _showAddDialog,
              icon: const Icon(Icons.add),
              label: const Text('Budget'),
            ),
          );
        },
      ),
    );
  }

  // shown when no budgets exist yet
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.account_balance_wallet_outlined, size: 64, color: AppColors.textDim),
          const SizedBox(height: 16),
          const Text('Keine Budgets', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Erstelle ein Budget', style: TextStyle(color: AppColors.textDim)),
        ],
      ),
    );
  }

  // list of all budget cards
  Widget _buildBudgetList(List<Budget> budgets) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: budgets.length,
      itemBuilder: (_, index) => _buildBudgetCard(budgets[index]),
    );
  }

  // single budget card with progress bar
  Widget _buildBudgetCard(Budget budget) {
    // choose color based on how much is spent
    Color progressColor;
    if (budget.isOver) {
      // red if over budget
      progressColor = AppColors.error;
    } else if (budget.progress >= 0.8) {
      // orange/warning if over 80%
      progressColor = AppColors.warning;
    } else {
      // green if under 80%
      progressColor = AppColors.primary;
    }

    return Dismissible(
      // unique key for each budget
      key: Key('${budget.category}_${budget.startDate.millisecondsSinceEpoch}'),
      // only allow swipe from right to left
      direction: DismissDirection.endToStart,
      // red background with delete icon
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      // ask before deleting
      confirmDismiss: (_) => _confirmDelete(budget),
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // top row: category name and spent/limit amounts
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(budget.category, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(
                    '${Money.format(budget.spentCents)} / ${Money.format(budget.limitCents)}',
                    style: TextStyle(fontWeight: FontWeight.bold, color: progressColor),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              
              // date range text
              Text(budget.dateRange, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
              const SizedBox(height: 12),
              
              // progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: budget.progress,
                  backgroundColor: AppColors.surface,
                  valueColor: AlwaysStoppedAnimation(progressColor),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 8),
              
              // bottom row: percentage and remaining/over amount
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // percentage on left
                  Text('${(budget.progress * 100).toStringAsFixed(0)}%', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                  // remaining or over budget text on right
                  Text(
                    budget.isOver
                        ? '${Money.format(budget.spentCents - budget.limitCents)} über'
                        : '${Money.format(budget.remainingCents)} übrig',
                    style: TextStyle(
                      color: budget.isOver ? AppColors.error : AppColors.textDim,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // show confirmation dialog before deleting budget
  Future<bool> _confirmDelete(Budget budget) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Budget löschen?'),
        content: Text(budget.category),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Nein')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Ja', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    
    // delete if user confirmed
    if (confirmed == true) {
      await DB.deleteBudget(budget);
    }
    return confirmed == true;
  }

  // shows dialog to create a new budget
  void _showAddDialog() {
    // variables for the form
    String? selectedCategory;
    final limitController = TextEditingController();
    var startDate = DateTime.now();
    var endDate = DateTime.now().add(const Duration(days: 30));

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog( //dialog state
          backgroundColor: AppColors.surface,
          title: const Text('Neues Budget'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // category dropdown
                const Text('Kategorie', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _buildCategoryDropdown(selectedCategory, (value) {
                  setDialogState(() => selectedCategory = value);
                }),
                const SizedBox(height: 16),

                // limit input field
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

                // date range selection
                const Text('Zeitraum', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    // start date button
                    Expanded(
                      child: _buildDateButton(startDate, (date) {
                        setDialogState(() => startDate = date);
                      }),
                    ),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('bis')),
                    // end date button (cant be before start date)
                    Expanded(
                      child: _buildDateButton(endDate, (date) {
                        setDialogState(() => endDate = date);
                      }, firstDate: startDate),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
            ElevatedButton(
              onPressed: () => _saveBudget(selectedCategory, limitController.text, startDate, endDate),
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }

  // dropdown for selecting expense category
  Widget _buildCategoryDropdown(String? selected, Function(String?) onChanged) {
    // build dropdown items from expense categories
    final items = <DropdownMenuItem<String>>[];
    for (var category in Categories.expense) {
      items.add(
        DropdownMenuItem(
          value: category['name'],
          child: Row(
            children: [
              Text(category['emoji']!),
              const SizedBox(width: 8),
              Text(category['name']!),
            ],
          ),
        ),
      );
    }

    return DropdownButtonFormField<String>(
      initialValue: selected,
      decoration: const InputDecoration(
        hintText: 'Wählen...',
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: items,
      onChanged: onChanged,
    );
  }

  // button that opens date picker
  Widget _buildDateButton(DateTime date, Function(DateTime) onPicked, {DateTime? firstDate}) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: firstDate ?? DateTime(2020),
          lastDate: DateTime(2030),
        );
        if (picked != null) {
          onPicked(picked);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(8)),
        child: Text('${date.day}.${date.month}.${date.year}', textAlign: TextAlign.center),
      ),
    );
  }

  // validates input and saves new budget
  void _saveBudget(String? category, String limitText, DateTime startDate, DateTime endDate) async {
    // check if category is selected
    if (category == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kategorie wählen')),
      );
      return;
    }
    
    // check if limit is valid (input is whole euros -> convert to cents)
    final limitCents = Money.parseToCents(limitText);
    if (limitCents == null || limitCents <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Limit eingeben')),
      );
      return;
    }

    // create and save budget (dates normalized to midnight)
    final newBudget = Budget(
      category: category,
      limitCents: limitCents,
      startDate: DateTime(startDate.year, startDate.month, startDate.day),
      endDate: DateTime(endDate.year, endDate.month, endDate.day),
    );
    await DB.addBudget(newBudget);
    
    // close dialog and refresh
    if (mounted) {
      Navigator.pop(context);
      setState(() {});
    }
  }
}
