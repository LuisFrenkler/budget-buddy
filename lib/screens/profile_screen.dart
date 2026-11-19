import 'data_screen.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/db.dart';
import '../widgets/import_flows.dart';
import '../services/backup_service.dart';
import '../services/settings_service.dart';
import '../services/auth_service.dart';
import '../services/file_saver.dart';
import '../utils/theme.dart';
import '../utils/dates.dart';
import '../utils/errors.dart';
import 'connections_screen.dart';
import 'auth_screens.dart';
import '../services/account_service.dart';
import '../services/plus_service.dart';
import '../services/store_purchases.dart';
import 'subscription_screen.dart';
import 'places_screen.dart';
import 'plus_screen.dart';
import 'company_screen.dart';
import 'account_settings_screen.dart';
import '../services/avatar_service.dart';
import '../widgets/user_avatar.dart';
import '../widgets/settings_list.dart';
import 'notification_settings_screen.dart';
import '../legal/legal_info.dart';
import '../services/notification_service.dart';
import '../services/buddy_service.dart';
import '../l10n/l10n.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _lockHint = tr('Gerätecode beim Öffnen');

  @override
  void initState() {
    super.initState();
    AuthService.lockSubtitle().then((s) {
      if (mounted) setState(() => _lockHint = s);
    });
    // provider known → Schalter liest den richtigen Consent-Key
    BuddyService.live().then((_) {
      if (mounted) setState(() {});
    });
  }

  // "ING und Depot verbunden"; nothing linked says nothing
  static String? _linkedText() {
    final linked = [
      if (Settings.bankName.isNotEmpty) Settings.bankName,
      for (final l in Settings.extraBanks) l.bank,
      if (Settings.depotState.isNotEmpty) Settings.depotBroker.isNotEmpty ? Settings.depotBroker : tr('Depot'),
      for (final l in Settings.extraDepots) l.broker.isNotEmpty ? l.broker : tr('Depot'),
    ];
    return linked.isEmpty ? null : '${linked.join(', ')} verbunden';
  }

  @override
  Widget build(BuildContext context) {
    // bookings, the account (name changes) and settings (bank, depot links)
    // all show here, so a change on another page shows when coming back
    return ListenableBuilder(
      listenable: Listenable.merge(
          [Hive.box('transactions').listenable(), Hive.box('settings').listenable(), AccountService.current]),
      builder: (context, child) {
        final account = AccountService.current.value;

        return Scaffold(
          appBar: AppBar(title: Text(tr('Profil'))),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              // header: avatar and a few personal numbers; leads to the account
              InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: account != null ? _openAccount : _signUp,
                child: Row(
                children: [
                  GestureDetector(
                    onTap: account == null ? null : () => _pickAvatar(context),
                    child: Stack(children: [
                      UserAvatar(name: account?.name, size: 64, fontSize: 26),
                      if (account != null)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                            child: Icon(Icons.camera_alt_rounded, size: 12, color: AppColors.onPrimary),
                          ),
                        ),
                    ]),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(account?.name ?? tr('Konto erstellen'),
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(account?.email ?? tr('Für Bank und Sync'),
                            style: TextStyle(color: AppColors.textDim, fontSize: 13), overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
                ],
              ),
              ),
              // a header and three short groups: everything else is one sentence to Ahead away
              SectionLabel(tr('Ahead')),
              SettingsGroup([
                // everything the app has, in one list: nothing is reachable only by asking
                SettingsRow(
                  key: const Key('all-places'),
                  icon: Icons.apps_rounded,
                  title: tr('Alle Bereiche'),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlacesScreen())),
                ),
                _membershipRow(),
                SettingsRow(
                  icon: Icons.account_balance_rounded,
                  title: tr('Banken & Depots'),
                  subtitle: _linkedText(),
                  onTap: _openConnections,
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: NotificationService.enabled,
                  builder: (context, on, _) => SettingsRow(
                    icon: Icons.notifications_rounded,
                    title: tr('Mitteilungen'),
                    subtitle: on ? tr('An') : tr('Aus'),
                    onTap: _openNotifications,
                  ),
                ),
              ]),

              SectionLabel(tr('Schutz und Daten')),
              SettingsGroup([
                _switch(Icons.lock_rounded, tr('App-Sperre'), _lockHint, Settings.appLockEnabled, _toggleAppLock),
                _switch(Icons.visibility_off_rounded, tr('Beträge verbergen'), null,
                    Settings.hideAmounts.value, (v) async {
                  await Settings.setHideAmounts(v);
                  if (mounted) setState(() {});
                }),
                _switch(Icons.cloud_outlined, tr('Ahead mit KI'),
                    tr('Nur mit Zustimmung'), BuddyService.hasConsent, (v) async {
                  await BuddyService.live();
                  await BuddyService.setConsent(v);
                  if (mounted) setState(() {});
                }),
                SettingsRow(
                  icon: Icons.privacy_tip_outlined,
                  title: tr('Wo deine Daten liegen'),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DataScreen())),
                ),
                // stays until backup and restore have a home on the data page: this is their only door
                SettingsRow(
                  icon: Icons.swap_vert_rounded,
                  title: tr('Import, Export & Backup'),
                  onTap: _openDataTools,
                ),
              ]),

              // the two settings Ahead cannot change for you yet
              SectionLabel(tr('Erscheinungsbild')),
              SettingsGroup([
                _switch(Icons.dark_mode_rounded, tr('Dunkler Modus'), null,
                    ThemeController.isDark.value, _toggleDarkMode),
                SettingsRow(
                  icon: Icons.translate_rounded,
                  title: tr('Sprache'),
                  subtitle: L10n.names[L10n.lang.value]!,
                  onTap: _pickLanguage,
                ),
              ]),

              SectionLabel(tr('Hilfe')),
              SettingsGroup([
                SettingsRow(
                  icon: Icons.help_outline_rounded,
                  title: tr('Hilfe & Rechtliches'),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CompanyScreen())),
                ),
                if (account != null)
                  SettingsRow(
                    icon: Icons.logout_rounded,
                    title: tr('Abmelden'),
                    onTap: () => AccountSettingsScreen.logout(context),
                  ),
                // the only door to a reset, so it stays
                SettingsRow(
                  icon: Icons.restart_alt_rounded,
                  title: tr('App zurücksetzen'),
                  subtitle: tr('Alle Daten auf diesem Gerät'),
                  onTap: _resetApp,
                  danger: true,
                ),
              ]),
              const SizedBox(height: 24),
              Center(
                child: Text(tr('Ahead {appVersion}', {'appVersion': LegalInfo.appVersion}), style: TextStyle(color: AppColors.textDim, fontSize: 12)),
              ),
            ],
          ),
        );
      },
    );
  }

  // Ahead Plus, the paid version; a running subscription keeps its dates and the way to manage it
  Widget _membershipRow() {
    return ValueListenableBuilder<String?>(
      valueListenable: PlusService.syncError,
      builder: (context, syncErr, _) => ValueListenableBuilder<Subscription?>(
        valueListenable: PlusService.subscription,
        builder: (context, sub, _) {
          final now = DateTime.now();
          return SettingsRow(
            icon: syncErr != null ? Icons.sync_problem_rounded : Icons.workspace_premium_outlined,
            title: sub != null ? tr('Mein Abo') : 'Ahead Plus',
            subtitle: syncErr ??
                (sub == null
                    ? null
                    : sub.cancelled
                        ? tr('Gekündigt · aktiv bis {x}', {'x': Dates.dayMonth(sub.endsAt!)})
                        : sub.inTrial(now)
                            ? tr('Gratis-Test bis {x} · Abo verwalten', {'x': Dates.dayMonth(sub.trialEnds)})
                            : tr('Nächste Zahlung {x} · Abo verwalten', {'x': Dates.dayMonth(sub.periodEnd(now))})),
            onTap: () async {
              if (syncErr != null) {
                await PlusService.syncWithServer(fresh: true);
                return;
              }
              await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => sub != null ? const SubscriptionScreen() : const PlusScreen()));
            },
          );
        },
      ),
    );
  }

  Future<void> _pickAvatar(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(tr('Profilbild wählen')),
            onTap: () => Navigator.pop(context, 'pick'),
          ),
          if (AvatarService.bytes() != null)
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: Text(tr('Profilbild entfernen')),
              onTap: () => Navigator.pop(context, 'clear'),
            ),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(this.context);
    try {
      if (choice == 'clear') {
        await AvatarService.clear();
        messenger.showSnackBar(SnackBar(content: Text(tr('Profilbild entfernt'))));
        return;
      }
      final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      final file = result?.files.single;
      if (file?.bytes == null) return;
      await AvatarService.set(file!.bytes!);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(tr('Profilbild gespeichert'))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void _signUp() => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignUpScreen()));

  void _openAccount() =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountSettingsScreen()));

  void _openNotifications() =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationSettingsScreen()));

  // the rarely used data tools on their own page, so the profile stays short
  void _openDataTools() => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(tr('Import, Export & Backup'))),
            body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), children: [
              SectionLabel(tr('Importieren')),
              SettingsGroup([
                SettingsRow(
                  icon: Icons.file_upload_rounded,
                  title: tr('Umsätze importieren'),
                  subtitle: tr('CSV deiner Bank, in ein Konto deiner Wahl'),
                  onTap: () => importBookings(context),
                ),
                SettingsRow(
                  icon: Icons.show_chart_rounded,
                  title: tr('Depot importieren'),
                  subtitle: tr('CSV oder Trade-Republic-Export, in ein Depot'),
                  onTap: () => importDepot(context),
                ),
              ]),
              SectionLabel(tr('Sichern')),
              SettingsGroup([
                SettingsRow(
                  icon: Icons.file_download_rounded,
                  title: tr('Als CSV exportieren'),
                  onTap: _exportCsv,
                ),
                SettingsRow(
                  icon: Icons.cloud_upload_rounded,
                  title: tr('Backup erstellen'),
                  onTap: _backupJson,
                ),
                SettingsRow(
                  icon: Icons.restore_rounded,
                  title: tr('Backup wiederherstellen'),
                  subtitle: tr('Ersetzt die Daten auf diesem Gerät'),
                  onTap: _restoreJson,
                ),
              ]),
              const SizedBox(height: 16),
              Text(tr('Deine Daten liegen auf diesem Gerät. Ein Backup hilft, wenn du das Handy wechselst.'),
                  textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.4)),
            ]),
          ),
        ),
      );

  void _openConnections() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ConnectionsScreen()));
  }

  // each language is named in itself, so it can be found from either side
  Future<void> _pickLanguage() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final code in L10n.supported)
            ListTile(
              title: Text(L10n.names[code]!, style: const TextStyle(fontWeight: FontWeight.w600)),
              trailing: code == L10n.lang.value ? Icon(Icons.check_rounded, color: AppColors.text) : null,
              onTap: () => Navigator.pop(context, code),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (picked == null || picked == L10n.lang.value) return;
    await L10n.set(picked);
    if (mounted) setState(() {});
  }

  Widget _switch(IconData icon, String title, String? subtitle, bool value, ValueChanged<bool> onChanged) {
    return SettingsRow(
      icon: icon,
      title: title,
      subtitle: (subtitle == null || subtitle.isEmpty) ? null : subtitle,
      trailing: Switch(value: value, onChanged: onChanged),
    );
  }

  Future<bool> _confirm(String title, String text, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Abbrechen'))),
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

  // helper to show a snackbar
  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(milliseconds: 2800), 
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

  // enables or disables the app lock (requires a successful auth to enable)
  Future<void> _toggleAppLock(bool value) async {
    if (value) {
      if (!await AuthService.isAvailable()) {
        _snack(tr('Keine Biometrie/PIN auf diesem Gerät'), error: true);
        return;
      }
      final ok = await AuthService.authenticate(tr('App-Sperre aktivieren'));
      if (!ok) return;
    }
    await Settings.setAppLockEnabled(value);
    if (mounted) setState(() {});
  }

  // writes a CSV export to a temp file and opens the share sheet
  Future<void> _exportCsv() async {
    final txs = DB.getTx();
    if (txs.isEmpty) {
      _snack(tr('Keine Daten zum Exportieren'), error: true);
      return;
    }
    try {
      final csv = BackupService.transactionsToCsv(txs);
      await saveTextFile('ahead_export.csv', csv, text: tr('Ahead Export'));
    } catch (e) {
      _snack(friendlyError(e), error: true);
    }
  }

  // shares/downloads a full JSON backup
  Future<void> _backupJson() async {
    try {
      final json = BackupService.toBackupJson();
      await saveTextFile('ahead_backup.json', json, text: tr('Ahead Backup'));
    } catch (e) {
      _snack(friendlyError(e), error: true);
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
        title: Text(tr('Wiederherstellen?')),
        content: Text(tr('Ersetzt alle aktuellen Daten durch das Backup.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Abbrechen'))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Wiederherstellen'))),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final bytes = result.files.first.bytes;
      if (bytes == null) {
        _snack(tr('Datei konnte nicht gelesen werden'), error: true);
        return;
      }
      final content = utf8.decode(bytes, allowMalformed: true);
      await BackupService.restoreFromJson(content);
      if (mounted) setState(() {});
      _snack(tr('Wiederhergestellt'));
    } catch (e) {
      _snack(friendlyError(e), error: true);
    }
  }

  // deletes everything on this device and starts over like a fresh install;
  // a server account stays and can be used to sign in again
  Future<void> _resetApp() async {
    final ok = await _confirm(
        tr('App zurücksetzen?'),
        tr('Alle Umsätze, Budgets, Depot-Positionen und Einstellungen auf diesem Gerät werden gelöscht. {x}', {'x': AccountService.current.value != null ? tr('Du wirst abgemeldet, dein Konto bleibt bestehen. ') : ''}) +
            // a store subscription keeps running and is brought back with "Käufe wiederherstellen"
            tr('{x}Das lässt sich nicht rückgängig machen.', {'x': PlusService.subscription.value?.fromStore == true ? tr('Dein Plus-Abo läuft im {storeName} weiter; hol es danach mit „Käufe wiederherstellen“ zurück. ', {'storeName': StorePurchases.storeName}) : ''}),
        tr('Zurücksetzen'));
    if (!ok) return;
    await DB.clearAll();
    if (AccountService.current.value != null) await AccountService.logout();
    await Settings.resetApp();
    await PlusService.end();
    if (mounted) Navigator.popUntil(context, (r) => r.isFirst);
  }
}
