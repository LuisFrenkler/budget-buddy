// Dumb Sonstiges cleanup: list merchants, pick a category, apply to all of them.
// Only touches Sonstiges. No Umbuchung (that would skew spending without changing Konto).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/category_coach.dart';
import '../services/ledger_busy.dart';
import '../utils/money.dart';
import '../utils/theme.dart';

Future<void> showMiscSortSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (context) => const _MiscSortSheet(),
  );
}

class _MiscSortSheet extends StatefulWidget {
  const _MiscSortSheet();

  @override
  State<_MiscSortSheet> createState() => _MiscSortSheetState();
}

class _MiscSortSheetState extends State<_MiscSortSheet> {
  Future<void> _assign(CategoryGroup g) async {
    final list = g.isIncome
        ? Categories.income
            .where((c) =>
                !Categories.isExpenseOnly(c['name']!) &&
                c['name'] != Categories.transfer)
            .toList()
        : Categories.expense
            .where((c) =>
                c['name'] != 'Sonstiges' && c['name'] != Categories.transfer)
            .toList();
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('„${g.sample}“',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                    '${g.count}× in Sonstiges · ${Money.format(g.cents)} — nur diese Sonstiges-Buchungen.',
                    style: TextStyle(color: AppColors.textDim, height: 1.35)),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in list)
                      ActionChip(
                        avatar: Icon(Categories.icon(c['name']!),
                            size: 18, color: Categories.color(c['name']!)),
                        label: Text(c['name']!),
                        onPressed: () => Navigator.pop(context, c['name']),
                      ),
                  ],
                ),
              ]),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    HapticFeedback.selectionClick();
    LedgerBusy.enter();
    final n = await CategoryCoach.apply(g.sample, picked,
        isIncome: g.isIncome, key: g.key);
    LedgerBusy.leave();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(milliseconds: 2800),
      content: Text(n <= 0
          ? 'Nichts geändert'
          : '$n ${n == 1 ? 'Buchung' : 'Buchungen'} → $picked'),
    ));
    setState(() {});
    if (CategoryCoach.miscCount() == 0 && mounted) Navigator.pop(context);
  }

  Future<void> _applyAllSuggestions() async {
    final fixes = CategoryCoach.autoFixes(limit: 40);
    if (fixes.isEmpty) return;
    HapticFeedback.mediumImpact();
    LedgerBusy.enter();
    var n = 0;
    for (final p in fixes) {
      n += await CategoryCoach.apply(p.sample, p.category, isIncome: p.isIncome);
    }
    LedgerBusy.leave();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(milliseconds: 2800),
      content: Text(n <= 0
          ? 'Nichts geändert'
          : '$n ${n == 1 ? 'Buchung' : 'Buchungen'} zugeordnet'),
    ));
    setState(() {});
    if (CategoryCoach.miscCount() == 0 && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final groups = CategoryCoach.groups(limit: 40);
    final fixes = CategoryCoach.autoFixes(limit: 8);
    final n = CategoryCoach.miscCount();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      maxChildSize: 0.92,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        children: [
          const Text('Buchungen einordnen',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
              n == 0
                  ? 'Sonstiges ist leer.'
                  : '$n in Sonstiges — Vorschlag antippen oder selbst wählen.',
              style: TextStyle(color: AppColors.textDim, height: 1.35)),
          if (fixes.isNotEmpty) ...[
            const SizedBox(height: 14),
            FilledButton.tonalIcon(
              onPressed: _applyAllSuggestions,
              icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
              label: Text(
                  '${fixes.fold<int>(0, (s, p) => s + p.count)} Vorschläge übernehmen'),
            ),
            const SizedBox(height: 8),
            for (final p in fixes)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(p.sample,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                    '${p.count}× · ${Money.format(p.cents)} → ${p.category}'),
                trailing: TextButton(
                  onPressed: () async {
                    HapticFeedback.selectionClick();
                    // taken before the wait: this context may be gone afterwards
                    final messenger = ScaffoldMessenger.of(context);
                    final navigator = Navigator.of(context);
                    LedgerBusy.enter();
                    final int moved;
                    try {
                      moved = await CategoryCoach.apply(p.sample, p.category, isIncome: p.isIncome);
                    } finally {
                      LedgerBusy.leave();
                    }
                    if (!mounted) return;
                    messenger.showSnackBar(SnackBar(content: Text('$moved → ${p.category}')));
                    setState(() {});
                    if (CategoryCoach.miscCount() == 0) navigator.pop();
                  },
                  child: const Text('OK'),
                ),
              ),
            Divider(color: AppColors.border),
          ],
          const SizedBox(height: 8),
          if (groups.isEmpty && fixes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Text('Nichts offen.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textDim)),
            )
          else
            for (final g in groups)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(g.sample,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${g.count}× · ${Money.format(g.cents)}'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _assign(g),
              ),
        ],
      ),
    );
  }
}
