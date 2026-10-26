import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/transaction.dart';
import '../services/bank_sync.dart';
import '../services/db.dart';
import '../services/settings_service.dart';
import '../utils/dates.dart';
import '../utils/money.dart';
import '../utils/theme.dart';
import '../widgets/big_number.dart';
import '../widgets/tx_row.dart';

// Details of one booking: amount, date, category (changeable with one tap),
// where it came from, and how much went to the same counterparty lately.
// Bank bookings are fixed by the bank; only their category can change.
class TransactionScreen extends StatelessWidget {
  final String id;
  const TransactionScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box>(
      valueListenable: Hive.box('transactions').listenable(),
      builder: (context, _, __) {
        final all = DB.getTx();
        final matches = all.where((t) => t.id == id);
        // deleted meanwhile: nothing left to show
        if (matches.isEmpty) return Scaffold(appBar: AppBar());
        final tx = matches.first;
        final fromBank = tx.id.startsWith(BankSync.prefix);
        final title = (tx.note?.trim().isNotEmpty ?? false) ? tx.note!.trim() : tx.category;

        return Scaffold(
          appBar: AppBar(
            // bank bookings would come back with the next sync
            actions: [
              if (!fromBank)
              IconButton(
                tooltip: 'Löschen',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () => _delete(context, tx),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            children: [
              Center(child: CategoryAvatar(tx.category, isIncome: tx.isIncome, size: 64, merchant: tx.note)),
              const SizedBox(height: 14),
              Text(title,
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              ValueListenableBuilder<bool>(
                valueListenable: Settings.hideAmounts,
                builder: (_, hidden, __) => Text(
                  hidden ? Money.hidden : tx.amountText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1,
                    color: tx.isIncome ? AppColors.positive : AppColors.text,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(Dates.long(tx.date), textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim)),
              const SizedBox(height: 28),
              _group([
                _row(
                  'Kategorie',
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Categories.icon(tx.category), size: 18, color: AppColors.textDim),
                    const SizedBox(width: 8),
                    Text(tx.category, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 2),
                    Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
                  ]),
                  onTap: () => _pickCategory(context, tx),
                ),
                _row('Art', Text(tx.isIncome ? 'Einnahme' : 'Ausgabe', style: const TextStyle(fontWeight: FontWeight.w600))),
                _row(
                  'Quelle',
                  Text(fromBank ? '${Settings.bankName.isEmpty ? 'Bank' : Settings.bankName} · Girokonto' : 'Manuell erfasst',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ]),
              ..._counterparty(context, tx, all),
              if (!fromBank) ...[
                const SizedBox(height: 24),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    backgroundColor: AppColors.surfaceAlt,
                    foregroundColor: AppColors.text,
                  ),
                  onPressed: () => TxRow.openEditor(context, tx: tx),
                  child: const Text('Bearbeiten'),
                ),
              ] else ...[
                const SizedBox(height: 16),
                Text('Betrag und Datum kommen von deiner Bank. Die Kategorie kannst du jederzeit ändern, '
                    'BudgetBuddy merkt sie sich für künftige Buchungen.',
                    textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _group(List<Widget> rows) => Container(
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (int i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 16, color: AppColors.border),
            rows[i],
          ],
        ]),
      );

  Widget _row(String label, Widget value, {VoidCallback? onTap}) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 14, onTap != null ? 8 : 16, 14),
          child: Row(children: [
            Text(label, style: TextStyle(color: AppColors.textDim)),
            const Spacer(),
            value,
          ]),
        ),
      );

  // how much went to (or came from) the same counterparty in the last months
  List<Widget> _counterparty(BuildContext context, Transaction tx, List<Transaction> all) {
    final name = tx.note?.trim().toLowerCase() ?? '';
    if (name.isEmpty) return const [];
    final since = DateTime.now().subtract(const Duration(days: 92));
    final same = all
        .where((t) => t.isIncome == tx.isIncome && t.note?.trim().toLowerCase() == name && t.date.isAfter(since))
        .toList();
    if (same.length < 2) return const [];
    final total = same.fold<int>(0, (s, t) => s + t.amountCents);
    final others = same.where((t) => t.id != tx.id).take(4).toList();

    return [
      const SizedBox(height: 28),
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 10),
        child: Text('Bei ${tx.note!.trim()}',
            style: TextStyle(color: AppColors.textDim, fontSize: 13, fontWeight: FontWeight.bold)),
      ),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          _stat('${same.length}', same.length == 1 ? 'Umsatz' : 'Umsätze'),
          _stat(Money.format(total), 'in 3 Monaten'),
          _stat(Money.format(total ~/ same.length), 'im Schnitt'),
        ]),
      ),
      const SizedBox(height: 8),
      for (final t in others)
        TxRow(t,
            onTap: () => Navigator.pushReplacement(
                context, MaterialPageRoute(builder: (_) => TransactionScreen(id: t.id)))),
    ];
  }

  Widget _stat(String value, String label) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ValueListenableBuilder<bool>(
            valueListenable: Settings.hideAmounts,
            // counts stay visible, sums hide in privacy mode
            builder: (_, hidden, __) => Text(hidden && value.contains('€') ? '•••' : value,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
        ]),
      );

  Future<void> _pickCategory(BuildContext context, Transaction tx) async {
    final list = tx.isIncome ? Categories.income : Categories.expense;
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Kategorie', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in list)
                ChoiceChip(
                  selected: c['name'] == tx.category,
                  showCheckmark: false,
                  avatar: Icon(Categories.icon(c['name']!), size: 18),
                  label: Text(c['name']!),
                  onSelected: (_) => Navigator.pop(context, c['name']),
                ),
            ]),
          ]),
        ),
      ),
    );
    if (picked == null || picked == tx.category) return;
    HapticFeedback.selectionClick();
    await DB.addTx(Transaction(
      id: tx.id,
      amountCents: tx.amountCents,
      category: picked,
      date: tx.date,
      isIncome: tx.isIncome,
      note: tx.note,
    ));
  }

  Future<void> _delete(BuildContext context, Transaction tx) async {
    HapticFeedback.mediumImpact();
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    await DB.deleteTx(tx.id);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: const Text('Umsatz gelöscht'),
      action: SnackBarAction(label: 'Rückgängig', onPressed: () => DB.addTx(tx)),
    ));
  }
}
