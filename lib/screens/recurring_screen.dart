import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/recurring.dart';
import '../services/db.dart';
import '../services/recurring_service.dart';
import '../utils/theme.dart';
import '../utils/money.dart';
import '../widgets/hero_card.dart';

class RecurringScreen extends StatefulWidget {
  const RecurringScreen({super.key});

  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box>(
      valueListenable: Hive.box('recurring').listenable(),
      builder: (_, __, ___) {
        final rules = DB.getRules();
        return Scaffold(
          appBar: AppBar(title: const Text('Wiederkehrend')),
          body: rules.isEmpty
              ? _emptyState()
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [for (final r in rules) _ruleCard(r)],
                ),
        );
      },
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.repeat, size: 64, color: AppColors.textDim),
            const SizedBox(height: 16),
            const Text('Keine Daueraufträge',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Wähle beim Hinzufügen einer Buchung "Wiederholen"',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim)),
          ],
        ),
      ),
    );
  }

  Widget _ruleCard(RecurringRule r) {
    final color = r.isIncome ? AppColors.accent : AppColors.error;
    final next = RecurringService.nextDate(r);
    final nextText =
        '${next.day.toString().padLeft(2, '0')}.${next.month.toString().padLeft(2, '0')}.${next.year}';
    final intervalLabel = r.interval.isEmpty
        ? '—'
        : '${r.interval[0].toUpperCase()}${r.interval.substring(1)}';

    return Dismissible(
      key: Key(r.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(20)),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) => _confirmDelete(r),
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              IconChip(Icons.repeat, color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.category, style: const TextStyle(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text(
                      '$intervalLabel · '
                      '${r.active ? 'nächste $nextText' : 'pausiert'}',
                      style: TextStyle(fontSize: 12, color: AppColors.textDim),
                    ),
                  ],
                ),
              ),
              Text(Money.withSign(r.amountCents, r.isIncome),
                  style: TextStyle(fontWeight: FontWeight.bold, color: color)),
              Switch(
                value: r.active,
                activeThumbColor: AppColors.primary,
                onChanged: (v) => _toggle(r, v),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggle(RecurringRule r, bool active) async {
    r.active = active;
    await DB.updateRule(r);
    // catch up immediately when re-enabling
    if (active) await RecurringService.process();
    if (mounted) setState(() {});
  }

  Future<bool> _confirmDelete(RecurringRule r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Dauerauftrag löschen?'),
        content: Text('${r.category} (${r.interval})\n'
            'Bereits erstellte Buchungen bleiben erhalten.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Nein')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Ja', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirmed == true) {
      await DB.deleteRule(r.id);
      if (mounted) setState(() {});
    }
    return false;
  }
}
