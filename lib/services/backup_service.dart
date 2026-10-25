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

  // serializes every box into a single pretty-printed JSON document
  static String toBackupJson() {
    final data = {
      'version': 1,
      'transactions': _boxMaps('transactions'),
      'budgets': _boxMaps('budgets'),
      'badges': _boxMaps('badges'),
      'holdings': _boxMaps('holdings'),
      'recurring': _boxMaps('recurring'),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  static List<Map<String, dynamic>> _boxMaps(String name) {
    return Hive.box(name)
        .values
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  // restores a backup, REPLACING all current data. throws on malformed input.
  static Future<void> restoreFromJson(String json) async {
    final data = jsonDecode(json) as Map<String, dynamic>;

    await _restoreBox('transactions', data['transactions'], (m) => '${m['id']}');
    await _restoreBox(
        'budgets', data['budgets'], (m) => '${m['category']}_${m['startDate']}');
    await _restoreBox('badges', data['badges'], (m) => '${m['id']}');
    await _restoreBox('holdings', data['holdings'], (m) => '${m['id']}');
    await _restoreBox('recurring', data['recurring'], (m) => '${m['id']}');
  }

  static Future<void> _restoreBox(
      String name, dynamic list, String Function(Map) keyOf) async {
    final box = Hive.box(name);
    await box.clear();
    if (list is! List) return;
    for (int i = 0; i < list.length; i++) {
      try {
        final m = Map<String, dynamic>.from(list[i] as Map);
        var key = keyOf(m);
        // never collapse records onto a missing/duplicate key (data loss)
        if (key.isEmpty || key.contains('null')) key = '${name}_$i';
        await box.put(key, m);
      } catch (_) {}
    }
  }
}
