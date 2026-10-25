// Pure, testable CSV parsing for the import feature.
//
// Expected format (one transaction per line, header skipped):
//   Datum;Kategorie;Beschreibung;Betrag
//   05.01.2025;Gehalt;Lohn Januar;2850.00
//
// A positive amount is an income, a negative amount is an expense.
import 'package:uuid/uuid.dart';
import '../models/transaction.dart';
import '../utils/money.dart';
import '../utils/theme.dart';

// result of importing a whole CSV file
class ImportResult {
  final List<Transaction> transactions;
  final int skipped;
  const ImportResult(this.transactions, this.skipped);
}

class CsvImporter {
  static const _uuid = Uuid();

  // parse the full file content into transactions, counting skipped lines
  static ImportResult parse(String content) {
    final lines = content.split('\n');
    final transactions = <Transaction>[];
    int skipped = 0;

    // skip the first line (header)
    for (int i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue; // blank lines don't count as errors

      final tx = parseLine(line);
      if (tx != null) {
        transactions.add(tx);
      } else {
        skipped++;
      }
    }

    return ImportResult(transactions, skipped);
  }

  // parse a single line into a Transaction, or null if the line is invalid
  static Transaction? parseLine(String line) {
    if (line.isEmpty) return null;

    final parts = line.split(';');
    if (parts.length < 4) return null;

    try {
      // parse date (dd.MM.yyyy), normalized to midnight
      final dateParts = parts[0].trim().split('.');
      if (dateParts.length != 3) return null;
      final day = int.parse(dateParts[0]);
      final month = int.parse(dateParts[1]);
      final year = int.parse(dateParts[2]);
      final date = DateTime(year, month, day);

      // category must be one of the known categories
      final category = parts[1].trim();
      if (!Categories.all.contains(category)) return null;

      // parse amount into cents (sign decides income vs expense)
      final cents = Money.parseToCents(parts[3]);
      if (cents == null || cents == 0) return null;

      final note = parts[2].trim();

      return Transaction(
        id: _uuid.v4(),
        amountCents: cents.abs(),     // store as a positive amount
        category: category,
        date: date,
        isIncome: cents > 0,
        note: note.isNotEmpty ? note : null,
      );
    } catch (_) {
      return null;
    }
  }
}
