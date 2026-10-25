import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/db.dart';
import '../services/csv_importer.dart';
import '../services/holdings_csv_importer.dart';
import '../services/trade_republic_importer.dart';
import '../services/backup_service.dart';
import '../services/settings_service.dart';
import '../services/auth_service.dart';
import '../services/file_saver.dart';
import '../utils/theme.dart';
import '../models/badge.dart' as badge_model;
import 'recurring_screen.dart';
import 'connections_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box>(
      valueListenable: Hive.box('transactions').listenable(),
      builder: (context, box, child) {
        // get number of transactions from database
        final count = DB.getTx().length;

        return Scaffold(
          appBar: AppBar(title: const Text('Profil')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              
              // card showing total transaction count
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.receipt_long, color: AppColors.primary, size: 32),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$count', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                        Text('Transaktionen', style: TextStyle(color: AppColors.textDim)),
                      ],
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),

              // achievements, kept low-key here instead of on the home screen
              _sectionLabel('Erfolge'),
              _badgeGrid(),

              const SizedBox(height: 24),

              // security section
              _sectionLabel('Sicherheit'),
              Container(
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
                child: SwitchListTile(
                  secondary: const Icon(Icons.lock_outline, color: AppColors.primary),
                  title: const Text('App-Sperre'),
                  subtitle: Text('Face-ID / PIN beim Öffnen',
                      style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                  activeThumbColor: AppColors.primary,
                  value: Settings.appLockEnabled,
                  onChanged: _toggleAppLock,
                ),
              ),

              const SizedBox(height: 24),
              _sectionLabel('Darstellung'),
              Container(
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
                child: SwitchListTile(
                  secondary: const Icon(Icons.dark_mode_outlined, color: AppColors.primary),
                  title: const Text('Dunkler Modus'),
                  activeThumbColor: AppColors.primary,
                  value: ThemeController.isDark.value,
                  onChanged: _toggleDarkMode,
                ),
              ),

              const SizedBox(height: 24),
              _sectionLabel('Live-Verbindung'),
              _dataTile(Icons.sync, 'Konto & Depot verbinden', _openConnections),

              const SizedBox(height: 24),
              _sectionLabel('Automatisch'),
              _dataTile(Icons.repeat, 'Wiederkehrende Buchungen', _openRecurring),

              const SizedBox(height: 24),
              _sectionLabel('Daten'),

              // button to open file picker and import csv
              ElevatedButton.icon(
                onPressed: _importCSV,
                icon: const Icon(Icons.file_upload),
                label: const Text('CSV importieren'),
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
              ),
              const SizedBox(height: 8),
              // show user what format the csv should have
              Text(
                'Format: Datum;Kategorie;Beschreibung;Betrag',
                style: TextStyle(fontSize: 12, color: AppColors.textDim),
              ),
              const SizedBox(height: 16),

              // import an existing depot from a broker CSV export
              _dataTile(Icons.account_balance_wallet_outlined, 'Depot importieren (CSV)', _importDepotCsv),
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text('Format: Name;Symbol;Typ;Anzahl;Kaufpreis;AktuellerKurs',
                    style: TextStyle(fontSize: 12, color: AppColors.textDim)),
              ),
              const SizedBox(height: 16),

              // export and backup actions
              _dataTile(Icons.file_download_outlined, 'Als CSV exportieren', _exportCsv),
              const SizedBox(height: 8),
              _dataTile(Icons.backup_outlined, 'Backup erstellen (JSON)', _backupJson),
              const SizedBox(height: 8),
              _dataTile(Icons.restore, 'Backup wiederherstellen', _restoreJson),

              const SizedBox(height: 24),

              // button to delete all data
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ListTile(
                  leading: const Icon(Icons.delete_outline, color: AppColors.error),
                  title: const Text('Alle Daten löschen'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _deleteAllData,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // small grey section heading
  // two-column grid of achievement badges; locked ones are dimmed
  Widget _badgeGrid() {
    final badges = DB.getBadges();
    return LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - 10) / 2;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [for (final b in badges) _badgeTile(b, w)],
      );
    });
  }

  Widget _badgeTile(badge_model.Badge b, double width) {
    return Opacity(
      opacity: b.isUnlocked ? 1 : 0.4,
      child: Container(
        width: width,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Text(b.emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(b.name,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      overflow: TextOverflow.ellipsis),
                  Text(b.description,
                      style: TextStyle(color: AppColors.textDim, fontSize: 11),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(text,
          style: TextStyle(
              color: AppColors.textDim, fontSize: 13, fontWeight: FontWeight.bold)),
    );
  }

  // a tappable list-tile inside a surface card (used for data actions)
  Widget _dataTile(IconData icon, String title, VoidCallback onTap) {
    return Container(
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(title),
        trailing: Icon(Icons.chevron_right, color: AppColors.textDim),
        onTap: onTap,
      ),
    );
  }

  // helper to show a snackbar
  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? AppColors.error : AppColors.primary,
    ));
  }

  // switches between dark and light theme
  Future<void> _toggleDarkMode(bool value) async {
    ThemeController.isDark.value = value;
    await Settings.setDarkMode(value);
    if (mounted) setState(() {});
  }

  // imports portfolio positions from a CSV (broker export)
  Future<void> _importDepotCsv() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['csv'], withData: true);
    if (result == null || result.files.isEmpty) return;
    try {
      final bytes = result.files.first.bytes;
      if (bytes == null) {
        _snack('Datei konnte nicht gelesen werden', error: true);
        return;
      }
      final content = utf8.decode(bytes, allowMalformed: true);
      // auto-detect a Trade Republic transaction export and reconstruct the
      // depot from it; otherwise expect the simple positions format
      final imported = TradeRepublicImporter.looksLikeTradeRepublic(content)
          ? TradeRepublicImporter.parse(content)
          : HoldingsCsvImporter.parse(content);
      for (final h in imported.holdings) {
        await DB.addHolding(h);
      }
      _snack(imported.skipped > 0
          ? '${imported.holdings.length} Positionen importiert, ${imported.skipped} übersprungen'
          : '${imported.holdings.length} Positionen importiert');
    } catch (e) {
      _snack('Fehler: $e', error: true);
    }
  }

  // opens the recurring rules management screen
  void _openRecurring() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const RecurringScreen()));
  }

  // opens the live bank/depot connection screen
  void _openConnections() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ConnectionsScreen()));
  }

  // enables or disables the app lock (requires a successful auth to enable)
  Future<void> _toggleAppLock(bool value) async {
    if (value) {
      if (!await AuthService.isAvailable()) {
        _snack('Keine Biometrie/PIN auf diesem Gerät', error: true);
        return;
      }
      final ok = await AuthService.authenticate('App-Sperre aktivieren');
      if (!ok) return;
    }
    await Settings.setAppLockEnabled(value);
    if (mounted) setState(() {});
  }

  // writes a CSV export to a temp file and opens the share sheet
  Future<void> _exportCsv() async {
    final txs = DB.getTx();
    if (txs.isEmpty) {
      _snack('Keine Daten zum Exportieren', error: true);
      return;
    }
    try {
      final csv = BackupService.transactionsToCsv(txs);
      await saveTextFile('budgetbuddy_export.csv', csv, text: 'BudgetBuddy Export');
    } catch (e) {
      _snack('Fehler: $e', error: true);
    }
  }

  // shares/downloads a full JSON backup
  Future<void> _backupJson() async {
    try {
      final json = BackupService.toBackupJson();
      await saveTextFile('budgetbuddy_backup.json', json, text: 'BudgetBuddy Backup');
    } catch (e) {
      _snack('Fehler: $e', error: true);
    }
  }

  // picks a JSON backup and restores it (after confirmation, replaces all data)
  Future<void> _restoreJson() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Wiederherstellen?'),
        content: const Text('Ersetzt alle aktuellen Daten durch das Backup.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Wiederherstellen')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final bytes = result.files.first.bytes;
      if (bytes == null) {
        _snack('Datei konnte nicht gelesen werden', error: true);
        return;
      }
      final content = utf8.decode(bytes, allowMalformed: true);
      await BackupService.restoreFromJson(content);
      if (mounted) setState(() {});
      _snack('Wiederhergestellt');
    } catch (e) {
      _snack('Fehler: $e', error: true);
    }
  }

  // opens file picker, reads csv file and imports each line as transaction
  void _importCSV() async {
    // let user pick a csv file from their device
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );

    // user cancelled or didnt pick a file
    if (result == null || result.files.isEmpty) return;

    try {
      // read the picked file's bytes (works on web and mobile)
      final bytes = result.files.first.bytes;
      if (bytes == null) {
        _snack('Datei konnte nicht gelesen werden', error: true);
        return;
      }
      final content = utf8.decode(bytes, allowMalformed: true);
      final imported = CsvImporter.parse(content);

      // save every parsed transaction to the database
      for (final tx in imported.transactions) {
        await DB.addTx(tx);
      }

      // check if user unlocked any badges
      await DB.checkBadges();

      // show how many were imported and how many lines were skipped
      if (mounted) {
        final msg = imported.skipped > 0
            ? '${imported.transactions.length} importiert, ${imported.skipped} übersprungen'
            : '${imported.transactions.length} importiert';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AppColors.primary),
        );
      }
    } catch (e) {
      // something went wrong, show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _deleteAllData() async {
    // show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Alle Daten löschen?'),
        content: const Text('Kann nicht rückgängig gemacht werden.'),
        actions: [
          // cancel button, returns false
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Nein'),
          ),
          // confirm button, returns true
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ja', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    // if user confirmed, delete everything
    if (confirmed == true) {
      await DB.clearAll();
      
      // show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gelöscht'), backgroundColor: AppColors.primary),
        );
      }
    }
  }
}
