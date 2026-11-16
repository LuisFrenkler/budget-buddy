import 'buddy_memory_screen.dart';
import 'data_screen.dart';
import 'invite_screen.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
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
import 'tax_screen.dart';
import 'vorsorge_screen.dart';
import 'account_settings_screen.dart';
import '../services/avatar_service.dart';
import '../widgets/user_avatar.dart';
import '../widgets/settings_list.dart';
import '../widgets/sync_pill.dart';
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
      if (Settings.depotState.isNotEmpty) Settings.depotBroker.isNotEmpty ? Settings.depotBroker : tr('Depot'),
      for (final l in Settings.extraDepots) l.broker.isNotEmpty ? l.broker : tr('Depot'),
    ];
    return linked.isEmpty ? tr('ING, Sparkasse, Trade Republic & Co. verbinden') : '${linked.join(', ')} verbunden';
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
                        Text(account?.name ?? tr('Konto'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(account?.email ?? tr('Tippen für Konto-Einstellungen'),
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
                SettingsRow(
                  icon: Icons.savings_outlined,
                  title: tr('Sparquote'),
                  subtitle: tr('Vom Einkommen übrig'),
                  value: rate == null ? '–' : '$rate %',
                  onTap: () => _explainRate(tx),
                ),
              ]),

              const SizedBox(height: 20),
              _plusCard(),
              // Alltag first: account, lock, banks, each at most one tap from here
              SectionLabel(tr('Konto')),
              SettingsGroup([
                if (account != null)
                  SettingsRow(
                    icon: Icons.manage_accounts_rounded,
                    title: tr('Mein Konto'),
                    subtitle: tr('Name und Sicherheit'),
                    onTap: _openAccount,
                  )
                else
                  SettingsRow(
                    icon: Icons.person_add_alt_1_rounded,
                    title: tr('Konto erstellen'),
                    subtitle: tr('Für Bank und Sync'),
                    onTap: _signUp,
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
                _switch(Icons.lock_rounded, tr('App-Sperre'), _lockHint, Settings.appLockEnabled, _toggleAppLock),
              ]),

              SectionLabel(tr('Finanzen')),
              SettingsGroup([
                SettingsRow(
                  icon: Icons.account_balance_rounded,
                  title: tr('Banken & Depots'),
                  subtitle: _linkedText(),
                  onTap: _openConnections,
                ),
                SettingsRow(
                  icon: Icons.sync_rounded,
                  title: tr('Synchronisation'),
                  subtitle: _syncHint(),
                  onTap: _syncNow,
                ),
                SettingsRow(
                  icon: Icons.savings_rounded,
                  title: tr('Budgets'),
                  subtitle: tr('Monatliche Limits'),
                  onTap: () => _toAccount(1),
                ),
                SettingsRow(
                  icon: Icons.pie_chart_outline_rounded,
                  title: tr('Kategorien'),
                  subtitle: tr('Sortierung'),
                  onTap: () => _toAccount(2),
                ),
              ]),

              SectionLabel(tr('Erscheinungsbild')),
              SettingsGroup([
                _switch(Icons.dark_mode_rounded, tr('Dunkler Modus'), null,
                    ThemeController.isDark.value, _toggleDarkMode),
                _switch(Icons.visibility_off_rounded, tr('Beträge verbergen'), null,
                    Settings.hideAmounts.value, (v) async {
                  await Settings.setHideAmounts(v);
                  if (mounted) setState(() {});
                }),
                SettingsRow(
                  icon: Icons.translate_rounded,
                  title: tr('Sprache'),
                  subtitle: L10n.names[L10n.lang.value]!,
                  onTap: _pickLanguage,
                ),
              ]),

              SectionLabel(tr('Planen')),
              SettingsGroup([
                SettingsRow(
                  icon: Icons.flag_rounded,
                  title: tr('Sparziele'),
                  subtitle: tr('Urlaub, Notgroschen'),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GoalsScreen())),
                ),
                SettingsRow(
                  icon: Icons.receipt_long_rounded,
                  title: tr('Verträge & Abos'),
                  subtitle: tr('Erkannt'),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ContractsScreen())),
                ),
                SettingsRow(
                  icon: Icons.call_split_rounded,
                  title: tr('Geteilte Ausgaben'),
                  subtitle: tr('Mit Freunden'),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SplitsScreen())),
                ),
              ]),

              SectionLabel(tr('Privatsphäre & KI')),
              SettingsGroup([
                _switch(Icons.cloud_outlined, tr('Buddy mit KI'),
                    tr('Nur mit Zustimmung'), BuddyService.hasConsent, (v) async {
                  await BuddyService.live();
                  await BuddyService.setConsent(v);
                  if (mounted) setState(() {});
                }),
                SettingsRow(
                  icon: Icons.bookmark_outline_rounded,
                  title: tr('Was Buddy weiß'),
                  subtitle: tr('Von dir bestätigt'),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BuddyMemoryScreen())),
                ),
                SettingsRow(
                  icon: Icons.privacy_tip_outlined,
                  title: tr('Wo deine Daten liegen'),
                  subtitle: tr('Übersicht'),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DataScreen())),
                ),
              ]),

              SectionLabel(tr('Ahead')),
              SettingsGroup([
                SettingsRow(
                  icon: Icons.card_giftcard_rounded,
                  title: tr('Freunde einladen'),
                  subtitle: tr('Mehr Buddy-Fragen'),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InviteScreen())),
                ),
                SettingsRow(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: tr('Feedback senden'),
                  subtitle: tr('Was wir besser machen können'),
                  onTap: _sendFeedback,
                ),
                SettingsRow(
                  icon: Icons.help_outline_rounded,
                  title: tr('Hilfe & Lizenzen'),
                  subtitle: tr('Support, Open Source'),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutScreen())),
                ),
                SettingsRow(
                  icon: Icons.apartment_rounded,
                  title: tr('Unternehmen & Vertrauen'),
                  subtitle: tr('Rechtliches & Kontakt'),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CompanyScreen())),
                ),
              ]),

              _advancedHeader(),
              if (_advanced)
                SettingsGroup([
                  SettingsRow(
                    icon: Icons.account_balance_wallet_rounded,
                    title: tr('Vermögen & Absicherung'),
                    subtitle: tr('Notgroschen, Schulden'),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WealthScreen())),
                  ),
                  SettingsRow(
                    icon: Icons.timelapse_rounded,
                    title: tr('Vorsorge'),
                    subtitle: tr('Rentenlücke grob schätzen'),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VorsorgeScreen())),
                  ),
                  SettingsRow(
                    icon: Icons.receipt_long_rounded,
                    title: tr('Steuer {y}', {'y': DateTime.now().year}),
                    subtitle: tr('Was mit der Steuererklärung zurückkommt'),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TaxScreen())),
                  ),
                  SettingsRow(
                    icon: Icons.swap_vert_rounded,
                    title: tr('Import, Export & Backup'),
                    subtitle: tr('CSV und Sicherung'),
                    onTap: _openDataTools,
                  ),
                  if (account != null)
                    SettingsRow(
                      icon: Icons.logout_rounded,
                      title: tr('Abmelden'),
                      subtitle: account.email,
                      onTap: () => AccountSettingsScreen.logout(context),
                    ),
                  SettingsRow(
                    icon: Icons.restart_alt_rounded,
                    title: tr('App zurücksetzen'),
                    subtitle: tr('Alle Daten auf diesem Gerät'),
                    onTap: _resetApp,
                    danger: true,
                  ),
                  if (account != null)
                    SettingsRow(
                      icon: Icons.person_remove_rounded,
                      title: tr('Konto löschen'),
                      subtitle: tr('Endgültig'),
                      onTap: () => AccountSettingsScreen.deleteAccount(context),
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

  // Plus status: an invitation, or the subscription with its next date
  Widget _plusCard() {
    return ValueListenableBuilder<String?>(
      valueListenable: PlusService.syncError,
      builder: (context, syncErr, _) => ValueListenableBuilder<Subscription?>(
        valueListenable: PlusService.subscription,
        builder: (context, sub, _) {
          final plus = sub != null;
          final now = DateTime.now();
          final trialOk = StorePurchases.supported &&
              ((StorePurchases.trial[PlusPlan.yearly] ?? false) ||
                  (StorePurchases.trial[PlusPlan.monthly] ?? false));
          final freePitch =
              tr('Gratis: {x} KI-Fragen, {x2} Belege, 1 Sparziel{x3}', {'x': PlusService.freeAiQuestions, 'x2': PlusService.freeReceiptScans, 'x3': trialOk ? tr(' · 7 Tage Plus testen') : tr(' · Plus ohne Limit')});
          final subtitle = syncErr ??
              (sub == null
                  ? freePitch
                  : sub.cancelled
                      ? tr('Gekündigt · aktiv bis {x}', {'x': Dates.dayMonth(sub.endsAt!)})
                      : sub.inTrial(now)
                          ? tr('Gratis-Test bis {x} · Abo verwalten', {'x': Dates.dayMonth(sub.trialEnds)})
                          : tr('Nächste Zahlung {x} · Abo verwalten', {'x': Dates.dayMonth(sub.periodEnd(now))}));
          return Material(
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: Ink(
              decoration: BoxDecoration(
                color: plus || syncErr != null ? AppColors.surface : AppColors.brand,
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
                    Icon(syncErr != null ? Icons.sync_problem_rounded : Icons.workspace_premium_outlined,
                        size: 26, color: syncErr != null ? AppColors.warningText : AppColors.primaryText),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                            syncErr != null
                                ? tr('Plus-Status unklar')
                                : plus
                                    ? tr('Mein Abo · Plus')
                                    : tr('Ahead Plus'),
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
                  subtitle: tr('Für Excel oder die Steuer'),
                  onTap: _exportCsv,
                ),
                SettingsRow(
                  icon: Icons.cloud_upload_rounded,
                  title: tr('Backup erstellen'),
                  subtitle: tr('Alle Daten als eine Datei'),
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

  void _toAccount(int segment) {
    AccountScreen.pendingSegment.value = segment;
    Navigator.popUntil(context, (r) => r.isFirst);
  }

  String _syncHint() {
    final parts = <String>[];
    if (Settings.bankState.isNotEmpty || Settings.extraBanks.isNotEmpty) {
      parts.add(tr('Bank {x}', {'x': SyncPill.ago(Settings.lastSync, DateTime.now())}));
    }
    if (Settings.depotState.isNotEmpty || Settings.extraDepots.isNotEmpty) {
      parts.add(tr('Depot {x}', {'x': SyncPill.ago(Settings.depotSync, DateTime.now())}));
    }
    final signedIn = AccountService.current.value != null;
    if (signedIn && Hive.box('settings').get('vaultDirty') == true) {
      parts.add(tr('Kontokopie ausstehend'));
    } else if (signedIn) {
      parts.add(tr('Kontokopie verschlüsselt'));
    } else {
      parts.add(tr('Kontokopie mit einem Konto'));
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
      _snack(tr('Nichts zu synchronisieren. Verbinde eine Bank oder erstelle ein Konto.'));
      return;
    }
    _snack(signedIn
        ? tr('Bank, Depot und Kontokopie wurden angestoßen.')
        : tr('Bank und Depot wurden angestoßen. Die Kontokopie braucht ein Konto.'));
  }

  Future<void> _sendFeedback() async {
    final uri = Uri(
      scheme: 'mailto',
      path: LegalInfo.email,
      query: 'subject=${Uri.encodeComponent(tr('Feedback zu Ahead'))}'
          '&body=${Uri.encodeComponent(tr('Was gut läuft:\nWas hakt:\n'))}',
    );
    if (!await launchUrl(uri) && mounted) {
      _snack(tr('Schreib an {email}', {'email': LegalInfo.email}));
    }
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
            Text(tr('Erweitert'),
                style: TextStyle(color: AppColors.textDim, fontSize: 13, fontWeight: FontWeight.bold)),
            const Spacer(),
            Text(_advanced ? tr('Einklappen') : tr('Backup, Zurücksetzen, Konto'),
                style: TextStyle(color: AppColors.textDim, fontSize: 12)),
            Icon(_advanced ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppColors.textDim, size: 20),
          ]),
        ),
      ),
    );
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
            Text(rate == null ? tr('Sparquote') : tr('Sparquote: {rate} %', {'rate': rate}),
                style: const TextStyle(fontFamily: AppFonts.display, fontSize: 22, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(tr('Was vom Einkommen übrig bleibt, über die letzten drei vollen Monate. Der laufende Monat zählt erst danach, sonst verzerrt das Gehalt die Zahl.'),
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
                        ? tr('kein Einkommen')
                        : tr('{x} von {y}', {'x': Money.format(m.income - m.spent), 'y': Money.format(m.income)}),
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
            Text(tr('Gut sind 10 bis 20 %. Sparziele zählen mit, solange das Geld auf dem Konto bleibt.'),
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
