// Importing files into a chosen account or depot: a bank's CSV export or
// BudgetBuddy's own CSV into an account, a positions CSV or a Trade Republic
// export into a depot. Shared by Profil, "+ Konto" and the Depot's +.
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/money_account.dart';
import '../models/transaction.dart';
import '../services/bank_csv_importer.dart';
import '../services/csv_importer.dart';
import '../services/db.dart';
import '../services/holdings_csv_importer.dart';
import '../services/money_accounts.dart';
import '../services/trade_republic_importer.dart';
import '../utils/errors.dart';
import '../utils/theme.dart';
import 'account_sheet.dart';
import '../l10n/l10n.dart';

void _snack(BuildContext context, String text, {bool error = false}) {
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
      duration: Duration(milliseconds: 3200),
      content: Text(text),
      backgroundColor: error ? AppColors.error : null));
}

// asks which account; [allowNew] also offers a new one, set up on the spot
Future<MoneyAccount?> pickAccount(BuildContext context, {String? title, bool allowNew = false}) async {
  final heading = title ?? tr('In welches Konto?');
  final accounts = MoneyAccounts.all;
  if (accounts.length == 1 && !allowNew) return accounts.single;
  const create = MoneyAccount(id: '_new', name: '');
  final picked = await showModalBottomSheet<MoneyAccount>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(heading, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ),
        for (final a in accounts)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: Icon(a.kind == 'spar' ? Icons.savings_rounded : Icons.account_balance_wallet_rounded,
                color: AppColors.primaryText),
            title: Text(a.name),
            subtitle: Text(MoneyAccount.kinds[a.kind]!),
            onTap: () => Navigator.pop(sheet, a),
          ),
        if (allowNew)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: Icon(Icons.add_rounded, color: AppColors.primaryText),
            title: Text(tr('Neues Konto')),
            subtitle: Text(tr('Sparkonto, Bargeld oder ein weiteres Girokonto')),
            onTap: () => Navigator.pop(sheet, create),
          ),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (picked?.id != create.id || !context.mounted) return picked;
  return showAccountSheet(context);
}

Future<String?> _pickText(List<String> extensions) async {
  final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: extensions, withData: true);
  final bytes = result?.files.firstOrNull?.bytes;
  if (bytes == null) return null;
  // banks export in Latin-1 as often as in UTF-8
  final text = utf8.decode(bytes, allowMalformed: true);
  return text.contains('�') ? latin1.decode(bytes) : text;
}

// the bookings of a file onto one account; the account keeps today's
// balance, the file only fills in what happened before
Future<void> importBookings(BuildContext context, {MoneyAccount? into}) async {
  final account = into ?? await pickAccount(context, title: tr('Umsätze in welches Konto?'), allowNew: true);
  if (account == null) return;
  final content = await _pickText(['csv', 'txt']);
  if (content == null) return;
  try {
    final before = DB.getTx();
    final balance = MoneyAccounts.balanceOf(account, before);
    final existing = MoneyAccounts.bookingsOf(account.id, before);
    final List<Transaction> txs;
    final String msg;
    if (BankCsvImporter.looksLikeBank(content)) {
      final r = BankCsvImporter.parse(content, existing: existing);
      txs = r.transactions;
      msg = [
        '${txs.length} ${txs.length == 1 ? 'Umsatz' : 'Umsätze'} in ${account.name}',
        if (r.duplicates > 0) tr('{duplicates} schon vorhanden', {'duplicates': r.duplicates}),
        if (r.skipped > 0) tr('{skipped} nicht lesbar', {'skipped': r.skipped}),
      ].join(' · ');
    } else {
      final r = CsvImporter.parse(content, existing: existing);
      txs = r.transactions;
      msg = [
        '${txs.length} ${txs.length == 1 ? 'Umsatz' : 'Umsätze'} in ${account.name}',
        if (r.duplicates > 0) tr('{duplicates} schon vorhanden', {'duplicates': r.duplicates}),
        if (r.skipped > 0) tr('{skipped} übersprungen', {'skipped': r.skipped}),
      ].join(' · ');
    }
    if (txs.isEmpty) {
      if (context.mounted) {
        _snack(context, tr('In dieser Datei wurden keine neuen Umsätze gefunden. Exportiere sie im Online-Banking als CSV.'));
      }
      return;
    }
    for (final t in txs) {
      await DB.addTx(t.onAccount(account.isMain ? null : account.id));
    }
    // a linked account gets its balance from the bank anyway
    if (account.link == null) await MoneyAccounts.setBalance(account, balance, DB.getTx());
    if (context.mounted) _snack(context, msg);
  } catch (e) {
    if (context.mounted) _snack(context, friendlyError(e, fallback: tr('Import hat nicht geklappt.')), error: true);
  }
}

// positions of a file into a depot (by name, as on the Depot tab)
Future<void> importDepot(BuildContext context, {String? depot}) async {
  final name = depot ?? await _pickDepotName(context);
  if (name == null) return;
  final content = await _pickText(['csv', 'txt']);
  if (content == null) return;
  try {
    // a Trade Republic export rebuilds the depot from its buys and sells
    final imported = TradeRepublicImporter.looksLikeTradeRepublic(content)
        ? TradeRepublicImporter.parse(content)
        : HoldingsCsvImporter.parse(content);
    for (final h in imported.holdings) {
      await DB.addHolding(h.inDepot(name.isEmpty ? null : name));
    }
    if (context.mounted) {
      _snack(
          context,
          tr('{holdings} {x}{x2} importiert{x3}', {'holdings': imported.holdings.length, 'x': imported.holdings.length == 1 ? tr('Position') : tr('Positionen'), 'x2': name.isEmpty ? '' : ' in $name', 'x3': imported.skipped > 0 ? tr(' · {skipped} übersprungen', {'skipped': imported.skipped}) : ''}));
    }
  } catch (e) {
    if (context.mounted) _snack(context, friendlyError(e, fallback: tr('Import hat nicht geklappt.')), error: true);
  }
}

// an existing depot or a new name; '' = none
Future<String?> _pickDepotName(BuildContext context) {
  final names = {for (final h in DB.getHoldings()) if (h.depot != null && h.depot!.isNotEmpty) h.depot!}.toList()..sort();
  final ctrl = TextEditingController();
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    builder: (sheet) => Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(sheet).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('In welches Depot?'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        for (final n in names)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.trending_up_rounded, color: AppColors.primaryText),
            title: Text(n),
            onTap: () => Navigator.pop(sheet, n),
          ),
        TextField(
          controller: ctrl,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: names.isEmpty ? tr('Depot') : tr('Neues Depot'), hintText: tr('z. B. Scalable')),
          onSubmitted: (v) => Navigator.pop(sheet, v.trim()),
        ),
        const SizedBox(height: 12),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          onPressed: () => Navigator.pop(sheet, ctrl.text.trim()),
          child: Text(tr('Datei wählen')),
        ),
      ]),
    ),
  ).whenComplete(ctrl.dispose);
}
