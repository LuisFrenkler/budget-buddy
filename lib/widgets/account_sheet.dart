// Adds an account (a savings account, cash, a card at another bank) or
// changes one: name, kind, and for a hand-kept account today's balance.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../models/money_account.dart';
import '../screens/connections_screen.dart';
import '../services/db.dart';
import '../services/money_accounts.dart';
import '../utils/money.dart';
import '../utils/theme.dart';

// returns the saved account, or null when cancelled or deleted
Future<MoneyAccount?> showAccountSheet(BuildContext context, {MoneyAccount? account}) => showModalBottomSheet<MoneyAccount>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (_) => _AccountSheet(account),
    );

class _AccountSheet extends StatefulWidget {
  final MoneyAccount? account;
  const _AccountSheet(this.account);

  @override
  State<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<_AccountSheet> {
  late final _name = TextEditingController(text: widget.account?.name ?? '');
  late final _balance = TextEditingController();
  late String _kind = widget.account?.kind ?? 'spar';
  String? _error;

  bool get _isNew => widget.account == null;
  // a synced account takes its balance from the bank
  bool get _handKept => widget.account?.link == null;

  @override
  void initState() {
    super.initState();
    final a = widget.account;
    if (a != null && _handKept) {
      _balance.text = (MoneyAccounts.balanceOf(a, DB.getTx()) / 100).toStringAsFixed(2).replaceAll('.', ',');
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return setState(() => _error = 'Gib dem Konto einen Namen, z. B. Tagesgeld');
    final cents = _balance.text.trim().isEmpty ? 0 : Money.parseToCents(_balance.text);
    if (_handKept && cents == null) return setState(() => _error = 'Bitte einen Betrag eingeben, z. B. 1.250,40');
    final account = (widget.account ?? MoneyAccount(id: const Uuid().v4(), name: name)).copyWith(name: name, kind: _kind);
    await MoneyAccounts.save(account);
    if (_handKept) await MoneyAccounts.setBalance(account, cents!, DB.getTx());
    HapticFeedback.mediumImpact();
    if (mounted) Navigator.pop(context, account);
  }

  Future<void> _delete() async {
    final a = widget.account!;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${a.name} entfernen?'),
        content: const Text('Die Buchungen dieses Kontos wandern auf dein Hauptkonto. Es geht kein Umsatz verloren.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Entfernen'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    await MoneyAccounts.remove(a);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.account;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(_isNew ? 'Konto hinzufügen' : a!.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        // no dead end: an account at a bank is better linked than typed in
        if (_isNew)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: () {
                // the sheet's context is gone after the pop: keep the navigator
                final nav = Navigator.of(context);
                nav.pop();
                nav.push(MaterialPageRoute(builder: (_) => const ConnectionsScreen(start: 'bank')));
              },
              icon: const Icon(Icons.link_rounded, size: 18),
              label: const Text('Lieber mit der Bank verbinden'),
            ),
          ),
        if (a?.link != null) ...[
          const SizedBox(height: 6),
          Text('Wird über ${a!.bank ?? 'deine Bank'} abgeglichen.', style: TextStyle(color: AppColors.textDim)),
        ],
        const SizedBox(height: 16),
        Wrap(spacing: 8, children: [
          for (final e in MoneyAccount.kinds.entries)
            ChoiceChip(
              label: Text(e.value),
              selected: _kind == e.key,
              onSelected: (_) => setState(() => _kind = e.key),
            ),
        ]),
        const SizedBox(height: 14),
        TextField(
          controller: _name,
          autofocus: _isNew,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Name', hintText: 'z. B. Tagesgeld, Bargeld, DKB'),
        ),
        if (_handKept) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _balance,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            onSubmitted: (_) => _save(),
            decoration: const InputDecoration(labelText: 'Kontostand heute', suffixText: '€', hintText: '0,00'),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: AppColors.errorText)),
        ],
        const SizedBox(height: 18),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: _save,
          child: Text(_isNew ? 'Konto anlegen' : 'Speichern'),
        ),
        if (a != null && !a.isMain)
          TextButton(
            onPressed: _delete,
            style: TextButton.styleFrom(foregroundColor: AppColors.errorText),
            child: const Text('Konto entfernen'),
          ),
      ]),
    );
  }
}
