import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../screens/add_screen.dart';
import '../screens/transaction_screen.dart';
import '../utils/dates.dart';
import '../utils/money.dart';
import '../utils/theme.dart';
import 'big_number.dart';

// One calm transaction row: description as title, category and day below,
// the amount on the right (income green, expenses in the normal text color).
class TxRow extends StatelessWidget {
  final Transaction tx;
  final VoidCallback? onTap;
  // off in lists that are already grouped by day
  final bool showDay;

  const TxRow(this.tx, {super.key, this.onTap, this.showDay = true});

  @override
  Widget build(BuildContext context) {
    final note = tx.note?.trim() ?? '';
    final title = note.isNotEmpty ? note : tx.category;
    final day = Dates.relativeDay(tx.date);
    final subtitle = !showDay ? tx.category : note.isNotEmpty ? '${tx.category} · $day' : day;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap ??
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => TransactionScreen(id: tx.id))),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            CategoryAvatar(tx.category, isIncome: tx.isIncome, merchant: tx.note),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(fontSize: 13, color: AppColors.textDim),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              tx.amountText,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: tx.isIncome ? AppColors.positive : AppColors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // opens the add/edit screen; returns true when something was saved
  static Future<bool> openEditor(BuildContext context, {Transaction? tx}) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => AddScreen(tx: tx)));
    return saved == true;
  }
}

// Bottom sheet listing a set of transactions, e.g. one category in a month.
// Used to drill down from charts and budgets.
Future<void> showTransactionsSheet(BuildContext context,
    {required String title, String? subtitle, required List<Transaction> tx}) {
  int total = 0;
  for (final t in tx) {
    total += t.isIncome ? t.amountCents : -t.amountCents;
  }
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('${subtitle != null ? '$subtitle · ' : ''}${tx.length} ${tx.length == 1 ? 'Umsatz' : 'Umsätze'} · ${Money.signed(total)}',
              style: TextStyle(color: AppColors.textDim)),
          const SizedBox(height: 12),
          if (tx.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(child: Text('Keine Umsätze', style: TextStyle(color: AppColors.textDim))),
            ),
          for (final t in tx) TxRow(t),
        ],
      ),
    ),
  );
}
