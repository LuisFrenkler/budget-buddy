// Moves money between the user's own accounts, e.g. to the savings account.
// It is booked twice as "Umbuchung": out of one account and into the other,
// so both balances are right and nothing counts as spending or income.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../models/money_account.dart';
import '../models/transaction.dart';
import '../services/db.dart';
import '../services/money_accounts.dart';
import '../utils/money.dart';
import '../utils/theme.dart';

// the two bookings of one transfer; [from] and [to] are account ids
List<Transaction> transferBookings({
  required MoneyAccount from,
  required MoneyAccount to,
  required int cents,
  required DateTime date,
}) {
  final id = const Uuid().v4();
  String? acc(MoneyAccount a) => a.isMain ? null : a.id;
  return [
    Transaction(
        id: '${id}_out', amountCents: cents, category: Categories.transfer, date: date, isIncome: false,
        note: 'Umbuchung an ${to.name}', accountId: acc(from)),
    Transaction(
        id: '${id}_in', amountCents: cents, category: Categories.transfer, date: date, isIncome: true,
        note: 'Umbuchung von ${from.name}', accountId: acc(to)),
  ];
}

Future<void> showTransferSheet(BuildContext context) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    builder: (_) => const _TransferSheet(),
  );
  if (ok == true && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(duration: Duration(milliseconds: 2800), content: Text('Umgebucht')));
  }
}

class _TransferSheet extends StatefulWidget {
  const _TransferSheet();

  @override
  State<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<_TransferSheet> {
  final _amount = TextEditingController();
  final _accounts = MoneyAccounts.all;
  late MoneyAccount _from = _accounts.first;
  // to a savings account by default, the usual move
  late MoneyAccount _to = _accounts.firstWhere((a) => a.kind == 'spar' && a.id != _from.id,
      orElse: () => _accounts.firstWhere((a) => a.id != _from.id));
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final cents = Money.parseToCents(_amount.text);
    if (cents == null || cents <= 0) return setState(() => _error = 'Bitte einen Betrag eingeben, z. B. 200');
    if (_from.id == _to.id) return setState(() => _error = 'Wähle zwei verschiedene Konten');
    for (final t in transferBookings(from: _from, to: _to, cents: cents, date: DateTime.now())) {
      await DB.addTx(t);
    }
    HapticFeedback.mediumImpact();
    if (mounted) Navigator.pop(context, true);
  }

  Widget _picker(String label, MoneyAccount value, ValueChanged<MoneyAccount> onChanged) => DropdownButtonFormField<String>(
        initialValue: value.id,
        decoration: InputDecoration(labelText: label),
        items: [for (final a in _accounts) DropdownMenuItem(value: a.id, child: Text(a.name))],
        onChanged: (id) => onChanged(_accounts.firstWhere((a) => a.id == id)),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Geld verschieben', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text('Zwischen deinen eigenen Konten. Zählt nicht als Ausgabe.', style: TextStyle(color: AppColors.textDim)),
        const SizedBox(height: 16),
        _picker('Von', _from, (a) => setState(() => _from = a)),
        const SizedBox(height: 12),
        _picker('Nach', _to, (a) => setState(() => _to = a)),
        const SizedBox(height: 12),
        TextField(
          controller: _amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onSubmitted: (_) => _save(),
          decoration: InputDecoration(labelText: 'Betrag', suffixText: '€', errorText: _error),
        ),
        const SizedBox(height: 18),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: _save,
          child: const Text('Umbuchen'),
        ),
      ]),
    );
  }
}
