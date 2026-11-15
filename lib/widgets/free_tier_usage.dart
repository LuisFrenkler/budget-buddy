import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../services/goals_service.dart';
import '../services/plus_service.dart';
import '../utils/theme.dart';
import '../l10n/l10n.dart';

// Honest remaining free-tier counts, on Mein Abo when there is no subscription.
class FreeTierUsage extends StatelessWidget {
  const FreeTierUsage({super.key});

  @override
  Widget build(BuildContext context) {
    final goals = Hive.isBoxOpen('goals')
        ? GoalsService.all().where((g) => !g.reached).length
        : 0;
    final rows = [
      (
        tr('Buddy KI'),
        tr('{x} von {x2} Fragen', {
          'x': PlusService.left(PlusFeature.aiQuestion),
          'x2': PlusService.freeAiQuestions
        })
      ),
      (
        tr('Beleg-Scans'),
        tr('{x} von {x2} Scans', {
          'x': PlusService.left(PlusFeature.receiptScan),
          'x2': PlusService.freeReceiptScans
        })
      ),
      (
        tr('Sparziele'),
        tr('{goals} von {x} aktiv',
            {'goals': goals, 'x': PlusService.freeGoals})
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Dein Gratis-Kontingent diesen Monat'),
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppColors.textDim)),
        const SizedBox(height: 8),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              Expanded(
                  child: Text(r.$1,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13.5))),
              Text(r.$2,
                  style: TextStyle(
                      color: AppColors.primaryText,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ]),
          ),
      ]),
    );
  }
}
