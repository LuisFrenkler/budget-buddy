import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/backend_service.dart';
import 'package:budget_buddy/services/bank_sync.dart';
import 'package:budget_buddy/services/categorizer.dart';
import 'package:budget_buddy/services/category_rules.dart';

BankTransaction _b(String id, int cents, String party,
        [String purpose = '', String mcc = '', String hint = '']) =>
    BankTransaction(
        id, DateTime(2026, 10, 1), cents, party, purpose, '', mcc, hint);

void main() {
  group('Categorizer', () {
    test('recognizes common German merchants', () {
      expect(Categorizer.guess('REWE Markt GmbH', isIncome: false),
          'Lebensmittel');
      expect(Categorizer.guess('Lieferando.de Bestellung', isIncome: false),
          'Essen & Trinken');
      expect(
          Categorizer.guess('DB Vertrieb GmbH', isIncome: false), 'Transport');
      expect(Categorizer.guess('Netflix International B.V.', isIncome: false),
          'Unterhaltung');
      expect(Categorizer.guess('Hausverwaltung Becker Miete', isIncome: false),
          'Wohnen');
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
      // no Shopping category: the marketplace waits for a correction
      expect(Categorizer.guess('AMZN Mktp DE', isIncome: false), 'Sonstiges');
      expect(Categorizer.guess('Shelly Cloud', isIncome: false), 'Sonstiges');
    });

    test('german bank spellings and rails', () {
      expect(Categorizer.guess('LIDL DIENSTLEISTUNG', isIncome: false),
          'Lebensmittel');
      expect(Categorizer.guess('dm-drogerie markt', isIncome: false),
          'Lebensmittel');
      expect(Categorizer.guess('PAYPAL *SPOTIFY', isIncome: false),
          'Unterhaltung');
      expect(
          Categorizer.guess('Amazon Prime', isIncome: false), 'Unterhaltung');
      expect(
          Categorizer.guess('DB FERNVERKEHR AG', isIncome: false), 'Transport');
      expect(Categorizer.guess('WWW.BAHN.DE', isIncome: false), 'Transport');
      expect(Categorizer.guess('SHELL DEUTSCHLAND GMBH', isIncome: false),
          'Transport');
      expect(Categorizer.guess('Kaltmiete Oktober', isIncome: false), 'Wohnen');
      expect(Categorizer.guess('Warmmiete', isIncome: false), 'Wohnen');
      expect(Categorizer.guess('Entgeltabrechnung 10/2026', isIncome: true),
          'Gehalt');
      expect(Categorizer.guess('Nettolohn', isIncome: true), 'Gehalt');
      expect(Categorizer.guess('BAECKEREI SCHULZ', isIncome: false),
          'Essen & Trinken');
      expect(Categorizer.guess('Mueller', isIncome: false, mcc: '5812'),
          'Essen & Trinken');
      expect(Categorizer.guess('REWE', isIncome: false, mcc: '5812'),
          'Lebensmittel');
      expect(Categorizer.brand('PAYPAL *AMZN Mktp'), 'amazon');
      expect(Categorizer.brand('DB Fernverkehr'), 'deutsche bahn');
    });
  });

  group('BankSync.merge', () {
    test('a deleted booking stays deleted, a CSV-imported one is not doubled',
        () {
      final csv = Transaction(
          id: 'csv_x',
          amountCents: 2350,
          category: 'Lebensmittel',
          date: DateTime(2026, 10, 1),
          isIncome: false);
      final r = BankSync.merge(
        existing: [csv],
        incoming: [
          _b('gone', -999, 'Kiosk'),
          _b('dup', -2350, 'REWE'),
          _b('new', -100, 'Bäcker')
        ],
        bankBalanceCents: 0,
        dismissed: {'bank_gone'},
      );
      expect(r.added.map((t) => t.id), ['bank_new']);
    });

    test('adds new bookings with a stable id, sign and category', () {
      final r = BankSync.merge(
        existing: const [],
        incoming: [
          _b('1', -2350, 'REWE Markt GmbH'),
          _b('2', 250000, 'Musterfirma GmbH', 'Gehalt')
        ],
        bankBalanceCents: 100000,
      );
      expect(r.added.map((t) => t.id), ['bank_1', 'bank_2']);
      expect(r.added[0].isIncome, isFalse);
      expect(r.added[0].amountCents, 2350);
      expect(r.added[0].category, 'Lebensmittel');
      expect(r.added[0].note, 'REWE Markt GmbH');
      expect(r.added[1].category, 'Gehalt');
      expect(r.smarter, 2);
    });

    test('never duplicates or overwrites a known booking', () {
      final edited = Transaction(
          id: 'bank_1',
          amountCents: 2350,
          category: 'Geschenk',
          date: DateTime(2026, 10, 1),
          isIncome: false);
      final r = BankSync.merge(
          existing: [edited],
          incoming: [_b('1', -2350, 'REWE')],
          bankBalanceCents: 0);
      expect(r.added, isEmpty);
    });

    test('bank id upgrade does not re-import a fingerprint booking', () {
      final finger = Transaction(
        id: 'bank_2026-10-01T00:00:00.000|-2350|REWE|',
        amountCents: 2350,
        category: 'Lebensmittel',
        date: DateTime(2026, 10, 1),
        isIncome: false,
        note: 'REWE',
      );
      final r = BankSync.merge(
        existing: [finger],
        incoming: [_b('EB-REAL-99', -2350, 'REWE')],
        bankBalanceCents: 0,
      );
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
      final r = BankSync.merge(
          existing: [mine],
          incoming: [_b('new', -1500, 'Max Mustermann')],
          bankBalanceCents: 0);
      expect(r.added.single.category, 'Bildung');
      expect(r.smarter, 0);
    });

    test('opening balance makes the app balance equal the bank balance', () {
      final manual = Transaction(
          id: 'cash',
          amountCents: 1000,
          category: 'Sonstiges',
          date: DateTime(2026, 9, 1),
          isIncome: false);
      final r = BankSync.merge(
        existing: [manual],
        incoming: [_b('1', 50000, 'Musterfirma'), _b('2', -2000, 'REWE')],
        bankBalanceCents: 120000,
      );
      // -1000 + 50000 - 2000 = 47000 booked, so 73000 must come before
      expect(r.openingBalanceCents, 73000);
    });

    test('uses the purpose when the counterparty is missing', () {
      final r = BankSync.merge(
          existing: const [],
          incoming: [_b('1', -500, '', 'Kartenzahlung')],
          bankBalanceCents: 0);
      expect(r.added.single.note, 'Kartenzahlung');
    });
  });

  group('BankSync.merge with several accounts', () {
    BankTransaction on(String acc, String id, int cents, String party,
            [int day = 1]) =>
        BankTransaction(id, DateTime(2026, 10, day), cents, party, '', acc);
    const giro = BankAccountInfo('g', 'Girokonto', 'DE1', 150000);
    const tg = BankAccountInfo('t', 'Tagesgeld', 'DE2', 520000);

    test('giro wins as main even when the bank lists savings first', () {
      final r = BankSync.merge(
        existing: const [],
        incoming: [on('t', '1', 100, 'Zinsen'), on('g', '2', -500, 'REWE')],
        bankBalanceCents: 670000,
        accounts: const [tg, giro], // savings first from the bank
        link: 'L1',
        bankName: 'ING',
      );
      expect(r.added.where((t) => t.accountId == null).single.id, 'bank_2');
      expect(r.accounts.single.id, 'bank_t');
      expect(r.touchesMain, isTrue);
    });

    test(
        'each bank account gets its own balance; a move between them is an Umbuchung',
        () {
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
      expect(
          r.added
              .where((t) => t.amountCents == 20000)
              .every((t) => t.category == 'Umbuchung'),
          isTrue);
      expect(r.added.firstWhere((t) => t.id == 'bank_1').category,
          isNot('Umbuchung'));
    });

    test(
        'bookings synced before onto the main account move to their account, keeping the category',
        () {
      final old = Transaction(
          id: 'bank_3',
          amountCents: 20000,
          category: 'Sparen',
          date: DateTime(2026, 10, 2),
          isIncome: true);
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

    test(
        'a second bank books on its own accounts and leaves the main one alone',
        () {
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

  group('categories on sync', () {
    test('PayPal, rent, salary code and a card MCC are categorized locally',
        () {
      final r = BankSync.merge(
        existing: const [],
        incoming: [
          _b('1', -1099, 'PayPal Europe S.a.r.l.', 'PAYPAL *SPOTIFY'),
          _b('2', -89000, 'Hausverwaltung Becker', 'Kaltmiete'),
          _b('3', 250000, 'Musterfirma GmbH', '10/2026', '', 'LOHN/GEHALT'),
          _b('4', -2400, 'Mueller', 'POS', '5812'),
          _b('5', -4550, 'SHELL STATION', 'Tankstelle'),
        ],
        bankBalanceCents: 0,
      );
      expect(r.added[0].category, 'Unterhaltung');
      expect(r.added[0].note, 'Spotify');
      expect(r.added[1].category, 'Wohnen');
      expect(r.added[2].category, 'Gehalt');
      expect(r.added[3].category, 'Essen & Trinken');
      expect(r.added[4].category, 'Transport');
    });

    test('an old automatic Sonstiges does not block a better guess', () {
      final old = Transaction(
        id: 'bank_old',
        amountCents: 4900,
        category: 'Sonstiges',
        date: DateTime(2026, 9, 1),
        isIncome: false,
        note: 'DB Fernverkehr AG',
      );
      final r = BankSync.merge(
        existing: [old],
        incoming: [_b('new', -4900, 'DB Fernverkehr AG')],
        bankBalanceCents: 0,
      );
      expect(r.added.single.category, 'Transport');
    });

    test('a saved choice follows the merchant, including PayPal and AMZN',
        () async {
      Hive.init(Directory.systemTemp.createTempSync('catrules').path);
      if (!Hive.isBoxOpen('settings')) await Hive.openBox('settings');
      await Hive.box('settings').delete('categoryRules');
      await CategoryRules.remember('AMZN Mktp DE', 'Kleidung', isIncome: false);
      await CategoryRules.remember('REWE Markt GmbH', 'Sonstiges',
          isIncome: false);
      final r = BankSync.merge(
        existing: const [],
        incoming: [
          _b('1', -1999, 'PayPal Europe S.a.r.l.', 'PAYPAL *AMAZON'),
          _b('2', -1200, 'REWE Markt GmbH'),
        ],
        bankBalanceCents: 0,
      );
      expect(r.added[0].category, 'Kleidung');
      expect(r.added[1].category, 'Sonstiges');
      expect(r.smarter, 0);
      await Hive.box('settings').delete('categoryRules');
    });

    test('counts a fresh guess outside Sonstiges, not an unknown booking', () {
      final r = BankSync.merge(
        existing: const [],
        incoming: [
          _b('1', -2350, 'REWE Markt GmbH'),
          _b('2', -500, 'Max Mustermann')
        ],
        bankBalanceCents: 0,
      );
      expect(r.smarter, 1);
    });
  });

  group('BankSync smile', () {
    setUp(BankSync.takeSmile);

    test('the warm line only appears when something was sorted', () {
      expect(BankSync.syncedLine(added: 0, smarter: 0), 'Alles aktuell');
      expect(BankSync.syncedLine(added: 1, smarter: 0), '1 neue Buchung');
      expect(BankSync.syncedLine(added: 0, smarter: 12),
          '12 Umsätze smarter eingeordnet');
      expect(BankSync.syncedLine(added: 2, smarter: 1),
          '2 neue Buchungen · 1 Umsatz smarter eingeordnet');
    });

    test('an unspoken sort is folded into the next sync sentence', () {
      BankSync.offerSmile(smarter: 12);
      final claimed = BankSync.claimSmile((added: 4, smarter: 0));
      expect(claimed.added, 4);
      expect(claimed.smarter, 12);
      expect(BankSync.takeSmile().smarter, 0);
    });
  });
}
