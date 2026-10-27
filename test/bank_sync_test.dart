import 'package:flutter_test/flutter_test.dart';
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/backend_service.dart';
import 'package:budget_buddy/services/bank_sync.dart';
import 'package:budget_buddy/services/categorizer.dart';

BankTransaction _b(String id, int cents, String party, [String purpose = '']) =>
    BankTransaction(id, DateTime(2026, 10, 1), cents, party, purpose);

void main() {
  group('Categorizer', () {
    test('recognizes common German merchants', () {
      expect(Categorizer.guess('REWE Markt GmbH', isIncome: false), 'Lebensmittel');
      expect(Categorizer.guess('Lieferando.de Bestellung', isIncome: false), 'Essen & Trinken');
      expect(Categorizer.guess('DB Vertrieb GmbH', isIncome: false), 'Transport');
      expect(Categorizer.guess('Netflix International B.V.', isIncome: false), 'Unterhaltung');
      expect(Categorizer.guess('Hausverwaltung Becker Miete', isIncome: false), 'Wohnen');
      expect(Categorizer.guess('Gehalt 10/2026', isIncome: true), 'Gehalt');
    });

    test('keywords only match at the start of a word', () {
      // "esso" must not be found inside "Espresso"
      expect(Categorizer.guess('Espresso Bar', isIncome: false), 'Sonstiges');
      expect(Categorizer.guess('ESSO Station', isIncome: false), 'Transport');
    });

    test('unknown bookings fall back to Sonstiges', () {
      expect(Categorizer.guess('Max Mustermann', isIncome: false), 'Sonstiges');
      expect(Categorizer.guess('Rückzahlung', isIncome: true), 'Sonstiges');
    });
  });

  group('BankSync.merge', () {
    test('a deleted booking stays deleted, a CSV-imported one is not doubled', () {
      final csv = Transaction(
          id: 'csv_x', amountCents: 2350, category: 'Lebensmittel', date: DateTime(2026, 10, 1), isIncome: false);
      final r = BankSync.merge(
        existing: [csv],
        incoming: [_b('gone', -999, 'Kiosk'), _b('dup', -2350, 'REWE'), _b('new', -100, 'Bäcker')],
        bankBalanceCents: 0,
        dismissed: {'bank_gone'},
      );
      expect(r.added.map((t) => t.id), ['bank_new']);
    });

    test('adds new bookings with a stable id, sign and category', () {
      final r = BankSync.merge(
        existing: const [],
        incoming: [_b('1', -2350, 'REWE Markt GmbH'), _b('2', 250000, 'Musterfirma GmbH', 'Gehalt')],
        bankBalanceCents: 100000,
      );
      expect(r.added.map((t) => t.id), ['bank_1', 'bank_2']);
      expect(r.added[0].isIncome, isFalse);
      expect(r.added[0].amountCents, 2350);
      expect(r.added[0].category, 'Lebensmittel');
      expect(r.added[0].note, 'REWE Markt GmbH');
      expect(r.added[1].category, 'Gehalt');
    });

    test('never duplicates or overwrites a known booking', () {
      final edited = Transaction(
          id: 'bank_1', amountCents: 2350, category: 'Geschenk', date: DateTime(2026, 10, 1), isIncome: false);
      final r = BankSync.merge(existing: [edited], incoming: [_b('1', -2350, 'REWE')], bankBalanceCents: 0);
      expect(r.added, isEmpty);
    });

    test('remembers the category the user gave a counterparty', () {
      final mine = Transaction(
        id: 'bank_old',
        amountCents: 1500,
        category: 'Bildung',
        date: DateTime(2026, 9, 1),
        isIncome: false,
        note: 'Max Mustermann',
      );
      final r = BankSync.merge(existing: [mine], incoming: [_b('new', -1500, 'Max Mustermann')], bankBalanceCents: 0);
      expect(r.added.single.category, 'Bildung');
    });

    test('opening balance makes the app balance equal the bank balance', () {
      final manual = Transaction(
          id: 'cash', amountCents: 1000, category: 'Sonstiges', date: DateTime(2026, 9, 1), isIncome: false);
      final r = BankSync.merge(
        existing: [manual],
        incoming: [_b('1', 50000, 'Musterfirma'), _b('2', -2000, 'REWE')],
        bankBalanceCents: 120000,
      );
      // -1000 + 50000 - 2000 = 47000 booked, so 73000 must come before
      expect(r.openingBalanceCents, 73000);
    });

    test('uses the purpose when the counterparty is missing', () {
      final r = BankSync.merge(existing: const [], incoming: [_b('1', -500, '', 'Kartenzahlung')], bankBalanceCents: 0);
      expect(r.added.single.note, 'Kartenzahlung');
    });
  });
}
