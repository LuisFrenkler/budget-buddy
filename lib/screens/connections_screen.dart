import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/transaction.dart';
import '../models/holding.dart';
import '../services/backend_service.dart';
import '../services/db.dart';
import '../services/settings_service.dart';
import '../utils/theme.dart';

// Links a real bank account (GoCardless/PSD2) and depot (Parqet) through the
// local backend. See backend/server.dart and backend/README.md.
class ConnectionsScreen extends StatefulWidget {
  const ConnectionsScreen({super.key});

  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  bool _checking = true;
  bool _backendUp = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final up = await BackendService.isUp();
    if (mounted) {
      setState(() {
        _backendUp = up;
        _checking = false;
      });
    }
  }

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? AppColors.error : AppColors.primary,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final linked = Settings.gcRequisitionId.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Verbindungen')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _backendBanner(),
          const SizedBox(height: 24),

          _sectionLabel('Bankkonto (GoCardless / PSD2)'),
          if (!linked)
            _actionTile(Icons.account_balance, 'Bank verbinden', _connectBank)
          else ...[
            _actionTile(Icons.download, 'Umsätze importieren', _importBank),
            const SizedBox(height: 8),
            _actionTile(Icons.link_off, 'Verbindung trennen', _disconnectBank, danger: true),
          ],
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(
              'Du wirst sicher zu deiner Bank weitergeleitet. Nach dem Login hier auf "Umsätze importieren" tippen.',
              style: TextStyle(fontSize: 12, color: AppColors.textDim),
            ),
          ),

          const SizedBox(height: 24),
          _sectionLabel('Depot (Parqet)'),
          _actionTile(Icons.trending_up, 'Parqet-Depot laden', _loadParqet),
        ],
      ),
    );
  }

  Widget _backendBanner() {
    if (_checking) {
      return const ListTile(
        leading: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        title: Text('Verbinde mit Server...'),
      );
    }
    final ok = _backendUp;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (ok ? AppColors.primary : AppColors.warning).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        Icon(ok ? Icons.check_circle : Icons.error_outline,
            color: ok ? AppColors.primary : AppColors.warning),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            ok
                ? 'Server verbunden (${BackendService.base})'
                : 'Kein Server unter ${BackendService.base}. Starte ihn mit: dart run backend/server.dart',
            style: const TextStyle(fontSize: 13),
          ),
        ),
        IconButton(onPressed: _check, icon: const Icon(Icons.refresh, size: 20)),
      ]),
    );
  }

  Widget _sectionLabel(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Text(t,
            style: TextStyle(
                color: AppColors.textDim, fontSize: 13, fontWeight: FontWeight.bold)),
      );

  Widget _actionTile(IconData icon, String title, VoidCallback onTap, {bool danger = false}) {
    final color = danger ? AppColors.error : AppColors.primary;
    return Container(
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(title),
        trailing: _busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(Icons.chevron_right, color: AppColors.textDim),
        onTap: _busy ? null : onTap,
      ),
    );
  }

  // --- bank flow ---

  Future<void> _connectBank() async {
    if (!_backendUp) return _snack('Server nicht erreichbar', error: true);
    setState(() => _busy = true);
    try {
      final banks = await BackendService.institutions();
      if (!mounted) return;
      final bank = await showModalBottomSheet<Bank>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => _BankPicker(banks),
      );
      if (bank == null) return;

      final req = await BackendService.createRequisition(bank.id, 'http://localhost:8123');
      await Settings.setGcRequisitionId(req.requisitionId);
      await launchUrl(Uri.parse(req.link), mode: LaunchMode.externalApplication);
      if (mounted) {
        setState(() {});
        _snack('Bei der Bank anmelden, dann "Umsätze importieren"');
      }
    } catch (e) {
      _snack('Fehler: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importBank() async {
    setState(() => _busy = true);
    try {
      final txs = await BackendService.transactions(Settings.gcRequisitionId);
      for (final t in txs) {
        // stable id so re-importing the same transaction doesn't duplicate it
        final id = 'bank_${t.date.millisecondsSinceEpoch}_${t.amountCents}_${t.description.hashCode}';
        await DB.addTx(Transaction(
          id: id,
          amountCents: t.amountCents.abs(),
          category: 'Sonstiges',
          date: t.date,
          isIncome: t.amountCents >= 0,
          note: t.description.isEmpty ? null : t.description,
        ));
      }
      await DB.checkBadges();
      _snack('${txs.length} Umsätze importiert');
    } catch (e) {
      _snack('Fehler: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnectBank() async {
    await Settings.setGcRequisitionId('');
    if (mounted) setState(() {});
    _snack('Bankverbindung getrennt');
  }

  // --- depot flow ---

  Future<void> _loadParqet() async {
    if (!_backendUp) return _snack('Server nicht erreichbar', error: true);
    setState(() => _busy = true);
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
      _snack('Fehler: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
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
    final filtered = _q.isEmpty
        ? widget.banks
        : widget.banks.where((b) => b.name.toLowerCase().contains(_q.toLowerCase())).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(
                color: AppColors.border, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _q = v),
                decoration: const InputDecoration(
                    hintText: 'Bank suchen...', prefixIcon: Icon(Icons.search)),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final b in filtered)
                    ListTile(
                      leading: const Icon(Icons.account_balance, color: AppColors.primary),
                      title: Text(b.name),
                      onTap: () => Navigator.pop(context, b),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
