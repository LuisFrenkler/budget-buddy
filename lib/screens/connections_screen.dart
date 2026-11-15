import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/money_accounts.dart';
import '../services/account_isolation.dart';
import '../services/account_service.dart';
import 'auth_screens.dart';
import 'contracts_screen.dart';
import 'profile_screen.dart';
import '../services/backend_service.dart';
import '../services/bank_search.dart';
import '../services/bank_sync.dart';
import '../services/db.dart';
import '../services/depot_sync.dart';
import '../services/settings_service.dart';
import '../utils/dates.dart';
import '../utils/money.dart';
import '../utils/theme.dart';
import '../widgets/instrument_avatar.dart';
import '../l10n/l10n.dart';

// Links a real bank account (Enable Banking / PSD2) and a depot (Trade
// Republic and other brokers through Parqet Connect) through the backend.
// See backend/README.md.
//
// Linking a bank: pick it, log in on the bank's own page in the browser,
// and the app notices the granted access by itself (it polls the backend),
// then imports balance and bookings right away.
class ConnectionsScreen extends StatefulWidget {
  // 'bank' or 'depot': opened from "+ Konto" / Depot's +, the connection starts right away
  final String? start;
  const ConnectionsScreen({super.key, this.start});

  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  bool _checking = true;
  // null = server not reachable, otherwise 'live' or 'demo'
  String? _mode;
  bool _syncing = false;
  // null = server not reachable, otherwise 'live' or 'demo'
  String? _depotMode;
  bool _depotBusy = false;
  String? _depotPending;
  // the Parqet login in the browser is for a further depot
  bool _addingDepot = false;
  String? _depotLink;
  Timer? _depotPoll;

  // consent started in the browser and not finished yet
  String? _pendingState;
  String? _pendingBank;
  String? _pendingLink;
  Timer? _poll;
  // the consent in the browser is for a further bank, not the first one
  bool _addingBank = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _depotPoll?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    final health = await BackendService.health();
    if (mounted) {
      setState(() {
        _mode = health?['bank'] as String?;
        _depotMode = health == null ? null : '${health['depot'] ?? 'demo'}';
        _checking = false;
      });
      // asked for from elsewhere: straight to the bank list or the Parqet login
      final signedIn = AccountService.current.value != null;
      if (signedIn &&
          health != null &&
          widget.start == 'bank' &&
          _pendingState == null) {
        _connectBank(extra: Settings.bankState.isNotEmpty);
      } else if (signedIn && health != null && widget.start == 'depot') {
        _connectDepot(extra: Settings.depotState.isNotEmpty);
      }
    }
  }

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      duration: const Duration(milliseconds: 2800),
      content: Text(text),
      backgroundColor: error ? AppColors.error : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Verbindungen'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          Text(
              tr('Kontostand und Umsätze, automatisch.'),
              style: TextStyle(color: AppColors.textDim, fontSize: 15)),
          if (!_checking && _mode == null) ...[
            const SizedBox(height: 16),
            _offlineBanner(),
          ],
          _label(tr('Girokonto')),
          _bankCard(),
          _label(tr('Depot')),
          _depotCard(),
          const SizedBox(height: 24),
          _serverStatus(),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 28, bottom: 10, left: 4),
        child: Text(text,
            style: TextStyle(
                color: AppColors.textDim,
                fontSize: 13,
                fontWeight: FontWeight.bold)),
      );

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: AppColors.surface, borderRadius: BorderRadius.circular(20)),
        child: child,
      );

  // --- bank card ---

  // the first bank, every further one, and a way to add another
  Widget _bankCard() {
    final extras = Settings.extraBanks;
    if (Settings.bankState.isEmpty && extras.isEmpty) return _firstBankCard();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (Settings.bankState.isNotEmpty) _linkedCard() else _firstBankCard(),
      for (final l in extras) ...[
        const SizedBox(height: 12),
        _extraBankCard(l.state, l.bank)
      ],
      const SizedBox(height: 12),
      if (_pendingState != null && _addingBank)
        _waitingCard()
      else if (Settings.bankState.isNotEmpty)
        OutlinedButton.icon(
          style:
              OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: () => _connectBank(extra: true),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(tr('Weitere Bank verbinden')),
        ),
    ]);
  }

  // a bank linked after the first: its accounts with their balances
  Widget _extraBankCard(String state, String bank) {
    final tx = DB.getTx();
    final accounts =
        MoneyAccounts.others.where((a) => a.link == state).toList();
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          InstrumentAvatar(bank, size: 44),
          const SizedBox(width: 14),
          Expanded(
              child: Text(bank,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700))),
          if (_mode == 'demo')
            _chip(tr('Demo'), AppColors.warning)
          else
            _chip(tr('Aktiv'), AppColors.positive),
        ]),
        const SizedBox(height: 12),
        if (accounts.isEmpty)
          Text(tr('Wird beim nächsten Aktualisieren geladen'),
              style: TextStyle(color: AppColors.textDim, fontSize: 13))
        else
          for (final a in accounts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(child: Text(tr(a.name))),
                Text(Money.format(MoneyAccounts.balanceOf(a, tx)),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
            ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => _disconnectExtra(state, bank),
            style: TextButton.styleFrom(foregroundColor: AppColors.errorText),
            child: Text(tr('Trennen')),
          ),
        ),
      ]),
    );
  }

  Future<void> _disconnectExtra(String state, String bank) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$bank trennen?'),
        content: Text(
            tr('Freigabe weg. Umsätze und Konten dieser Bank verschwinden.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('Abbrechen'))),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text(tr('Trennen')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await BackendService.disconnect(state);
    } catch (_) {
      // forget it locally even when the server is offline
    }
    await AccountIsolation.deleteBankRowsForLink(state);
    await Settings.removeExtraBank(state);
    if (mounted) setState(() {});
    _snack('$bank getrennt');
  }

  Widget _firstBankCard() {
    if (AccountService.current.value == null) return _needsAccountCard();
    if (_pendingState != null) return _waitingCard();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _iconTile(Icons.account_balance_rounded, AppColors.primary),
            const SizedBox(width: 14),
            Expanded(
              child: Text(tr('Bankkonto verbinden'),
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
            if (_mode == 'demo') _chip(tr('Demo'), AppColors.warning),
          ]),
          const SizedBox(height: 16),
          _point(Icons.visibility_rounded,
              tr('Nur lesen, keine Überweisung')),
          _point(Icons.lock_rounded,
              tr('Login bei der Bank. Ahead sieht nichts.')),
          _point(Icons.link_off_rounded,
              tr('Trennbar, Freigabe bis 180 Tage')),
          _point(Icons.account_balance_wallet_outlined,
              tr('Auch Trade Republic: Guthaben, Karte, Zinsen')),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50)),
              onPressed: _mode == null ? null : _connectBank,
              child: Text(tr('Bank auswählen')),
            ),
          ),
        ],
      ),
    );
  }

  // bank/depot links require a signed-in account
  Widget _needsAccountCard({bool depot = false}) {
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _iconTile(
              depot ? Icons.show_chart_rounded : Icons.account_balance_rounded,
              depot ? AppColors.primary : AppColors.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Text(depot ? tr('Depot verbinden') : tr('Bankkonto verbinden'),
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 12),
        Text(
            tr('Dafür ein kostenloses Konto. Deine {x} bleibt nur für dich.', {'x': depot ? tr('Depotverbindung') : tr('Bankverbindung')}),
            style:
                TextStyle(color: AppColors.textDim, fontSize: 14, height: 1.4)),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SignUpScreen()));
              if (mounted) setState(() {});
            },
            child: Text(tr('Konto erstellen')),
          ),
        ),
      ]),
    );
  }

  Widget _waitingCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            InstrumentAvatar(_pendingBank ?? '?', size: 44),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_pendingBank ?? '',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(tr('Warte auf deine Freigabe …'),
                      style: TextStyle(color: AppColors.textDim, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
          const SizedBox(height: 14),
          Text(
              tr('Im Fenster bei der Bank anmelden. Danach hier weiter. Nach 10 Minuten bricht es ab.'),
              style: TextStyle(
                  color: AppColors.textDim, fontSize: 13, height: 1.35)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: FilledButton(
                style: _secondary,
                onPressed: () {
                  _cancelPending();
                  _snack(
                      tr('Verbinden abgebrochen. Du kannst es jederzeit noch einmal versuchen.'));
                },
                child: Text(tr('Abbrechen')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                style: _secondary,
                onPressed: _pendingLink == null
                    ? null
                    : () => launchUrl(Uri.parse(_pendingLink!),
                        mode: LaunchMode.externalApplication),
                child: Text(tr('Erneut öffnen')),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _linkedCard() {
    final name = Settings.bankName;
    final until = Settings.bankValidUntil;
    final expired = until != null && until.isBefore(DateTime.now());
    final expiresSoon = !expired &&
        until != null &&
        until.difference(DateTime.now()).inDays < 14;
    final last = Settings.lastSync;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            InstrumentAvatar(name, size: 44),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(_maskIban(Settings.bankIban),
                      style: TextStyle(
                          color: AppColors.textDim,
                          fontSize: 13,
                          letterSpacing: 0.5)),
                ],
              ),
            ),
            // a demo bank never passes for a real one, not even once linked
            if (_mode == 'demo')
              _chip(tr('Demo'), AppColors.warning)
            else if (expired)
              _chip(tr('Abgelaufen'), AppColors.error)
            else
              _chip(expiresSoon ? tr('Läuft ab') : tr('Aktiv'),
                  expiresSoon ? AppColors.warning : AppColors.positive),
          ]),
          const SizedBox(height: 20),
          Text(tr('Kontostand'),
              style: TextStyle(color: AppColors.textDim, fontSize: 13)),
          const SizedBox(height: 2),
          Text(Money.format(Settings.bankBalanceCents),
              style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5)),
          const SizedBox(height: 4),
          Text(
            [
              last == null
                  ? tr('Noch nicht aktualisiert')
                  : tr('Aktualisiert {x}', {'x': _ago(last)}),
              if (until != null)
                tr('Freigabe bis {x} {year}', {'x': Dates.dayMonth(until), 'year': until.year}),
            ].join(' · '),
            style: TextStyle(
                color: expiresSoon ? AppColors.warningText : AppColors.textDim,
                fontSize: 13),
          ),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _syncing ? null : _sync,
                icon: _syncing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.sync_rounded, size: 18),
                label: Text(_syncing ? tr('Aktualisiere …') : tr('Aktualisieren')),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: _syncing ? null : _disconnect,
              style: _secondary.copyWith(
                  foregroundColor: WidgetStatePropertyAll(AppColors.error)),
              child: Text(tr('Trennen')),
            ),
          ]),
          if (expired || expiresSoon) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: expired
                  ? FilledButton.icon(
                      onPressed: _connectBank,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(tr('Freigabe erneuern')),
                    )
                  : TextButton(
                      onPressed: _connectBank,
                      child: Text(tr('Freigabe erneuern'))),
            ),
          ],
        ],
      ),
    );
  }

  // --- depot card ---

  // the first depot, every further one, and a way to add another
  Widget _depotCard() {
    final extras = Settings.extraDepots;
    if (Settings.depotState.isEmpty && extras.isEmpty) return _firstDepotCard();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (Settings.depotState.isNotEmpty)
        _depotLinkedCard()
      else
        _firstDepotCard(),
      for (final l in extras) ...[
        const SizedBox(height: 12),
        _extraDepotCard(l.state, l.broker)
      ],
      const SizedBox(height: 12),
      if (_depotPending != null && _addingDepot)
        _depotWaitingCard()
      else if (Settings.depotState.isNotEmpty)
        OutlinedButton.icon(
          style:
              OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: () => _connectDepot(extra: true),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(tr('Weiteres Depot verbinden')),
        ),
    ]);
  }

  // a depot linked through a further Parqet login
  Widget _extraDepotCard(String state, String broker) {
    final prefix = DepotSync.linkPrefix(state);
    final positions =
        DB.getHoldings().where((h) => h.id.startsWith(prefix)).toList();
    final value = positions.fold<int>(0, (s, h) => s + h.valueCents);
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          InstrumentAvatar(broker.isEmpty ? tr('Parqet') : broker, size: 44),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(broker.isEmpty ? tr('Depot') : broker,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                  tr('über Parqet · {positions} {x}', {'positions': positions.length, 'x': positions.length == 1 ? tr('Position') : tr('Positionen')}),
                  style: TextStyle(color: AppColors.textDim, fontSize: 13)),
            ]),
          ),
          Text(Money.format(value),
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () =>
                _disconnectExtraDepot(state, broker.isEmpty ? tr('Depot') : broker),
            style: TextButton.styleFrom(foregroundColor: AppColors.errorText),
            child: Text(tr('Trennen')),
          ),
        ),
      ]),
    );
  }

  Future<void> _disconnectExtraDepot(String state, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$name trennen?'),
        content: Text(
            tr('Ahead liest es nicht mehr. Positionen bleiben, bis du sie löschst.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('Abbrechen'))),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text(tr('Trennen')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await BackendService.depotDisconnect(state);
    } catch (_) {
      // forget it locally even when the server is offline
    }
    await Settings.setExtraDepots([
      for (final l in Settings.extraDepots)
        if (l.state != state) l
    ]);
    if (mounted) setState(() {});
    _snack('$name getrennt');
  }

  Widget _firstDepotCard() {
    if (Settings.depotState.isNotEmpty) return _depotLinkedCard();
    if (AccountService.current.value == null)
      return _needsAccountCard(depot: true);
    if (_depotPending != null) return _depotWaitingCard();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _iconTile(Icons.show_chart_rounded, AppColors.primary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Depot verbinden'),
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(tr('Trade Republic, Scalable, ING und mehr'),
                        style:
                            TextStyle(color: AppColors.textDim, fontSize: 13)),
                  ]),
            ),
            if (_depotMode == 'demo') _chip(tr('Demo'), AppColors.warning),
          ]),
          const SizedBox(height: 16),
          // brokers like Trade Republic have no open interface; Parqet syncs them
          // and passes the depot on with the user's consent
          _step(1, tr('Verbinde dein Depot einmal mit Parqet'),
              tr('Kostenlos, Parqet hält es aktuell')),
          _step(2, tr('Gib es hier für Ahead frei'),
              tr('Nur lesen. Zugangsdaten sieht Ahead nie.')),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50)),
              onPressed:
                  _depotMode == null || _depotBusy ? null : _connectDepot,
              child: Text(tr('Mit Parqet verbinden')),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: TextButton(
              onPressed: () => launchUrl(Uri.parse('https://parqet.com'),
                  mode: LaunchMode.externalApplication),
              child: Text(tr('Noch kein Parqet? Hier kostenlos anlegen')),
            ),
          ),
          Text(
              tr('Ohne Parqet: CSV bei Trade Republic, dann Profil → Import → Depot.'),
              style: TextStyle(
                  color: AppColors.textDim, fontSize: 12.5, height: 1.4)),
        ],
      ),
    );
  }

  Widget _step(int n, String title, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle),
            child: Text('$n',
                style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 1),
              Text(text,
                  style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
            ]),
          ),
        ]),
      );

  Widget _depotWaitingCard() {
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _iconTile(Icons.show_chart_rounded, AppColors.primary),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Parqet'),
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(tr('Warte auf deine Freigabe …'),
                  style: TextStyle(color: AppColors.textDim, fontSize: 13)),
            ]),
          ),
          const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
        const SizedBox(height: 14),
        Text(
            tr('Bei Parqet anmelden, Zugriff erlauben. Danach hier weiter. Nach 10 Minuten bricht es ab.'),
            style: TextStyle(
                color: AppColors.textDim, fontSize: 13, height: 1.35)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: FilledButton(
              style: _secondary,
              onPressed: () {
                _cancelDepot();
                _snack(
                    tr('Verbinden abgebrochen. Du kannst es jederzeit noch einmal versuchen.'));
              },
              child: Text(tr('Abbrechen')),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              style: _secondary,
              onPressed: _depotLink == null
                  ? null
                  : () => launchUrl(Uri.parse(_depotLink!),
                      mode: LaunchMode.externalApplication),
              child: Text(tr('Erneut öffnen')),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _depotLinkedCard() {
    final synced = DB
        .getHoldings()
        .where((h) => h.id.startsWith(DepotSync.prefix))
        .toList();
    final value = synced.fold<int>(0, (s, h) => s + h.valueCents);
    final last = Settings.depotSync;
    final broker = Settings.depotBroker;
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          InstrumentAvatar(broker.isEmpty ? tr('Parqet') : broker, size: 44),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(broker.isEmpty ? tr('Depot') : broker,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(
                  tr('über Parqet · {synced} {x}', {'synced': synced.length, 'x': synced.length == 1 ? tr('Position') : tr('Positionen')}),
                  style: TextStyle(color: AppColors.textDim, fontSize: 13)),
            ]),
          ),
          _depotMode == 'demo'
              ? _chip(tr('Demo'), AppColors.warning)
              : _chip(tr('Aktiv'), AppColors.positive),
        ]),
        const SizedBox(height: 20),
        Text(tr('Depotwert'),
            style: TextStyle(color: AppColors.textDim, fontSize: 13)),
        const SizedBox(height: 2),
        Text(Money.format(value),
            style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5)),
        const SizedBox(height: 4),
        Text(
            last == null
                ? tr('Noch nicht aktualisiert')
                : tr('Aktualisiert {x}', {'x': _ago(last)}),
            style: TextStyle(color: AppColors.textDim, fontSize: 13)),
        const SizedBox(height: 10),
        // Parqet gathers all brokers in one place, so one link brings every depot
        Text(
            tr('Weitere Depots in Parqet. Beim nächsten Sync erscheinen sie hier.'),
            style:
                TextStyle(color: AppColors.textDim, fontSize: 13, height: 1.4)),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _depotBusy ? null : _syncDepot,
              icon: _depotBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync_rounded, size: 18),
              label: Text(_depotBusy ? tr('Aktualisiere …') : tr('Aktualisieren')),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: _depotBusy ? null : _disconnectDepot,
            style: _secondary.copyWith(
                foregroundColor: WidgetStatePropertyAll(AppColors.error)),
            child: Text(tr('Trennen')),
          ),
        ]),
      ]),
    );
  }

  Widget _offlineBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.wifi_off_rounded,
              size: 18, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
                tr('Kein Server. Verbinden geht gerade nicht.'),
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                    color: AppColors.warningText)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
            tr('Erfassen und CSV-Import gehen weiter.'),
            style: TextStyle(
                color: AppColors.textDim, fontSize: 13, height: 1.35)),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ProfileScreen())),
            child: Text(tr('Zum Import')),
          ),
        ),
      ]),
    );
  }

  // --- server status ---

  Widget _serverStatus() {
    final ok = _mode != null;
    final color = _checking
        ? AppColors.textDim
        : (ok ? AppColors.positive : AppColors.warning);
    // plain words for users; which parts run as a demo matters only for testing
    final text = _checking
        ? tr('Verbindung wird geprüft …')
        : !ok
            ? tr('Gerade nicht erreichbar · Erneut versuchen')
            : _mode == 'demo' && _depotMode == 'demo'
                ? tr('Demo: Beispielbank und -depot, keine echten Daten')
                : _mode == 'demo' || _depotMode == 'demo'
                    ? tr('Verbunden · {x} im Demo-Modus', {'x': _mode == 'demo' ? tr('Bank') : tr('Depot')})
                    : tr('Sicher verbunden');
    return Column(
      children: [
        Semantics(
          button: true,
          label: tr('Verbindung erneut prüfen'),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _check,
            child: ConstrainedBox(
              // a full-size tap target, not just the tiny icon
              constraints: const BoxConstraints(minHeight: 44),
              child:
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Flexible(
                    child: Text(text,
                        style:
                            TextStyle(color: AppColors.textDim, fontSize: 12))),
                const SizedBox(width: 6),
                Icon(Icons.refresh_rounded, size: 14, color: AppColors.textDim),
              ]),
            ),
          ),
        ),
        // a developer running the server locally; users never see this
        if (kDebugMode && !_checking && !ok) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(14)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Starte den Ahead-Server auf deinem Rechner:'),
                  style: TextStyle(color: AppColors.textDim, fontSize: 12)),
              const SizedBox(height: 8),
              const SelectableText('cd backend && dart run server.dart',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 13)),
            ]),
          ),
        ],
      ],
    );
  }

  // --- small pieces ---

  // the server's reasons are German already; anything technical is a connection problem
  static String _friendly(Object e) {
    final text = '$e';
    return RegExp(r'Exception|Error|Failed|Socket|Timeout|XMLHttpRequest')
            .hasMatch(text)
        ? tr('Gerade keine Verbindung. Bitte versuch es gleich noch einmal.')
        : text;
  }

  ButtonStyle get _secondary => FilledButton.styleFrom(
      backgroundColor: AppColors.surfaceAlt, foregroundColor: AppColors.text);

  Widget _iconTile(IconData icon, Color color) => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 22),
      );

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(999)),
        child: Text(text,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      );

  Widget _point(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ]),
      );

  static String _maskIban(String iban) {
    final s = iban.replaceAll(' ', '');
    if (s.length < 8) return tr('Girokonto');
    return '${s.substring(0, 4)} •••• ${s.substring(s.length - 4)}';
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return tr('gerade eben');
    if (d.inMinutes < 60) return tr('vor {inMinutes} Min.', {'inMinutes': d.inMinutes});
    if (d.inHours < 24) return tr('vor {inHours} Std.', {'inHours': d.inHours});
    return tr('am {x}', {'x': Dates.dayMonth(t)});
  }

  // --- bank flow ---

  Future<void> _connectBank({bool extra = false}) async {
    _addingBank = extra;
    try {
      final banks = await BackendService.institutions();
      if (!mounted) return;
      final bank = await showModalBottomSheet<Bank>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.surface,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => _BankPicker(banks),
      );
      if (bank == null) return;

      final link = await BackendService.connect(bank.id);
      if (!mounted) return;
      setState(() {
        _pendingState = link.state;
        _pendingBank = bank.name;
        _pendingLink = link.link;
      });
      await launchUrl(Uri.parse(link.link),
          mode: LaunchMode.externalApplication);
      _startPolling();
    } catch (e) {
      _snack(_friendly(e), error: true);
    }
  }

  void _startPolling() {
    _poll?.cancel();
    final started = DateTime.now();
    _poll = Timer.periodic(const Duration(seconds: 2), (timer) async {
      final state = _pendingState;
      if (state == null) {
        timer.cancel();
        return;
      }
      // no approval after ten minutes: stop waiting instead of spinning forever
      if (DateTime.now().difference(started).inMinutes >= 10) {
        timer.cancel();
        if (mounted) {
          _cancelPending();
          _snack(
              tr('Keine Freigabe von der Bank erhalten. Du kannst es jederzeit noch einmal versuchen.'));
        }
        return;
      }
      try {
        final link = await BackendService.status(state);
        if (link.status == 'linked') {
          timer.cancel();
          await _linked(state, link);
        } else if (link.status == 'failed' || link.status == 'unknown') {
          timer.cancel();
          _cancelPending();
          _snack(
              link.status == 'failed'
                  ? tr('Nicht verbunden: {error}', {'error': link.error})
                  : tr('Verbindung abgelaufen'),
              error: true);
        }
      } catch (_) {
        // a hiccup while polling; the next tick tries again
      }
    });
  }

  Future<void> _linked(String state, BankLink link) async {
    HapticFeedback.mediumImpact();
    if (_addingBank) {
      // a further bank: its accounts come in next to the ones already there
      await Settings.addExtraBank(state, link.bank ?? _pendingBank ?? tr('Bank'));
      if (!mounted) return;
      setState(() => _pendingState = null);
      return _sync(first: true);
    }
    await Settings.setBankState(state);
    await Settings.setBankOwner(AccountService.current.value?.id ?? '');
    await Settings.setBankInfo(
        name: link.bank ?? _pendingBank ?? tr('Bank'),
        iban: link.iban,
        validUntil: link.validUntil);
    if (!mounted) return;
    setState(() => _pendingState = null);
    await _sync(first: true);
  }

  void _cancelPending() {
    _poll?.cancel();
    if (mounted) {
      setState(() {
        _pendingState = null;
        _pendingLink = null;
        _pendingBank = null;
      });
    }
  }

  Future<void> _sync({bool first = false}) async {
    setState(() => _syncing = true);
    BankSync.holdSmile(true);
    try {
      final claimed = BankSync.claimSmile(await BankSync.run());
      if (first) {
        if (mounted) await _firstBankInsight(claimed.added, claimed.smarter);
      } else {
        if (claimed.smarter > 0) HapticFeedback.lightImpact();
        _snack(BankSync.syncedLine(
            added: claimed.added, smarter: claimed.smarter));
      }
    } catch (e) {
      _snack(tr('Aktualisieren hat nicht geklappt. {x}', {'x': _friendly(e)}), error: true);
    } finally {
      BankSync.holdSmile(false);
      if (mounted) setState(() => _syncing = false);
    }
  }

  // hand off to Start's habit number instead of leaving the user on Connections
  Future<void> _firstBankInsight(int added, int smarter) async {
    final name =
        _addingBank ? (_pendingBank ?? Settings.bankName) : Settings.bankName;
    if (!mounted) return;
    if (smarter > 0) HapticFeedback.lightImpact();
    final go = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$name verbunden'),
        content: Text(
          (added == 0
                  ? tr('Umsätze da. Auf dem Start siehst du, was noch frei ist.')
                  : tr('{added} {x} da. Buddy rechnet auf dem Start, was noch frei ist.', {'added': added, 'x': added == 1 ? tr('Umsatz') : tr('Umsätze')})) +
              (smarter > 0
                  ? '\n\n${BankSync.syncedLine(added: 0, smarter: smarter)}.'
                  : '') +
              tr('\n\nAbos und Miete unter Verträge.'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, 'stay'),
              child: Text(tr('Hier bleiben'))),
          TextButton(
              onPressed: () => Navigator.pop(context, 'contracts'),
              child: Text(tr('Verträge'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, 'start'),
              child: Text(tr('Zum Start'))),
        ],
      ),
    );
    if (!mounted) return;
    if (go == 'start') {
      Navigator.popUntil(context, (r) => r.isFirst);
    } else if (go == 'contracts') {
      Navigator.popUntil(context, (r) => r.isFirst);
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => const ContractsScreen()));
    }
  }

  Future<void> _disconnect() async {
    final extras = Settings.extraBanks;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${Settings.bankName} trennen?'),
        content: Text(extras.isEmpty
            ? tr('Freigabe weg. Übernommene Umsätze verschwinden.')
            : tr('Freigabe weg. Die andere Bank und ihre Umsätze bleiben.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('Abbrechen'))),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text(tr('Trennen')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final name = Settings.bankName;
    final state = Settings.bankState;
    try {
      await BackendService.disconnect(state);
    } catch (_) {
      // forget it locally even when the server is offline
    }
    // further banks stay linked; drop this bank's rows, then promote the first extra
    if (extras.isEmpty) {
      final target = Settings.bankBalanceCents;
      for (final t in DB
          .getTx()
          .where((t) => t.id.startsWith(BankSync.prefix))
          .toList()) {
        await DB.deleteTx(t.id);
      }
      await Settings.clearBank();
      // keep Kontostand ≈ last bank figure (manual bookings stay)
      await Settings.setOpeningBalanceCents(
          target - DB.balanceOf(DB.getTx()));
    } else {
      await AccountIsolation.deleteBankRowsForLink(state, includeMain: true);
      await Settings.clearBank();
      final first = extras.first;
      await Settings.setBankState(first.state);
      await Settings.setBankInfo(name: first.bank);
      await Settings.setBankOwner(AccountService.current.value?.id ?? '');
      for (final l in extras.skip(1)) {
        await Settings.addExtraBank(l.state, l.bank);
      }
    }
    if (mounted) setState(() {});
    _snack('$name getrennt');
  }

  // --- depot flow ---

  Future<void> _connectDepot({bool extra = false}) async {
    _addingDepot = extra;
    try {
      final link = await BackendService.depotConnect();
      if (!mounted) return;
      setState(() {
        _depotPending = link.state;
        _depotLink = link.link;
      });
      await launchUrl(Uri.parse(link.link),
          mode: LaunchMode.externalApplication);
      _depotPoll?.cancel();
      final started = DateTime.now();
      _depotPoll = Timer.periodic(const Duration(seconds: 2), (timer) async {
        final state = _depotPending;
        if (state == null) {
          timer.cancel();
          return;
        }
        if (DateTime.now().difference(started).inMinutes >= 10) {
          timer.cancel();
          if (mounted) {
            _cancelDepot();
            _snack(
                tr('Keine Freigabe vom Depot erhalten. Du kannst es jederzeit noch einmal versuchen.'));
          }
          return;
        }
        try {
          final s = await BackendService.depotStatus(state);
          if (s.status == 'linked') {
            timer.cancel();
            HapticFeedback.mediumImpact();
            if (_addingDepot) {
              await Settings.setExtraDepots(
                  [...Settings.extraDepots, (state: state, broker: '')]);
            } else {
              await Settings.setDepot(state);
            }
            await Settings.setDepotOwner(
                AccountService.current.value?.id ?? '');
            if (mounted) setState(() => _depotPending = null);
            await _syncDepot(first: true);
          } else if (s.status == 'failed' || s.status == 'unknown') {
            timer.cancel();
            _cancelDepot();
            _snack(
                s.status == 'failed'
                    ? tr('Nicht verbunden: {error}', {'error': s.error})
                    : tr('Verbindung abgelaufen'),
                error: true);
          }
        } catch (_) {
          // a hiccup while polling; the next tick tries again
        }
      });
    } catch (e) {
      _snack(_friendly(e), error: true);
    }
  }

  void _cancelDepot() {
    _depotPoll?.cancel();
    if (mounted) {
      setState(() {
        _depotPending = null;
        _depotLink = null;
        _addingDepot = false;
      });
    }
  }

  Future<void> _syncDepot({bool first = false}) async {
    setState(() => _depotBusy = true);
    try {
      final count = await DepotSync.run();
      _snack(first
          ? tr('Depot verbunden · {count} {x} übernommen', {'count': count, 'x': count == 1 ? tr('Position') : tr('Positionen')})
          : tr('Depot aktualisiert'));
    } catch (e) {
      _snack(tr('Aktualisieren hat nicht geklappt. {x}', {'x': _friendly(e)}), error: true);
    } finally {
      if (mounted) setState(() => _depotBusy = false);
    }
  }

  Future<void> _disconnectDepot() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Depot trennen?')),
        content: Text(
            tr('Depot-Zugriff weg. Positionen bleiben, bis du sie löschst. In Parqet unter Integrationen trennen.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('Abbrechen'))),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text(tr('Trennen')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await BackendService.depotDisconnect(Settings.depotState);
    } catch (_) {
      // forget it locally even when the server is offline
    }
    // further depots stay linked; promote the first so sync still has a primary
    final extras = Settings.extraDepots;
    await Settings.clearPrimaryDepot();
    if (extras.isNotEmpty) {
      final first = extras.first;
      await Settings.setDepot(first.state, broker: first.broker);
      await Settings.setDepotOwner(AccountService.current.value?.id ?? '');
      await Settings.setExtraDepots(extras.skip(1).toList());
    } else {
      await Settings.clearDepot();
    }
    if (mounted) setState(() {});
    _snack(tr('Depot getrennt'));
  }
}

// searchable list of banks, ranked so "ING" is not Recklinghausen
class _BankPicker extends StatefulWidget {
  final List<Bank> banks;
  const _BankPicker(this.banks);

  @override
  State<_BankPicker> createState() => _BankPickerState();
}

class _BankPickerState extends State<_BankPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final filtered = BankSearch.filter(widget.banks, _q);
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(tr('Bank auswählen'),
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                    hintText: tr('z. B. ING, DKB, Sparkasse Köln'),
                    prefixIcon: Icon(Icons.search_rounded)),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                          _q.trim().isEmpty
                              ? tr('Keine Banken geladen')
                              : tr('Keine Bank zu „{x}“ gefunden. Versuch einen anderen Namen.', {'x': _q.trim()}),
                          style: TextStyle(color: AppColors.textDim)))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final b = filtered[i];
                        final subtitle = b.group != null &&
                                b.group!.isNotEmpty &&
                                b.group!.toLowerCase() != b.name.toLowerCase()
                            ? b.group
                            : null;
                        return ListTile(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          leading: _logo(b),
                          title: Text(b.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: subtitle == null
                              ? null
                              : Text(subtitle,
                                  style: TextStyle(
                                      color: AppColors.textDim, fontSize: 12.5)),
                          trailing: Icon(Icons.chevron_right_rounded,
                              color: AppColors.textDim),
                          onTap: () => Navigator.pop(context, b),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _logo(Bank b) {
    final fallback = InstrumentAvatar(b.name, size: 38);
    if (b.logo == null) return fallback;
    return ClipOval(
      child: Container(
        width: 38,
        height: 38,
        color: Colors.white,
        padding: const EdgeInsets.all(5),
        child: Image.network(b.logo!,
            fit: BoxFit.contain, errorBuilder: (_, __, ___) => fallback),
      ),
    );
  }
}
