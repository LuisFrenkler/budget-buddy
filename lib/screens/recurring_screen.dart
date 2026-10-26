import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/recurring.dart';
import '../services/db.dart';
import '../services/recurring_service.dart';
import '../utils/dates.dart';
import '../utils/theme.dart';
import '../utils/money.dart';
import '../widgets/big_number.dart';

// Standing orders: what comes in and goes out regularly, normalized to a month.
class RecurringScreen extends StatefulWidget {
  const RecurringScreen({super.key});

  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen> {
  // how often an interval happens per month on average
  static const _perMonth = {'täglich': 30.44, 'wöchentlich': 4.35, 'monatlich': 1.0, 'jährlich': 1 / 12};

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box>(
      valueListenable: Hive.box('recurring').listenable(),
      builder: (_, __, ___) {
        // soonest first
        final rules = DB.getRules()
          ..sort((a, b) => RecurringService.nextDate(a).compareTo(RecurringService.nextDate(b)));
        final income = rules.where((r) => r.isIncome).toList();
        final expenses = rules.where((r) => !r.isIncome).toList();

        return Scaffold(
          appBar: AppBar(title: const Text('Wiederkehrend')),
          body: rules.isEmpty
              ? _emptyState()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  children: [
                    _summary(income, expenses),
                    if (income.isNotEmpty) ...[_label('Einnahmen'), _group(income)],
                    if (expenses.isNotEmpty) ...[_label('Ausgaben'), _group(expenses)],
                    const SizedBox(height: 16),
                    Text('Wische nach links zum Löschen. Bereits gebuchte Umsätze bleiben erhalten.',
                        textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                  ],
                ),
        );
      },
    );
  }

  // monthly amount of all active rules, in cents
  int _monthly(List<RecurringRule> rules) {
    double sum = 0;
    for (final r in rules) {
      if (r.active) sum += r.amountCents * (_perMonth[r.interval] ?? 1);
    }
    return sum.round();
  }

  Widget _summary(List<RecurringRule> income, List<RecurringRule> expenses) {
    final fixed = _monthly(expenses);
    final fixedIncome = _monthly(income);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: BigNumber(
        label: 'Fixkosten pro Monat',
        cents: fixed,
        below: Text(
          fixedIncome > 0
              ? 'Feste Einnahmen ${Money.format(fixedIncome)} · frei verfügbar ${Money.format(fixedIncome - fixed)}'
              : 'Noch keine festen Einnahmen',
          style: TextStyle(color: AppColors.textDim, fontSize: 14),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 8, left: 4),
        child: Text(text, style: TextStyle(color: AppColors.textDim, fontSize: 13, fontWeight: FontWeight.bold)),
      );

  Widget _group(List<RecurringRule> rules) {
    return Container(
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < rules.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 70, color: AppColors.border),
            _ruleRow(rules[i]),
          ],
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.repeat_rounded, size: 56, color: AppColors.textDim),
            const SizedBox(height: 16),
            const Text('Keine Daueraufträge', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Wähle beim Erfassen eines Umsatzes eine Wiederholung, z. B. „monatlich“.',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim)),
          ],
        ),
      ),
    );
  }

  Widget _ruleRow(RecurringRule r) {
    final note = r.note?.trim() ?? '';
    final title = note.isNotEmpty ? note : r.category;
    final interval = r.interval.isEmpty ? '—' : '${r.interval[0].toUpperCase()}${r.interval.substring(1)}';
    // date of the next booking, short enough to never be cut off
    final when = r.active ? Dates.dayMonth(RecurringService.nextDate(r)) : 'pausiert';

    return Dismissible(
      key: Key(r.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppColors.error,
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      confirmDismiss: (_) => _delete(r),
      child: Opacity(
        opacity: r.active ? 1 : 0.5,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          child: Row(
            children: [
              CategoryAvatar(r.category, isIncome: r.isIncome, merchant: r.note),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text('$interval · $when',
                        style: TextStyle(fontSize: 12, color: AppColors.textDim), overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Text(Money.withSign(r.amountCents, r.isIncome),
                  style: TextStyle(fontWeight: FontWeight.w600, color: r.isIncome ? AppColors.positive : AppColors.text)),
              Switch(value: r.active, onChanged: (v) => _toggle(r, v)),
            ],
          ),
        ),
      ),
    );
  }

  void _toggle(RecurringRule r, bool active) async {
    HapticFeedback.selectionClick();
    r.active = active;
    await DB.updateRule(r);
    // catch up immediately when re-enabling
    if (active) await RecurringService.process();
    if (mounted) setState(() {});
  }

  // deletes right away and offers an undo. Returning false keeps the row in
  // place until the box notifies, so the Dismissible never lingers dismissed.
  Future<bool> _delete(RecurringRule r) async {
    HapticFeedback.mediumImpact();
    await DB.deleteRule(r.id);
    if (mounted) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(persist: false, duration: const Duration(seconds: 5), 
        content: Text('${r.note ?? r.category} gelöscht'),
        action: SnackBarAction(label: 'Rückgängig', textColor: AppColors.primary, onPressed: () => DB.addRule(r)),
      ));
    }
    return false;
  }
}
