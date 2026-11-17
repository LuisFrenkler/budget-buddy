// "Was Buddy getan hat": every card the person confirmed, newest first, each
// with Rückgängig while it can still be taken back.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../services/buddy_log.dart';
import '../utils/dates.dart';
import '../utils/theme.dart';
import '../widgets/buddy_orb.dart';

class BuddyLogScreen extends StatelessWidget {
  const BuddyLogScreen({super.key});

  static IconData _icon(String kind) => switch (kind) {
        'budget' => Icons.pie_chart_outline_rounded,
        'goal' => Icons.flag_outlined,
        'cancel' => Icons.mark_email_read_outlined,
        'category' => Icons.label_outline_rounded,
        'save' => Icons.savings_outlined,
        _ => Icons.notifications_none_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: BuddyLog.changed,
      builder: (context, _, __) {
        final entries = BuddyLog.all();
        return Scaffold(
          appBar: AppBar(title: Text(tr('Was Ahead getan hat'))),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const BuddyOrb(size: 40),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    tr('Ahead macht nur, was du bestätigst. Hier steht, was er angelegt oder geändert hat. Fast alles lässt sich zurücknehmen.'),
                    style: TextStyle(color: AppColors.textDim, height: 1.45),
                  ),
                ),
              ]),
              const SizedBox(height: 24),
              if (entries.isEmpty)
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
                  child: Text(tr('Noch nichts. Übernimmst du Budget, Sparziel oder Erinnerung von Ahead, steht es hier.'),
                      style: TextStyle(color: AppColors.textDim, height: 1.45)),
                )
              else
                for (final e in entries)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.hairline),
                    ),
                    child: Row(children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(12)),
                        child: Icon(_icon(e.kind), size: 19, color: AppColors.text),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(e.title,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  decoration: e.undone ? TextDecoration.lineThrough : null,
                                  color: e.undone ? AppColors.textDim : AppColors.text)),
                          const SizedBox(height: 2),
                          Text(
                              e.undone
                                  ? tr('Zurückgenommen')
                                  : '${Dates.dayMonth(e.at)} · ${e.said}',
                              style: TextStyle(fontSize: 12.5, color: AppColors.textDim, height: 1.35)),
                        ]),
                      ),
                      if (e.canUndo)
                        TextButton(
                          onPressed: () async {
                            HapticFeedback.mediumImpact();
                            final said = await BuddyLog.undo(e.id);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(said)));
                            }
                          },
                          child: Text(tr('Rückgängig')),
                        ),
                    ]),
                  ),
            ],
          ),
        );
      },
    );
  }
}
