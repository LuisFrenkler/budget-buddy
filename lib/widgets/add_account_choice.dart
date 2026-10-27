// "+ Konto" and the Depot's +: a real account or depot first, by hand second.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../screens/connections_screen.dart';
import '../services/settings_service.dart';
import '../utils/theme.dart';
import 'account_sheet.dart';
import 'import_flows.dart';

enum _Choice { bank, depot, hand, file }

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
              Settings.depotState.isEmpty ? 'Depot verbinden' : 'Weiteres Depot hinzufügen',
              'Trade Republic, Scalable und andere, über Parqet'),
          option(_Choice.hand, depot ? Icons.edit_note_rounded : Icons.edit_rounded, AppColors.textDim,
              depot ? 'Position von Hand' : 'Konto von Hand',
              depot ? 'Aktie, ETF oder Krypto selbst eintragen' : 'Bargeld oder ein Konto ohne Verbindung'),
          option(_Choice.file, Icons.upload_file_rounded, AppColors.textDim, 'Aus Datei importieren',
              depot ? 'CSV aus Excel oder Trade-Republic-Export' : 'CSV-Export deiner Bank oder aus Excel'),
          const SizedBox(height: 8),
        ]),
      );
    },
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case _Choice.depot when Settings.depotState.isNotEmpty:
      await _furtherDepot(context);
    case _Choice.bank || _Choice.depot:
      await Navigator.push(context,
          MaterialPageRoute(builder: (_) => ConnectionsScreen(start: choice == _Choice.bank ? 'bank' : 'depot')));
    case _Choice.file:
      depot ? await importDepot(context) : await importBookings(context);
    case _Choice.hand:
      if (byHand != null) {
        byHand();
      } else {
        await showAccountSheet(context);
      }
  }
}

// a depot next to the linked one: Parqet gathers several brokers under one
// login, so most of the time the new broker is added there; a second
// Parqet login (a partner's, say) is linked like the first
Future<void> _furtherDepot(BuildContext context) async {
  final pick = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Weiteres Depot', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('Dein Depot kommt über Parqet. Dort kannst du mehrere Broker gleichzeitig verbinden.',
              style: TextStyle(color: AppColors.textDim, height: 1.4)),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: () => Navigator.pop(sheet, 'parqet'),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Broker in Parqet hinzufügen'),
          ),
          const SizedBox(height: 6),
          Text('Danach in BudgetBuddy auf Aktualisieren tippen, dann erscheint das neue Depot für sich.',
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
          const SizedBox(height: 14),
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () => Navigator.pop(sheet, 'login'),
            child: const Text('Anderes Parqet-Konto verbinden'),
          ),
        ]),
      ),
    ),
  );
  if (pick == null || !context.mounted) return;
  if (pick == 'parqet') {
    await launchUrl(Uri.parse('https://app.parqet.com'), mode: LaunchMode.externalApplication);
  } else {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const ConnectionsScreen(start: 'depot')));
  }
}
