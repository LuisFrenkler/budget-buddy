import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/transaction.dart';
import '../services/bank_sync.dart';
import '../services/booking_text.dart';
import '../services/db.dart';
import '../services/split_service.dart';
import 'splits_screen.dart';
import '../services/category_rules.dart';
import '../services/settings_service.dart';
import '../utils/dates.dart';
import '../utils/merchant.dart';
import '../utils/money.dart';
import '../utils/theme.dart';
import '../widgets/big_number.dart';
import '../widgets/tx_row.dart';
import '../l10n/l10n.dart';
import 'buddy_screen.dart';
import '../widgets/buddy_orb.dart';

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
        if (matches.isEmpty) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.receipt_long_rounded, size: 48, color: AppColors.textDim),
                  const SizedBox(height: 12),
                  Text(tr('Buchung gelöscht'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(tr('Diese Buchung gibt es hier nicht mehr.'),
                      textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim)),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(tr('Zurück')),
                  ),
                ]),
              ),
            ),
          );
        }
        final tx = matches.first;
        final fromBank = tx.id.startsWith(BankSync.prefix);
        final title = (tx.note?.trim().isNotEmpty ?? false)
            ? Merchant.present(tx.note, fallback: tx.category)
            : tx.category;

        return Scaffold(
          appBar: AppBar(
            // bank bookings would come back with the next sync
            actions: [
              if (!fromBank)
              IconButton(
                tooltip: tr('Löschen'),
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
                    color: tx.isIncome ? AppColors.positiveText : AppColors.text,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(Dates.long(tx.date), textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim)),
              const SizedBox(height: 28),
              _group([
                _row(
                  tr('Kategorie'),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Categories.icon(tx.category), size: 18, color: AppColors.textDim),
                    const SizedBox(width: 8),
                    Text(tr(tx.category), style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 2),
                    Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
                  ]),
                  onTap: () => _pickCategory(context, tx),
                ),
                _row(tr('Art'), Text(tx.isRefund ? tr('Erstattung') : (tx.isIncome ? tr('Einnahme') : tr('Ausgabe')),
                    style: const TextStyle(fontWeight: FontWeight.w600))),
                _row(
                  tr('Quelle'),
                  Text(fromBank ? tr('{x} · Girokonto', {'x': Settings.bankName.isEmpty ? tr('Bank') : Settings.bankName}) : tr('Manuell erfasst'),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ]),
              ..._explain(tx),
              ..._counterparty(context, tx, all),
              // ask Buddy about exactly this booking
              const SizedBox(height: 24),
              _askBuddy(context, tx),
              // an expense paid for others: split it in a group
              if (!tx.isIncome) ...[
                const SizedBox(height: 10),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    backgroundColor: AppColors.primary.withValues(alpha: 0.16),
                    foregroundColor: AppColors.primary,
                  ),
                  onPressed: () => shareTransaction(context, tx),
                  icon: Icon(SplitService.isShared(tx.id) ? Icons.check_rounded : Icons.call_split_rounded, size: 18),
                  label: Text(SplitService.isShared(tx.id) ? tr('Geteilt · noch einmal teilen') : tr('Mit anderen teilen')),
                ),
              ],
              if (!fromBank) ...[
                const SizedBox(height: 24),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    backgroundColor: AppColors.surfaceAlt,
                    foregroundColor: AppColors.text,
                  ),
                  onPressed: () async {
                    await TxRow.openEditor(context, tx: tx);
                    // deleted in the editor: this page has nothing left to show
                    if (context.mounted && !DB.getTx().any((t) => t.id == tx.id)) Navigator.pop(context);
                  },
                  child: Text(tr('Bearbeiten')),
                ),
              ] else ...[
                const SizedBox(height: 16),
                Text(tr('Betrag und Datum kommen von der Bank. Die Kategorie kannst du ändern, Ahead merkt sie sich.'),
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
        child: Text(tr('Bei {x}', {'x': tx.note!.trim()}),
            style: TextStyle(color: AppColors.textDim, fontSize: 13, fontWeight: FontWeight.bold)),
      ),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          _stat('${same.length}', same.length == 1 ? tr('Umsatz') : tr('Umsätze')),
          _stat(Money.format(total), tr('in 3 Monaten')),
          _stat(Money.format(total ~/ same.length), tr('im Schnitt')),
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
            builder: (_, hidden, __) => Text(hidden && value.contains('€') ? Money.hidden : value,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
        ]),
      );

  Future<void> _pickCategory(BuildContext context, Transaction tx) async {
    final list = tx.isIncome ? Categories.income.where((c) => !Categories.isExpenseOnly(c['name']!)).toList() : Categories.expense;
    // money coming in can also be a refund: then it belongs to what was bought
    final refunds = tx.isIncome ? Categories.expense.where((c) => Categories.isExpenseOnly(c['name']!)).toList() : const [];
    Widget chip(BuildContext context, Map<String, String> c) => ChoiceChip(
          selected: c['name'] == tx.category,
          showCheckmark: false,
          side: BorderSide(color: AppColors.border),
          selectedColor: Categories.color(c['name']!).withValues(alpha: 0.22),
          avatar: Icon(Categories.icon(c['name']!), size: 18, color: Categories.color(c['name']!)),
          label: Text(tr(c['name']!)),
          onSelected: (_) => Navigator.pop(context, c['name']),
        );
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('Kategorie'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [for (final c in list) chip(context, c)]),
            if (refunds.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(tr('Erstattung, z. B. eine Rücksendung'),
                  style: TextStyle(color: AppColors.textDim, fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              Text(tr('Zählt gegen die Ausgaben dieser Kategorie, nicht als Einnahme.'),
                  style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [for (final c in refunds) chip(context, c)]),
            ],
          ]),
        ),
      ),
    );
    if (picked == null || picked == tx.category) return;
    HapticFeedback.selectionClick();
    await DB.addTx(tx.withCategory(picked));
    final name = tx.note?.trim() ?? '';
    if (name.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(duration: const Duration(milliseconds: 2800), content: Text(tr('Kategorie: {picked}', {'picked': picked}))));
      }
      return;
    }
    final others = CategoryRules.others(tx, picked);
    if (others.isEmpty) {
      await CategoryRules.remember(name, picked, isIncome: tx.isIncome);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            duration: const Duration(milliseconds: 3200),
            content: Text(tr('Ahead merkt sich {name} als {picked}, auch bei Bank-Sync und Schnellerfassung.', {'name': name, 'picked': picked}))));
      }
      return;
    }
    if (!context.mounted) return;
    final all = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('$name → $picked merken?', style: const TextStyle(fontFamily: AppFonts.display, fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
                tr('{others} ältere {x} liegen noch woanders. Standard: merken und alle anpassen. Künftige {name}-Buchungen gehen zu {picked}.', {'others': others.length, 'x': others.length == 1 ? tr('Buchung steht') : tr('Buchungen stehen'), 'name': name, 'picked': picked}),
                style: TextStyle(color: AppColors.textDim, height: 1.4)),
            const SizedBox(height: 18),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('Merken & alle {x} ändern', {'x': others.length + 1})),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('Nur diese · künftige trotzdem {picked}', {'picked': picked})),
            ),
          ]),
        ),
      ),
    );
    if (all == true) {
      final moved = await CategoryRules.applyToAll(tx, picked);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            duration: const Duration(milliseconds: 3200),
            content: Text(tr('{name} merken · {x} {y} jetzt {picked}', {'name': name, 'x': moved + 1, 'y': moved + 1 == 1 ? tr('Buchung') : tr('Buchungen'), 'picked': picked}))));
      }
    } else {
      // dismissed sheet or "only this": still remember, that is the expected default
      await CategoryRules.remember(name, picked, isIncome: tx.isIncome);
      if (context.mounted) {
        final onlyThis = all == false;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            duration: const Duration(milliseconds: 3200),
            content: Text(onlyThis
                ? tr('Nur diese Buchung geändert · {name} merken wir uns als {picked}', {'name': name, 'picked': picked})
                : tr('{name} merken als {picked} · ältere Buchungen unverändert', {'name': name, 'picked': picked}))));
      }
    }
  }

  Future<void> _delete(BuildContext context, Transaction tx) async {
    HapticFeedback.mediumImpact();
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    await DB.deleteTx(tx.id);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(persist: false, duration: const Duration(seconds: 5), 
      content: Text(tr('Umsatz gelöscht')),
      action: SnackBarAction(label: tr('Rückgängig'), onPressed: () => DB.addTx(tx)),
    ));
  }

  // the bank's cryptic text in plain words
  List<Widget> _explain(Transaction tx) {
    final lines = BookingText.explain(raw: tx.raw, note: tx.note, income: tx.isIncome);
    if (lines.isEmpty) return const [];
    return [
      const SizedBox(height: 16),
      Semantics(
        container: true,
        child: Container(
          key: const Key('booking-explain'),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const BuddyOrb(size: 18),
              const SizedBox(width: 8),
              Text(tr('Was ist das?'), style: const TextStyle(fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 8),
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(l, style: TextStyle(color: AppColors.textDim, height: 1.4, fontSize: 13.5)),
              ),
            if (tx.raw != null && tx.raw!.trim().isNotEmpty)
              Text(tr('Text der Bank: {x}', {'x': tx.raw!.trim()}),
                  style: TextStyle(color: AppColors.textDim, fontSize: 11.5, height: 1.35)),
          ]),
        ),
      ),
    ];
  }

  // the question for Buddy that fits this booking
  static String buddyQuestion(Transaction tx) {
    final what = tx.note?.trim().isNotEmpty == true ? tx.note!.trim() : tr(tx.category);
    final amount = Money.format(tx.amountCents);
    if (tx.isIncome) {
      return tr('Ich habe {x} von {y} bekommen. Was mache ich am besten damit?', {'x': amount, 'y': what});
    }
    return tr('Ich habe am {d} {x} bei {y} ausgegeben. Wie passt das in meinen Monat, und kann ich mir das öfter leisten?',
        {'d': Dates.dayMonth(tx.date), 'x': amount, 'y': what});
  }

  Widget _askBuddy(BuildContext context, Transaction tx) => FilledButton.icon(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          backgroundColor: AppColors.surfaceAlt,
          foregroundColor: AppColors.text,
        ),
        onPressed: () {
          final q = buddyQuestion(tx);
          Navigator.of(context).popUntil((r) => r.isFirst);
          BuddyScreen.ask.value = q;
        },
        icon: const BuddyOrb(size: 20),
        label: Text(tx.isIncome ? tr('Ahead fragen, was ich damit mache') : tr('Kann ich mir das leisten?')),
      );
}
