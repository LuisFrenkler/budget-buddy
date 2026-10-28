import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../services/goals_service.dart';
import '../services/plus_service.dart';
import '../utils/theme.dart';

// Honest remaining free-tier counts — used on Plus pitch and Mein Abo empty.
class FreeTierUsage extends StatelessWidget {
  const FreeTierUsage({super.key});

  @override
  Widget build(BuildContext context) {
    final goals = Hive.isBoxOpen('goals')
        ? GoalsService.all().where((g) => !g.reached).length
        : 0;
    final rows = [
      (
        'Buddy KI',
        '${PlusService.left(PlusFeature.aiQuestion)} von ${PlusService.freeAiQuestions} Fragen'
      ),
      (
        'Beleg-Scans',
        '${PlusService.left(PlusFeature.receiptScan)} von ${PlusService.freeReceiptScans} Scans'
      ),
      (
        'Sparziele',
        '$goals von ${PlusService.freeGoals} aktiv'
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Dein Gratis-Kontingent diesen Monat',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppColors.textDim)),
        const SizedBox(height: 8),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              Expanded(child: Text(r.$1, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
              Text(r.$2, style: TextStyle(color: AppColors.primaryText, fontWeight: FontWeight.w700, fontSize: 13)),
            ]),
          ),
      ]),
    );
  }
}
