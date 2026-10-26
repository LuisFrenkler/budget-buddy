import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/holding.dart';
import '../services/account_service.dart';
import 'auth_screens.dart';
import '../services/backend_service.dart';
import '../services/bank_sync.dart';
import '../services/db.dart';
import '../services/settings_service.dart';
import '../utils/dates.dart';
import '../utils/money.dart';
import '../utils/theme.dart';
import '../widgets/instrument_avatar.dart';

// Links a real bank account (Enable Banking / PSD2) and a depot (Parqet)
// through the local backend. See backend/README.md.
//
// Linking a bank: pick it, log in on the bank's own page in the browser,
// and the app notices the granted access by itself (it polls the backend),
// then imports balance and bookings right away.
class ConnectionsScreen extends StatefulWidget {
  const ConnectionsScreen({super.key});

  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  bool _checking = true;
  // null = server not reachable, otherwise 'live' or 'demo'
  String? _mode;
  bool _syncing = false;
  bool _loadingDepot = false;

  // consent started in the browser and not finished yet
  String? _pendingState;
  String? _pendingBank;
  String? _pendingLink;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    final mode = await BackendService.bankMode();
    if (mounted) {
      setState(() {
        _mode = mode;
        _checking = false;
      });
    }
  }

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(duration: const Duration(milliseconds: 2800), 
      content: Text(text),
      backgroundColor: error ? AppColors.error : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verbindungen')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          Text('Kontostand, Umsätze und Depot automatisch aktuell, ohne Abtippen.',
              style: TextStyle(color: AppColors.textDim, fontSize: 15)),
          _label('Girokonto'),
          _bankCard(),
          _label('Depot'),
          _depotCard(),
          const SizedBox(height: 24),
          _serverStatus(),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 28, bottom: 10, left: 4),
        child: Text(text, style: TextStyle(color: AppColors.textDim, fontSize: 13, fontWeight: FontWeight.bold)),
      );

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20)),
        child: child,
      );

  // --- bank card ---

  Widget _bankCard() {
    if (Settings.bankState.isNotEmpty) return _linkedCard();
    if (AccountService.current.value == null) return _needsAccountCard();
    if (_pendingState != null) return _waitingCard();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _iconTile(Icons.account_balance_rounded, AppColors.primary),
            const SizedBox(width: 14),
            const Expanded(
              child: Text('Bankkonto verbinden', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
            if (_mode == 'demo') _chip('Demo', AppColors.warning),
          ]),
          const SizedBox(height: 16),
          _point(Icons.visibility_rounded, 'Nur Lesezugriff, Überweisungen sind nicht möglich'),
          _point(Icons.lock_rounded, 'Login direkt bei deiner Bank, BudgetBuddy sieht keine Zugangsdaten'),
          _point(Icons.link_off_rounded, 'Jederzeit trennbar, Freigabe gilt bis zu 180 Tage'),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: _mode == null ? null : _connectBank,
              child: const Text('Bank auswählen'),
            ),
          ),
        ],
      ),
    );
  }

  // bank links belong to an account, so guests sign up first
  Widget _needsAccountCard() {
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _iconTile(Icons.account_balance_rounded, AppColors.primary),
          const SizedBox(width: 14),
          const Expanded(
            child: Text('Bankkonto verbinden', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 12),
        Text('Dafür brauchst du ein kostenloses Konto. So bleibt deine Bankverbindung nur für dich sichtbar.',
            style: TextStyle(color: AppColors.textDim, fontSize: 14, height: 1.4)),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const SignUpScreen()));
              if (mounted) setState(() {});
            },
            child: const Text('Konto erstellen'),
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
                  Text(_pendingBank ?? '', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('Warte auf deine Freigabe …', style: TextStyle(color: AppColors.textDim, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
          const SizedBox(height: 14),
          Text('Melde dich im geöffneten Fenster bei deiner Bank an. Danach geht es hier automatisch weiter.',
              style: TextStyle(color: AppColors.textDim, fontSize: 13)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: FilledButton(style: _secondary, onPressed: _cancelPending, child: const Text('Abbrechen')),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                style: _secondary,
                onPressed: () => launchUrl(Uri.parse(_pendingLink!), mode: LaunchMode.externalApplication),
                child: const Text('Erneut öffnen'),
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
    final expiresSoon = until != null && until.difference(DateTime.now()).inDays < 14;
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
                  Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(_maskIban(Settings.bankIban),
                      style: TextStyle(color: AppColors.textDim, fontSize: 13, letterSpacing: 0.5)),
                ],
              ),
            ),
            _chip(expiresSoon ? 'Läuft ab' : 'Aktiv', expiresSoon ? AppColors.warning : AppColors.positive),
          ]),
          const SizedBox(height: 20),
          Text('Kontostand', style: TextStyle(color: AppColors.textDim, fontSize: 13)),
          const SizedBox(height: 2),
          Text(Money.format(Settings.bankBalanceCents),
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
          const SizedBox(height: 4),
          Text(
            [
              last == null ? 'Noch nicht aktualisiert' : 'Aktualisiert ${_ago(last)}',
              if (until != null) 'Freigabe bis ${Dates.dayMonth(until)} ${until.year}',
            ].join(' · '),
            style: TextStyle(color: expiresSoon ? AppColors.warning : AppColors.textDim, fontSize: 13),
          ),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _syncing ? null : _sync,
                icon: _syncing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.sync_rounded, size: 18),
                label: Text(_syncing ? 'Aktualisiere …' : 'Aktualisieren'),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: _syncing ? null : _disconnect,
              style: _secondary.copyWith(foregroundColor: WidgetStatePropertyAll(AppColors.error)),
              child: const Text('Trennen'),
            ),
          ]),
          if (expiresSoon) ...[
            const SizedBox(height: 10),
            Center(
              child: TextButton(onPressed: _connectBank, child: const Text('Freigabe erneuern')),
            ),
          ],
        ],
      ),
    );
  }

  // --- depot card ---

  Widget _depotCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _iconTile(Icons.show_chart_rounded, AppColors.accentBlue),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Parqet', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('Depots aller Broker an einem Ort', style: TextStyle(color: AppColors.textDim, fontSize: 13)),
                ],
              ),
            ),
            FilledButton(
              style: _secondary,
              onPressed: _mode == null || _loadingDepot ? null : _loadParqet,
              child: _loadingDepot
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Laden'),
            ),
          ]),
          const SizedBox(height: 14),
          Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 14),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline_rounded, size: 18, color: AppColors.textDim),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Trade Republic und Scalable bieten keine offene Schnittstelle. Exportiere dort deine Positionen '
                'und lade sie unter Profil → Depot importieren. Kurse aktualisiert die App danach selbst.',
                style: TextStyle(color: AppColors.textDim, fontSize: 13),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  // --- server status ---

  Widget _serverStatus() {
    final ok = _mode != null;
    final color = _checking ? AppColors.textDim : (ok ? AppColors.positive : AppColors.warning);
    final text = _checking
        ? 'Suche Server …'
        : !ok
            ? 'Server nicht erreichbar'
            : _mode == 'demo'
                ? 'Server verbunden · Demo-Bank, keine echten Daten'
                : 'Server verbunden · Enable Banking';
    return Column(
      children: [
        GestureDetector(
          onTap: _check,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Flexible(child: Text(text, style: TextStyle(color: AppColors.textDim, fontSize: 12))),
            const SizedBox(width: 6),
            Icon(Icons.refresh_rounded, size: 14, color: AppColors.textDim),
          ]),
        ),
        if (!_checking && !ok) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Starte den BudgetBuddy-Server auf deinem Rechner:',
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

  ButtonStyle get _secondary =>
      FilledButton.styleFrom(backgroundColor: AppColors.surfaceAlt, foregroundColor: AppColors.text);

  Widget _iconTile(IconData icon, Color color) => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 22),
      );

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
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
    if (s.length < 8) return 'Girokonto';
    return '${s.substring(0, 4)} •••• ${s.substring(s.length - 4)}';
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'gerade eben';
    if (d.inMinutes < 60) return 'vor ${d.inMinutes} Min.';
    if (d.inHours < 24) return 'vor ${d.inHours} Std.';
    return 'am ${Dates.dayMonth(t)}';
  }

  // --- bank flow ---

  Future<void> _connectBank() async {
    try {
      final banks = await BackendService.institutions();
      if (!mounted) return;
      final bank = await showModalBottomSheet<Bank>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.surface,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => _BankPicker(banks),
      );
      if (bank == null) return;

      final link = await BackendService.connect(bank.id);
      setState(() {
        _pendingState = link.state;
        _pendingBank = bank.name;
        _pendingLink = link.link;
      });
      await launchUrl(Uri.parse(link.link), mode: LaunchMode.externalApplication);
      _startPolling();
    } catch (e) {
      _snack('Fehler: $e', error: true);
    }
  }

  void _startPolling() {
    _poll?.cancel();
    final started = DateTime.now();
    _poll = Timer.periodic(const Duration(seconds: 2), (timer) async {
      final state = _pendingState;
      if (state == null || DateTime.now().difference(started).inMinutes >= 10) {
        timer.cancel();
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
          _snack(link.status == 'failed' ? 'Nicht verbunden: ${link.error}' : 'Verbindung abgelaufen', error: true);
        }
      } catch (_) {
        // a hiccup while polling; the next tick tries again
      }
    });
  }

  Future<void> _linked(String state, BankLink link) async {
    HapticFeedback.mediumImpact();
    await Settings.setBankState(state);
    await Settings.setBankOwner(AccountService.current.value?.id ?? '');
    await Settings.setBankInfo(name: link.bank ?? _pendingBank ?? 'Bank', iban: link.iban, validUntil: link.validUntil);
    if (!mounted) return;
    setState(() => _pendingState = null);
    await _sync(first: true);
  }

  void _cancelPending() {
    _poll?.cancel();
    if (mounted) setState(() => _pendingState = null);
  }

  Future<void> _sync({bool first = false}) async {
    setState(() => _syncing = true);
    try {
      final added = await BankSync.run();
      if (first) {
        _snack('${Settings.bankName} verbunden · $added ${added == 1 ? 'Umsatz' : 'Umsätze'} übernommen');
      } else {
        _snack(added == 0 ? 'Alles aktuell' : '$added neue ${added == 1 ? 'Buchung' : 'Buchungen'}');
      }
    } catch (e) {
      _snack('Aktualisieren fehlgeschlagen: $e', error: true);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _disconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${Settings.bankName} trennen?'),
        content: const Text('Die Freigabe wird widerrufen. Bereits übernommene Umsätze bleiben in der App.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Trennen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final name = Settings.bankName;
    try {
      await BackendService.disconnect(Settings.bankState);
    } catch (_) {
      // forget it locally even when the server is offline
    }
    await Settings.clearBank();
    if (mounted) setState(() {});
    _snack('$name getrennt');
  }

  // --- depot flow ---

  Future<void> _loadParqet() async {
    setState(() => _loadingDepot = true);
    try {
      final positions = await BackendService.parqetPortfolio();
      for (final p in positions) {
        final perShare = p.shares > 0 ? (p.valueCents / p.shares).round() : p.valueCents;
        await DB.addHolding(Holding(
          id: 'parqet_${p.name}', // stable so re-loading updates instead of duplicating
          name: p.name,
          symbol: '',
          type: 'Aktie',
          shares: p.shares,
          buyPriceCents: perShare,
          currentPriceCents: perShare,
        ));
      }
      _snack('${positions.length} Positionen aus Parqet geladen');
    } catch (e) {
      _snack('$e', error: true);
    } finally {
      if (mounted) setState(() => _loadingDepot = false);
    }
  }
}

// searchable list of banks
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
    final q = _q.toLowerCase().trim();
    final filtered = q.isEmpty ? widget.banks : widget.banks.where((b) => b.name.toLowerCase().contains(q)).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text('Bank auswählen', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: TextField(
                onChanged: (v) => setState(() => _q = v),
                decoration: const InputDecoration(hintText: 'Bank suchen', prefixIcon: Icon(Icons.search_rounded)),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(child: Text('Keine Bank gefunden', style: TextStyle(color: AppColors.textDim)))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final b = filtered[i];
                        return ListTile(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          leading: _logo(b),
                          title: Text(b.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          trailing: Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
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
        child: Image.network(b.logo!, fit: BoxFit.contain, errorBuilder: (_, __, ___) => fallback),
      ),
    );
  }
}
