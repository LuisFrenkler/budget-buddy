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
import '../models/transaction.dart';
import '../services/savings_rate.dart';
import '../utils/money.dart';
import 'connections_screen.dart';
import 'auth_screens.dart';
import '../services/account_service.dart';
import '../services/plus_service.dart';
import '../services/store_purchases.dart';
import '../services/cloud_sync.dart';
import '../services/bank_sync.dart';
import '../services/depot_sync.dart';
import 'plus_screen.dart';
import 'subscription_screen.dart';
import 'about_screen.dart';
import 'company_screen.dart';
import 'account_screen.dart';
import 'splits_screen.dart';
import 'contracts_screen.dart';
import 'goals_screen.dart';
import 'wealth_screen.dart';
import 'vorsorge_screen.dart';
import 'account_settings_screen.dart';
import '../services/avatar_service.dart';
import '../widgets/user_avatar.dart';
import '../widgets/settings_list.dart';
import '../widgets/sync_pill.dart';
import 'notification_settings_screen.dart';
import '../legal/legal_info.dart';
import '../legal/legal_texts.dart';
import '../services/notification_service.dart';
import '../services/buddy_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _lockHint = 'Gerätecode beim Öffnen';
  bool _advanced = false;

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

  // "ING und Depot verbunden", or what linking brings
  static String _linkedText() {
    final linked = [
      if (Settings.bankName.isNotEmpty) Settings.bankName,
      for (final l in Settings.extraBanks) l.bank,
      if (Settings.depotState.isNotEmpty) Settings.depotBroker.isNotEmpty ? Settings.depotBroker : 'Depot',
      for (final l in Settings.extraDepots) l.broker.isNotEmpty ? l.broker : 'Depot',
    ];
    return linked.isEmpty ? 'ING, Sparkasse, Trade Republic & Co. verbinden' : '${linked.join(', ')} verbunden';
  }

  @override
  Widget build(BuildContext context) {
    // bookings, the account (name changes) and settings (bank, depot links)
    // all show here, so a change on another page shows when coming back
    return ListenableBuilder(
      listenable: Listenable.merge(
          [Hive.box('transactions').listenable(), Hive.box('settings').listenable(), AccountService.current]),
      builder: (context, child) {
        final tx = DB.getTx();
        final rate = SavingsRate.headline(tx);
        // oldest transaction = the user's start with the app
        final since = tx.isEmpty ? null : tx.last.date;
        final account = AccountService.current.value;

        return Scaffold(
          appBar: AppBar(title: const Text('Profil')),
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
                            decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                            child: const Icon(Icons.camera_alt_rounded, size: 12, color: Colors.white),
                          ),
                        ),
                    ]),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(account?.name ?? 'Konto', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(account?.email ?? 'Tippen für Konto-Einstellungen',
                            style: TextStyle(color: AppColors.textDim, fontSize: 13), overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
                ],
              ),
              ),
              const SizedBox(height: 20),
              SettingsGroup([
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(children: [
                    _stat('${tx.length}', 'Umsätze'),
                    _stat(since == null ? '–' : Dates.month(since), 'Dabei seit'),
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _explainRate(tx),
                        child: Column(children: [
                          Text(rate == null ? '–' : '$rate %',
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Text('Sparquote', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                            const SizedBox(width: 3),
                            Icon(Icons.info_outline_rounded, size: 13, color: AppColors.textDim),
                          ]),
                        ]),
                      ),
                    ),
                  ]),
                ),
              ]),

              const SizedBox(height: 20),
              _plusCard(),
              // Alltag first: account, lock, banks — each at most one tap from here
              const SectionLabel('Konto'),
              SettingsGroup([
                if (account != null)
                  SettingsRow(
                    icon: Icons.manage_accounts_rounded,
                    title: 'Mein Konto',
                    subtitle: 'Name, E-Mail, Sicherheit',
                    onTap: _openAccount,
                  )
                else
                  SettingsRow(
                    icon: Icons.person_add_alt_1_rounded,
                    title: 'Konto erstellen',
                    subtitle: 'Für die Bankverbindung und neue Geräte',
                    onTap: _signUp,
                  ),
                ValueListenableBuilder<bool>(
                  valueListenable: NotificationService.enabled,
                  builder: (context, on, _) => SettingsRow(
                    icon: Icons.notifications_rounded,
                    title: 'Mitteilungen',
                    subtitle: on ? 'An · nur wenn es zählt, keine Werbung' : 'Aus',
                    onTap: _openNotifications,
                  ),
                ),
                _switch(Icons.lock_rounded, 'App-Sperre', _lockHint, Settings.appLockEnabled, _toggleAppLock),
              ]),

              const SectionLabel('Finanzen'),
              SettingsGroup([
                SettingsRow(
                  icon: Icons.account_balance_rounded,
                  title: 'Banken & Depots',
                  subtitle: _linkedText(),
                  onTap: _openConnections,
                ),
                SettingsRow(
                  icon: Icons.sync_rounded,
                  title: 'Synchronisation',
                  subtitle: _syncHint(),
                  onTap: _syncNow,
                ),
                SettingsRow(
                  icon: Icons.savings_rounded,
                  title: 'Budgets',
                  subtitle: 'Limits pro Kategorie, im Konto',
                  onTap: () => _toAccount(1),
                ),
                SettingsRow(
                  icon: Icons.pie_chart_outline_rounded,
                  title: 'Kategorien',
                  subtitle: 'Ausgaben nach Kategorie. Umsortieren einer Buchung merkt sich den Händler.',
                  onTap: () => _toAccount(2),
                ),
              ]),

              const SectionLabel('Erscheinungsbild'),
              SettingsGroup([
                _switch(Icons.dark_mode_rounded, 'Dunkler Modus', 'Gilt für die ganze App',
                    ThemeController.isDark.value, _toggleDarkMode),
                _switch(Icons.visibility_off_rounded, 'Beträge verbergen', 'Auch über das Auge auf dem Start',
                    Settings.hideAmounts.value, (v) async {
                  await Settings.setHideAmounts(v);
                  if (mounted) setState(() {});
                }),
              ]),

              const SectionLabel('Planen'),
              SettingsGroup([
                SettingsRow(
                  icon: Icons.flag_rounded,
                  title: 'Sparziele',
                  subtitle: 'Urlaub, Notgroschen, große Anschaffungen',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GoalsScreen())),
                ),
                SettingsRow(
                  icon: Icons.account_balance_wallet_rounded,
                  title: 'Vermögen & Absicherung',
                  subtitle: 'Notgroschen, Sparquote, Schulden, Versicherungen — keine Vermittlung',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WealthScreen())),
                ),
                SettingsRow(
                  icon: Icons.timelapse_rounded,
                  title: 'Vorsorge',
                  subtitle: 'Rentenlücke grob schätzen — Orientierung, keine Beratung',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VorsorgeScreen())),
                ),
                SettingsRow(
                  icon: Icons.receipt_long_rounded,
                  title: 'Verträge & Abos',
                  subtitle: 'Aus Buchungen erkannt — Miete, Streaming, Abos',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ContractsScreen())),
                ),
                SettingsRow(
                  icon: Icons.call_split_rounded,
                  title: 'Geteilte Ausgaben',
                  subtitle: 'Mit Code live teilen — oder nur auf dem Gerät',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SplitsScreen())),
                ),
              ]),

              const SectionLabel('Privatsphäre & KI'),
              SettingsGroup([
                _switch(Icons.auto_awesome_rounded, 'Buddy mit KI',
                    'Nur mit Zustimmung. Zusammenfassung ohne Kontonummern.', BuddyService.hasConsent, (v) async {
                  await BuddyService.live();
                  await BuddyService.setConsent(v);
                  if (mounted) setState(() {});
                }),
                SettingsRow(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Was das Gerät verlässt',
                  subtitle: 'Bank, Kontokopie, KI, Kurse',
                  onTap: _whatLeaves,
                ),
              ]),

              const SectionLabel('BudgetBuddy'),
              SettingsGroup([
                SettingsRow(
                  icon: Icons.apartment_rounded,
                  title: 'Unternehmen & Vertrauen',
                  subtitle: 'Wofür wir stehen, Karriere, Rechtliches',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CompanyScreen())),
                ),
              ]),

              _advancedHeader(),
              if (_advanced)
                SettingsGroup([
                  SettingsRow(
                    icon: Icons.swap_vert_rounded,
                    title: 'Import, Export & Backup',
                    subtitle: 'Bank-CSV, Depot, Sicherung auf diesem Gerät',
                    onTap: _openDataTools,
                  ),
                  if (account != null)
                    SettingsRow(
                      icon: Icons.logout_rounded,
                      title: 'Abmelden',
                      subtitle: account.email,
                      onTap: () => AccountSettingsScreen.logout(context),
                    ),
                  SettingsRow(
                    icon: Icons.restart_alt_rounded,
                    title: 'App zurücksetzen',
                    subtitle: 'Alle Daten auf diesem Gerät löschen',
                    onTap: _resetApp,
                    danger: true,
                  ),
                  if (account != null)
                    SettingsRow(
                      icon: Icons.person_remove_rounded,
                      title: 'Konto löschen',
                      subtitle: 'Konto, Bankverbindungen und Cloud-Kopie, endgültig',
                      onTap: () => AccountSettingsScreen.deleteAccount(context),
                      danger: true,
                    ),
                ]),
              const SizedBox(height: 24),
              Center(
                child: Text('BudgetBuddy ${LegalInfo.appVersion}', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
              ),
            ],
          ),
        );
      },
    );
  }

  // Plus status: an invitation, or the subscription with its next date
  Widget _plusCard() {
    return ValueListenableBuilder<String?>(
      valueListenable: PlusService.syncError,
      builder: (context, syncErr, _) => ValueListenableBuilder<Subscription?>(
        valueListenable: PlusService.subscription,
        builder: (context, sub, _) {
          final plus = sub != null;
          final now = DateTime.now();
          final subtitle = syncErr != null
              ? syncErr
              : sub == null
                  ? 'Buddy, Belege und Ziele ohne Limit · 7 Tage gratis'
                  : sub.cancelled
                      ? 'Gekündigt · aktiv bis ${Dates.dayMonth(sub.endsAt!)}'
                      : sub.inTrial(now)
                          ? 'Gratis-Test bis ${Dates.dayMonth(sub.trialEnds)} · Abo verwalten'
                          : 'Nächste Zahlung ${Dates.dayMonth(sub.periodEnd(now))} · Abo verwalten';
          return Material(
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: Ink(
              decoration: BoxDecoration(
                gradient: plus || syncErr != null ? null : const LinearGradient(colors: AppColors.heroBrand),
                color: plus || syncErr != null ? AppColors.surface : null,
              ),
              child: InkWell(
                onTap: () async {
                  if (syncErr != null) {
                    await PlusService.syncWithServer(fresh: true);
                    return;
                  }
                  if (plus) {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const SubscriptionScreen()));
                  } else {
                    await showPlus(context);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Text(syncErr != null ? '⚠️' : plus ? '✨' : '🚀', style: const TextStyle(fontSize: 24)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                            syncErr != null
                                ? 'Plus-Status unklar'
                                : plus
                                    ? 'Mein Abo · Plus'
                                    : 'BudgetBuddy Plus',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                color: plus || syncErr != null ? AppColors.text : Colors.white)),
                        Text(subtitle,
                            style: TextStyle(
                                fontSize: 13,
                                color: syncErr != null
                                    ? AppColors.warningText
                                    : plus
                                        ? AppColors.textDim
                                        : Colors.white70)),
                      ]),
                    ),
                    Icon(Icons.chevron_right_rounded, color: plus || syncErr != null ? AppColors.textDim : Colors.white),
                  ]),
                ),
              ),
            ),
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
            title: const Text('Profilbild wählen'),
            onTap: () => Navigator.pop(context, 'pick'),
          ),
          if (AvatarService.bytes() != null)
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Profilbild entfernen'),
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
        messenger.showSnackBar(const SnackBar(content: Text('Profilbild entfernt')));
        return;
      }
      final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      final file = result?.files.single;
      if (file?.bytes == null) return;
      await AvatarService.set(file!.bytes!);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Profilbild gespeichert')));
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
            appBar: AppBar(title: const Text('Import, Export & Backup')),
            body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), children: [
              const SectionLabel('Importieren'),
              SettingsGroup([
                SettingsRow(
                  icon: Icons.file_upload_rounded,
                  title: 'Umsätze importieren',
                  subtitle: 'CSV deiner Bank, in ein Konto deiner Wahl',
                  onTap: () => importBookings(context),
                ),
                SettingsRow(
                  icon: Icons.show_chart_rounded,
                  title: 'Depot importieren',
                  subtitle: 'CSV oder Trade-Republic-Export, in ein Depot',
                  onTap: () => importDepot(context),
                ),
              ]),
              const SectionLabel('Sichern'),
              SettingsGroup([
                SettingsRow(
                  icon: Icons.file_download_rounded,
                  title: 'Als CSV exportieren',
                  subtitle: 'Für Excel oder die Steuer',
                  onTap: _exportCsv,
                ),
                SettingsRow(
                  icon: Icons.cloud_upload_rounded,
                  title: 'Backup erstellen',
                  subtitle: 'Alle Daten als eine Datei',
                  onTap: _backupJson,
                ),
                SettingsRow(
                  icon: Icons.restore_rounded,
                  title: 'Backup wiederherstellen',
                  subtitle: 'Ersetzt die Daten auf diesem Gerät',
                  onTap: _restoreJson,
                ),
              ]),
              const SizedBox(height: 16),
              Text('Deine Daten liegen auf diesem Gerät. Ein Backup ist die einfachste Versicherung, '
                  'wenn du das Handy wechselst.',
                  textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.4)),
            ]),
          ),
        ),
      );

  void _openConnections() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ConnectionsScreen()));
  }

  void _toAccount(int segment) {
    AccountScreen.pendingSegment.value = segment;
    Navigator.popUntil(context, (r) => r.isFirst);
  }

  String _syncHint() {
    final parts = <String>[];
    if (Settings.bankState.isNotEmpty || Settings.extraBanks.isNotEmpty) {
      parts.add('Bank ${SyncPill.ago(Settings.lastSync, DateTime.now())}');
    }
    if (Settings.depotState.isNotEmpty || Settings.extraDepots.isNotEmpty) {
      parts.add('Depot ${SyncPill.ago(Settings.depotSync, DateTime.now())}');
    }
    final signedIn = AccountService.current.value != null;
    if (signedIn && Hive.box('settings').get('vaultDirty') == true) {
      parts.add('Kontokopie ausstehend');
    } else if (signedIn) {
      parts.add('Kontokopie verschlüsselt');
    } else {
      parts.add('Kontokopie mit einem Konto');
    }
    return parts.join(' · ');
  }

  Future<void> _syncNow() async {
    final signedIn = AccountService.current.value != null;
    try {
      if (signedIn) await CloudSync.start();
      await BankSync.refreshIfStale(maxAge: Duration.zero);
      await DepotSync.refreshIfStale(maxAge: Duration.zero);
    } catch (e) {
      _snack(friendlyError(e), error: true);
      return;
    }
    if (!mounted) return;
    setState(() {});
    final linked = Settings.bankState.isNotEmpty ||
        Settings.extraBanks.isNotEmpty ||
        Settings.depotState.isNotEmpty ||
        Settings.extraDepots.isNotEmpty;
    if (!signedIn && !linked) {
      _snack('Nichts zu synchronisieren. Verbinde eine Bank oder erstelle ein Konto.');
      return;
    }
    _snack(signedIn
        ? 'Bank, Depot und Kontokopie wurden angestoßen.'
        : 'Bank und Depot wurden angestoßen. Die Kontokopie braucht ein Konto.');
  }

  void _whatLeaves() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Was das Gerät verlässt', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(
              'Buchungen, Budgets, Ziele und Depot bleiben auf diesem Gerät. Mit einem Konto '
              'liegt zusätzlich eine Kopie bei uns, verschlüsselt mit deinem Passwort.\n\n'
              'Bank und Depot nur, wenn du sie verbindest. Den Login machst du bei der Bank '
              '(Enable Banking) oder bei Parqet. Zugangsdaten sehen wir nicht.\n\n'
              'Buddy schickt nur mit dem Schalter oben eine Zusammenfassung ohne Kontonummern '
              'an den KI-Anbieter. Kurse fragen nur das Börsenkürzel ab, nicht dein Depot. '
              'Mitteilungen plant das Gerät selbst.',
              style: TextStyle(color: AppColors.textDim, height: 1.45),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    this.context,
                    MaterialPageRoute(builder: (_) => LegalDocScreen(doc: LegalTexts.privacy)),
                  );
                },
                child: const Text('Datenschutzerklärung'),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _advancedHeader() {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8, left: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _advanced = !_advanced),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Text('Erweitert',
                style: TextStyle(color: AppColors.textDim, fontSize: 13, fontWeight: FontWeight.bold)),
            const Spacer(),
            Text(_advanced ? 'Einklappen' : 'Backup, Zurücksetzen, Konto',
                style: TextStyle(color: AppColors.textDim, fontSize: 12)),
            Icon(_advanced ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppColors.textDim, size: 20),
          ]),
        ),
      ),
    );
  }

  Widget _switch(IconData icon, String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return SettingsRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
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

  // how the savings rate comes about, month by month
  void _explainRate(List<Transaction> tx) {
    final months = SavingsRate.months(tx);
    final rate = SavingsRate.headline(tx);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(rate == null ? 'Sparquote' : 'Sparquote: $rate %',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Wie viel von deinem Einkommen übrig bleibt, über die letzten drei abgeschlossenen Monate. '
                'Der laufende Monat zählt erst mit, wenn er vorbei ist, sonst würde das Gehalt am '
                'Monatsanfang die Zahl verzerren.',
                style: TextStyle(color: AppColors.textDim, height: 1.4)),
            const SizedBox(height: 14),
            for (final m in months)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(children: [
                  Expanded(
                    child: Text('${Dates.months[m.month.month - 1]}${m.running ? ' (bisher)' : ''}',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, color: m.running ? AppColors.textDim : AppColors.text)),
                  ),
                  Text(
                    m.income <= 0
                        ? 'kein Einkommen'
                        : '${Money.format(m.income - m.spent)} von ${Money.format(m.income)}',
                    style: TextStyle(color: AppColors.textDim, fontSize: 13),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text(m.rate == null ? '–' : '${m.rate} %',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: (m.rate ?? 0) < 0 ? AppColors.errorText : AppColors.text)),
                  ),
                ]),
              ),
            const SizedBox(height: 8),
            Text('Gut sind 10 bis 20 %. Was du auf Sparziele legst, zählt mit, solange es auf deinem Konto bleibt.',
                style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.4)),
          ]),
        ),
      ),
    );
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
      _snack(friendlyError(e), error: true);
    }
  }

  // shares/downloads a full JSON backup
  Future<void> _backupJson() async {
    try {
      final json = BackupService.toBackupJson();
      await saveTextFile('budgetbuddy_backup.json', json, text: 'BudgetBuddy Backup');
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
      _snack(friendlyError(e), error: true);
    }
  }

  // deletes everything on this device and starts over like a fresh install;
  // a server account stays and can be used to sign in again
  Future<void> _resetApp() async {
    final ok = await _confirm(
        'App zurücksetzen?',
        'Alle Umsätze, Budgets, Depot-Positionen und Einstellungen auf diesem Gerät werden gelöscht. '
            '${AccountService.current.value != null ? 'Du wirst abgemeldet, dein Konto bleibt bestehen. ' : ''}'
            // a store subscription keeps running and is brought back with "Käufe wiederherstellen"
            '${PlusService.subscription.value?.fromStore == true ? 'Dein Plus-Abo läuft im ${StorePurchases.storeName} weiter; hol es danach mit „Käufe wiederherstellen“ zurück. ' : ''}'
            'Das lässt sich nicht rückgängig machen.',
        'Zurücksetzen');
    if (!ok) return;
    await DB.clearAll();
    if (AccountService.current.value != null) await AccountService.logout();
    await Settings.resetApp();
    await PlusService.end();
    if (mounted) Navigator.popUntil(context, (r) => r.isFirst);
  }
}
