import 'package:flutter_test/flutter_test.dart';
import 'package:budget_buddy/services/csv_importer.dart';

void main() {
  group('CsvImporter', () {
    test('parses valid lines and stores amounts in cents', () {
      const csv = 'Datum;Kategorie;Beschreibung;Betrag\n'
          '05.01.2025;Gehalt;Lohn Januar;2850.00\n'
          '08.01.2025;Lebensmittel;REWE Einkauf;-67.43\n';
      final result = CsvImporter.parse(csv);

      expect(result.transactions.length, 2);
      expect(result.skipped, 0);

      final gehalt = result.transactions[0];
      expect(gehalt.amountCents, 285000);
      expect(gehalt.isIncome, isTrue); // positive amount

      final rewe = result.transactions[1];
      expect(rewe.amountCents, 6743); // stored positive
      expect(rewe.isIncome, isFalse); // negative amount
      expect(rewe.note, 'REWE Einkauf');
    });

    test('normalizes dates to midnight', () {
      const csv = 'h\n05.03.2025;Gehalt;x;100.00\n';
      final tx = CsvImporter.parse(csv).transactions.single;
      expect(tx.date, DateTime(2025, 3, 5));
    });

    test('skips invalid lines and counts them', () {
      const csv = 'Datum;Kategorie;Beschreibung;Betrag\n'
          '05.01.2025;Gehalt;Lohn;2850.00\n'
          'too;few;fields\n' // only 3 fields
          '05.01.2025;NichtEineKategorie;x;-10.00\n' // unknown category
          'bad-date;Gehalt;x;10.00\n'; // unparseable date
      final result = CsvImporter.parse(csv);
      expect(result.transactions.length, 1);
      expect(result.skipped, 3);
    });

    test('blank lines do not count as skipped', () {
      const csv = 'h\n05.01.2025;Gehalt;Lohn;100.00\n\n   \n';
      final result = CsvImporter.parse(csv);
      expect(result.transactions.length, 1);
      expect(result.skipped, 0);
    });
  });

  test('importing the same file twice adds nothing the second time', () {
    const csv = 'Datum;Kategorie;Beschreibung;Betrag\n05.01.2025;Gehalt;Lohn;2850,00\n08.01.2025;Lebensmittel;REWE;-12,50\n';
    final first = CsvImporter.parse(csv);
    final again = CsvImporter.parse(csv, existing: first.transactions);
    expect(again.transactions, isEmpty);
    expect(again.duplicates, 2);
  });
}
