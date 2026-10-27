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

  group('BankSync.merge with several accounts', () {
    BankTransaction on(String acc, String id, int cents, String party, [int day = 1]) =>
        BankTransaction(id, DateTime(2026, 10, day), cents, party, '', acc);
    const giro = BankAccountInfo('g', 'Girokonto', 'DE1', 150000);
    const tg = BankAccountInfo('t', 'Tagesgeld', 'DE2', 520000);

    test('each bank account gets its own balance; a move between them is an Umbuchung', () {
      final r = BankSync.merge(
        existing: const [],
        incoming: [
          on('g', '1', -2350, 'REWE'),
          on('g', '2', -20000, 'Max Mustermann', 2),
          on('t', '3', 20000, 'Max Mustermann', 2),
          on('t', '4', 1250, 'Demo-Bank', 2),
        ],
        bankBalanceCents: 670000,
        accounts: const [giro, tg],
        link: 'L1',
        bankName: 'ING',
      );
      // the first account is the main one, the second its own account
      expect(r.added.where((t) => t.accountId == null).length, 2);
      expect(r.added.where((t) => t.accountId == 'bank_t').length, 2);
      final saving = r.accounts.single;
      expect(saving.name, 'Tagesgeld');
      expect(saving.kind, 'spar');
      expect(saving.link, 'L1');
      // 5.200 € today = start + 200 € moved in + 12,50 € interest
      expect(saving.openingCents, 520000 - 21250);
      expect(r.openingBalanceCents, 150000 - (-2350 - 20000));
      // the move is not spending
      expect(r.added.where((t) => t.amountCents == 20000).every((t) => t.category == 'Umbuchung'), isTrue);
      expect(r.added.firstWhere((t) => t.id == 'bank_1').category, isNot('Umbuchung'));
    });

    test('bookings synced before onto the main account move to their account, keeping the category', () {
      final old = Transaction(
          id: 'bank_3', amountCents: 20000, category: 'Sparen', date: DateTime(2026, 10, 2), isIncome: true);
      final r = BankSync.merge(
        existing: [old],
        incoming: [on('t', '3', 20000, 'Max Mustermann', 2)],
        bankBalanceCents: 670000,
        accounts: const [giro, tg],
        link: 'L1',
      );
      expect(r.added, isEmpty);
      expect(r.moved.single.accountId, 'bank_t');
      expect(r.moved.single.category, 'Sparen');
    });

    test('a second bank books on its own accounts and leaves the main one alone', () {
      final r = BankSync.merge(
        existing: const [],
        incoming: [on('x', '9', -1500, 'Bäcker')],
        bankBalanceCents: 30000,
        accounts: const [BankAccountInfo('x', 'Girokonto', 'DE3', 30000)],
        link: 'L2',
        primary: false,
        bankName: 'DKB',
      );
      expect(r.touchesMain, isFalse);
      expect(r.added.single.accountId, 'bank_x');
      expect(r.accounts.single.name, 'DKB Girokonto');
      expect(r.accounts.single.openingCents, 30000 + 1500);
    });
  });
}
