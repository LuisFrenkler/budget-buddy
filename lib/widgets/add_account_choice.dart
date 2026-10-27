// "+ Konto" and the Depot's +: a real account or depot first, by hand second.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../screens/connections_screen.dart';
import '../services/settings_service.dart';
import '../utils/theme.dart';
import 'account_sheet.dart';

enum _Choice { bank, depot, hand }

// [depot]: offered from the Depot tab, where "by hand" means a position
Future<void> showAddAccountChoice(BuildContext context, {bool depot = false, VoidCallback? byHand}) async {
  HapticFeedback.selectionClick();
  final choice = await showModalBottomSheet<_Choice>(
    context: context,
    // as tall as its options, not capped at half the screen
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    builder: (sheet) {
      Widget option(_Choice c, IconData icon, Color color, String title, String text) => ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            leading: CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.15),
              child: Icon(icon, color: color),
            ),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(text, style: TextStyle(color: AppColors.textDim)),
            onTap: () => Navigator.pop(sheet, c),
          );
      return SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!depot)
            option(_Choice.bank, Icons.account_balance_rounded, AppColors.primary,
                Settings.bankState.isEmpty ? 'Bankkonto verbinden' : 'Weitere Bank verbinden',
                'ING, Sparkasse, DKB, N26 und viele mehr'),
          option(_Choice.depot, Icons.trending_up_rounded, AppColors.accentBlue,
              Settings.depotState.isEmpty ? 'Depot verbinden' : 'Depot-Verbindung ansehen',
              'Trade Republic, Scalable und andere, über Parqet'),
          option(_Choice.hand, depot ? Icons.edit_note_rounded : Icons.edit_rounded, AppColors.textDim,
              depot ? 'Position von Hand' : 'Konto von Hand',
              depot ? 'Aktie, ETF oder Krypto selbst eintragen' : 'Bargeld oder ein Konto ohne Verbindung'),
          const SizedBox(height: 8),
        ]),
      );
    },
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case _Choice.bank || _Choice.depot:
      await Navigator.push(context,
          MaterialPageRoute(builder: (_) => ConnectionsScreen(start: choice == _Choice.bank ? 'bank' : 'depot')));
    case _Choice.hand:
      if (byHand != null) {
        byHand();
      } else {
        await showAccountSheet(context);
      }
  }
}
