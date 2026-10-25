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
import '../utils/dates.dart';
import '../models/badge.dart' as badge_model;
import 'recurring_screen.dart';
import 'connections_screen.dart';
import 'auth_screens.dart';
import '../services/account_service.dart';
import '../services/plus_service.dart';
import 'plus_screen.dart';

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
        final tx = DB.getTx();
        final badges = DB.getBadges();
        final unlocked = badges.where((b) => b.isUnlocked).length;
        // oldest transaction = the user's start with the app
        final since = tx.isEmpty ? null : tx.last.date;
        final account = AccountService.current.value;

        return Scaffold(
          appBar: AppBar(title: const Text('Profil')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              // header: avatar and a few personal numbers
              Row(
                children: [
                  _avatar(account),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(account?.name ?? 'Gast', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(account?.email ?? 'Ohne Konto · Daten nur auf diesem Gerät',
                            style: TextStyle(color: AppColors.textDim, fontSize: 13), overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _group([
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(children: [
                    _stat('${tx.length}', 'Umsätze'),
                    _stat(since == null ? '–' : Dates.month(since), 'Dabei seit'),
                    _stat('$unlocked/${badges.length}', 'Erfolge'),
                  ]),
                ),
              ]),

              // achievements, kept low-key here instead of on the home screen
              _sectionLabel('Erfolge'),
              _badgeGrid(badges),

              const SizedBox(height: 20),
              _plusCard(),
              _sectionLabel('Sicherheit & Darstellung'),
              _group([
                _switchRow(Icons.lock_rounded, 'App-Sperre', 'Face ID / PIN beim Öffnen',
                    Settings.appLockEnabled, _toggleAppLock),
                _switchRow(Icons.dark_mode_rounded, 'Dunkler Modus', null, ThemeController.isDark.value,
                    _toggleDarkMode),
              ]),

              _sectionLabel('Automatisierung'),
              _group([
                _row(Icons.repeat_rounded, 'Wiederkehrende Buchungen', 'Miete, Gehalt, Abos', _openRecurring),
                _row(
                    Icons.sync_rounded,
                    'Konto & Depot verbinden',
                    Settings.bankName.isNotEmpty ? '${Settings.bankName} verbunden' : 'Girokonto per PSD2, Depot per Parqet',
                    _openConnections),
              ]),

              _sectionLabel('Daten'),
              _group([
                _row(Icons.file_upload_rounded, 'Umsätze importieren', 'CSV: Datum;Kategorie;Beschreibung;Betrag',
                    _importCSV),
                _row(Icons.show_chart_rounded, 'Depot importieren', 'CSV oder Trade-Republic-Export', _importDepotCsv),
                _row(Icons.file_download_rounded, 'Als CSV exportieren', null, _exportCsv),
                _row(Icons.cloud_upload_rounded, 'Backup erstellen', 'Alle Daten als JSON', _backupJson),
                _row(Icons.restore_rounded, 'Backup wiederherstellen', null, _restoreJson),
              ]),

              _sectionLabel('Konto'),
              _group([
                if (account == null) ...[
                  _row(Icons.person_add_alt_1_rounded, 'Konto erstellen', 'Für die Bankverbindung', _signUp),
                  _row(Icons.logout_rounded, 'Gastmodus beenden', 'Zurück zum Start, Daten bleiben', _leaveGuest),
                ] else ...[
                  _row(Icons.logout_rounded, 'Abmelden', null, _logout),
                  _row(Icons.person_remove_rounded, 'Konto löschen', 'Konto und Bankverbindungen entfernen',
                      _deleteAccount, danger: true),
                ],
                _row(Icons.restart_alt_rounded, 'App zurücksetzen', 'Alle Daten löschen und neu starten',
                    _resetApp, danger: true),
              ]),
              const SizedBox(height: 24),
              Center(
                child: Text('BudgetBuddy 1.0', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
              ),
            ],
          ),
        );
      },
    );
  }

  // Plus status: an invitation, or what is active
  Widget _plusCard() {
    return ValueListenableBuilder<bool>(
      valueListenable: PlusService.active,
      builder: (context, plus, _) => Material(
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            gradient: plus ? null : const LinearGradient(colors: AppColors.heroBrand),
            color: plus ? AppColors.surface : null,
          ),
          child: InkWell(
            onTap: plus ? null : () => showPlus(context),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Text(plus ? '✨' : '🚀', style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(plus ? 'BudgetBuddy Plus aktiv' : 'BudgetBuddy Plus',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16, color: plus ? AppColors.text : Colors.white)),
                    Text(plus ? 'Testmodus, ohne Zahlung' : 'Buddy, Belege und Ziele ohne Limit · 7 Tage gratis',
                        style: TextStyle(fontSize: 13, color: plus ? AppColors.textDim : Colors.white70)),
                  ]),
                ),
                if (plus)
                  TextButton(onPressed: PlusService.cancelTest, child: const Text('Beenden'))
                else
                  const Icon(Icons.chevron_right_rounded, color: Colors.white),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  // round avatar with the initial of the signed-in user
  Widget _avatar(Account? account) {
    return Container(
      width: 64,
      height: 64,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: AppColors.heroBrand, begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: account == null
          ? const Icon(Icons.person_rounded, color: Colors.white, size: 32)
          : Text(account.name.isEmpty ? '?' : account.name[0].toUpperCase(),
              style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
    );
  }

  void _signUp() => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignUpScreen()));

  Future<void> _logout() async {
    final ok = await _confirm('Abmelden?', 'Deine Daten bleiben auf diesem Gerät. Zum Öffnen meldest du dich wieder an.',
        'Abmelden');
    if (!ok) return;
    await AccountService.logout();
    if (mounted) Navigator.popUntil(context, (r) => r.isFirst);
  }

  Future<void> _deleteAccount() async {
    final ok = await _confirm(
        'Konto löschen?',
        'Dein Konto und alle Bankverbindungen werden dauerhaft gelöscht. '
            'Umsätze auf diesem Gerät bleiben, bis du sie unter „Alle Daten löschen“ entfernst.',
        'Endgültig löschen');
    if (!ok) return;
    try {
      await AccountService.deleteAccount();
      if (mounted) Navigator.popUntil(context, (r) => r.isFirst);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<bool> _confirm(String title, String text, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  // one value of the header statistics
  Widget _stat(String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
        ],
      ),
    );
  }

  // rows grouped in one rounded surface, separated by thin lines
  Widget _group(List<Widget> rows) {
    return Container(
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 60, color: AppColors.border),
            rows[i],
          ],
        ],
      ),
    );
  }

  Widget _icon(IconData icon, Color color) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(9)),
      child: Icon(icon, color: color, size: 18),
    );
  }

  // tappable settings row with an optional explanation below the title
  Widget _row(IconData icon, String title, String? subtitle, VoidCallback onTap, {bool danger = false}) {
    final color = danger ? AppColors.error : AppColors.primary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            _icon(icon, color),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(fontWeight: FontWeight.w600, color: danger ? AppColors.error : AppColors.text)),
                  if (subtitle != null)
                    Text(subtitle,
                        style: TextStyle(color: AppColors.textDim, fontSize: 12), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (!danger) Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
          ],
        ),
      ),
    );
  }

  Widget _switchRow(IconData icon, String title, String? subtitle, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Row(
        children: [
          _icon(icon, AppColors.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (subtitle != null) Text(subtitle, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  // icons instead of emojis, so badges match the rest of the app
  static const _badgeIcons = {
    'first': Icons.flag_rounded,
    'saver': Icons.savings_rounded,
    'master': Icons.insights_rounded,
    'week': Icons.event_available_rounded,
  };

  // two-column grid of achievement badges; locked ones are dimmed
  Widget _badgeGrid(List<badge_model.Badge> badges) {
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
    final color = b.isUnlocked ? AppColors.warning : AppColors.textDim;
    return Opacity(
      opacity: b.isUnlocked ? 1 : 0.5,
      child: Container(
        width: width,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            _icon(_badgeIcons[b.id] ?? Icons.emoji_events_rounded, color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(b.name,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      overflow: TextOverflow.ellipsis),
                  Text(b.isUnlocked ? b.description : 'Noch offen: ${b.description}',
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
      padding: const EdgeInsets.only(top: 24, bottom: 8, left: 4),
      child: Text(text,
          style: TextStyle(
              color: AppColors.textDim, fontSize: 13, fontWeight: FontWeight.bold)),
    );
  }

  // helper to show a snackbar
  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? AppColors.error : null,
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
          SnackBar(content: Text(msg)),
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

  Future<void> _leaveGuest() async {
    await Settings.setGuest(false);
    if (mounted) Navigator.popUntil(context, (r) => r.isFirst);
  }

  // deletes everything on this device and starts over like a fresh install;
  // a server account stays and can be used to sign in again
  Future<void> _resetApp() async {
    final ok = await _confirm(
        'App zurücksetzen?',
        'Alle Umsätze, Budgets, Depot-Positionen und Einstellungen auf diesem Gerät werden gelöscht. '
            '${AccountService.current.value != null ? 'Du wirst abgemeldet, dein Konto bleibt bestehen. ' : ''}'
            'Das lässt sich nicht rückgängig machen.',
        'Zurücksetzen');
    if (!ok) return;
    await DB.clearAll();
    if (AccountService.current.value != null) await AccountService.logout();
    await Settings.resetApp();
    PlusService.load();
    if (mounted) Navigator.popUntil(context, (r) => r.isFirst);
  }
}
