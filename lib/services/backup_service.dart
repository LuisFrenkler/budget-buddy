// Export and backup/restore of the user's data.
//
// CSV export is round-trip compatible with CsvImporter (same column layout
// and dot-decimal amounts). JSON backup captures all three Hive boxes so the
// user never loses their data when switching or resetting a device.
import 'dart:convert';
import 'package:hive/hive.dart';
import '../models/transaction.dart';

class BackupService {
  // --- CSV export (transactions only) ---

  // builds a CSV string: Datum;Kategorie;Beschreibung;Betrag
  // income is a positive amount, expense a negative one (as the importer expects)
  static String transactionsToCsv(List<Transaction> txs) {
    final buf = StringBuffer('Datum;Kategorie;Beschreibung;Betrag\n');
    for (final t in txs) {
      final day = t.date.day.toString().padLeft(2, '0');
      final month = t.date.month.toString().padLeft(2, '0');
      final date = '$day.$month.${t.date.year}';

      final signedCents = t.isIncome ? t.amountCents : -t.amountCents;
      final amount = (signedCents / 100).toStringAsFixed(2);

      // keep the CSV well-formed: a note must not contain the ; separator or newlines
      final note = (t.note ?? '').replaceAll(';', ',').replaceAll('\n', ' ');

      buf.writeln('$date;${t.category};$note;$amount');
    }
    return buf.toString();
  }

  // --- JSON backup / restore (all boxes) ---

  // settings that change what the money adds up to; device things (theme,
  // app lock, bank link) stay on the device
  static const settingKeys = [
    'openingBalanceCents', 'balanceSet', 'categoryRules', 'budgetsStopped', 'cancellations', 'contractsHidden',
    // the accounts besides the main one, and the main one's name
    'moneyAccounts', 'mainAccount',
    // wealth bridge + vorsorge + profile picture (vault / JSON backup)
    'wealthDebts', 'wealthPolicies', 'emergencyExtraCents', 'vorsorge', 'avatarBytes',
  ];

  // serializes every box into a single pretty-printed JSON document
  static String toBackupJson() {
    final settings = Hive.box('settings');
    final data = {
      'version': 1,
      'transactions': _boxMaps('transactions'),
      'budgets': _boxMaps('budgets'),
      'badges': _boxMaps('badges'),
      'holdings': _boxMaps('holdings'),
      'recurring': _boxMaps('recurring'),
      'goals': _boxMaps('goals'),
      'splits': _boxMaps('splits'),
      'settings': {for (final k in settingKeys) if (settings.containsKey(k)) k: settings.get(k)},
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  static List<Map<String, dynamic>> _boxMaps(String name) {
    return Hive.box(name)
        .values
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  // restores a backup, REPLACING all current data. Throws on anything that
  // is not a BudgetBuddy backup, before a single record is touched.
  static Future<void> restoreFromJson(String json) async {
    final data = jsonDecode(json);
    if (data is! Map || data['version'] != 1 || data['transactions'] is! List) {
      throw const FormatException('Keine BudgetBuddy-Sicherung');
    }
    // build everything first, then replace box by box
    final boxes = {
      'transactions': _entries('transactions', data['transactions'], (m) => '${m['id']}'),
      'budgets': _entries('budgets', data['budgets'], (m) => '${m['category']}_${m['startDate']}'),
      'badges': _entries('badges', data['badges'], (m) => '${m['id']}'),
      'holdings': _entries('holdings', data['holdings'], (m) => '${m['id']}'),
      'recurring': _entries('recurring', data['recurring'], (m) => '${m['id']}'),
      // older backups had no goals/splits — still clear so another session cannot stick
      'goals': data['goals'] is List ? _entries('goals', data['goals'], (m) => '${m['id']}') : <String, Map<String, dynamic>>{},
      'splits': data['splits'] is List ? _entries('splits', data['splits'], (m) => '${m['id']}') : <String, Map<String, dynamic>>{},
    };
    for (final e in boxes.entries) {
      if (!Hive.isBoxOpen(e.key)) continue;
      final box = Hive.box(e.key);
      await box.clear();
      for (final me in e.value.entries) {
        await _hivePut(box, me.key, me.value);
      }
    }
    await Hive.box('settings').delete('bankDismissed');
    // every money setting must match the backup: missing keys are cleared so
    // a leftover opening balance or extra account cannot stick around
    final settings = data['settings'];
    final box = Hive.box('settings');
    for (final k in settingKeys) {
      if (settings is Map && settings.containsKey(k)) {
        await _hivePut(box, k, settings[k]);
      } else {
        await box.delete(k);
      }
    }
  }

  // Hive web crashes on null / odd JS types — JSON round-trip keeps only safe values
  static dynamic stripNulls(dynamic value) {
    if (value == null) return null;
    try {
      return jsonDecode(jsonEncode(value));
    } catch (_) {
      return null;
    }
  }

  static Future<void> _hivePut(Box box, dynamic key, dynamic value) async {
    final clean = stripNulls(value);
    if (clean == null) {
      await box.delete(key);
      return;
    }
    await box.put(key, clean);
  }

  static Map<String, Map<String, dynamic>> _entries(String name, dynamic list, String Function(Map) keyOf) {
    final out = <String, Map<String, dynamic>>{};
    if (list is! List) return out;
    for (int i = 0; i < list.length; i++) {
      try {
        final m = Map<String, dynamic>.from(list[i] as Map);
        var key = keyOf(m);
        // never collapse records onto a missing/duplicate key (data loss)
        if (key.isEmpty || key.contains('null') || out.containsKey(key)) key = '${name}_$i';
        final clean = stripNulls(m);
        if (clean is! Map) continue;
        out[key] = Map<String, dynamic>.from(clean);
      } catch (_) {}
    }
    return out;
  }
}
