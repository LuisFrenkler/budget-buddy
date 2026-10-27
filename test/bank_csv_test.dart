import 'package:budget_buddy/services/bank_csv_importer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Sparkasse (CAMT, semicolon, quoted)', () {
    const csv = '"Auftragskonto";"Buchungstag";"Valutadatum";"Buchungstext";"Verwendungszweck";'
        '"Beguenstigter/Zahlungspflichtiger";"Kontonummer/IBAN";"BIC (SWIFT-Code)";"Betrag";"Waehrung";"Info"\n'
        '"DE123";"24.10.26";"24.10.26";"KARTENZAHLUNG";"REWE SAGT DANKE";"REWE MARKT GMBH";"";"";"-84,29";"EUR";"Umsatz gebucht"\n'
        '"DE123";"01.10.26";"01.10.26";"GUTSCHRIFT";"Gehalt Oktober";"Muster GmbH";"";"";"2.850,00";"EUR";"Umsatz gebucht"\n';
    final r = BankCsvImporter.parse(csv);
    expect(r.bank, 'Sparkasse');
    expect(r.transactions.length, 2);
    final rewe = r.transactions.first;
    expect(rewe.amountCents, 8429);
    expect(rewe.isIncome, isFalse);
    expect(rewe.date, DateTime(2026, 10, 24));
    expect(rewe.note, 'Rewe Markt GmbH');
    expect(rewe.category, 'Lebensmittel');
    final pay = r.transactions.last;
    expect(pay.amountCents, 285000);
    expect(pay.isIncome, isTrue);
    expect(pay.category, 'Gehalt');
  });

  test('ING with lines before the header', () {
    const csv = 'Umsatzanzeige;Datei erstellt am: 26.10.2026\n'
        '\n'
        'IBAN;DE12 5001 0517 0000 0000 00\n'
        'Kontoname;Girokonto\n'
        '\n'
        'Buchung;Valuta;Auftraggeber/Empfänger;Buchungstext;Verwendungszweck;Saldo;Währung;Betrag;Währung\n'
        '20.10.2026;20.10.2026;Spotify AB;Lastschrift;Spotify Premium;1.234,56;EUR;-10,99;EUR\n';
    final r = BankCsvImporter.parse(csv);
    expect(r.bank, 'ING');
    expect(r.transactions.single.note, 'Spotify AB');
    expect(r.transactions.single.amountCents, 1099);
    expect(r.transactions.single.category, 'Unterhaltung');
  });

  test('N26 with commas and English numbers', () {
    const csv = '"Date","Payee","Account number","Transaction type","Payment reference","Amount (EUR)"\n'
        '"2026-10-12","Lieferando","","MasterCard Payment","","-36.55"\n';
    final r = BankCsvImporter.parse(csv);
    expect(r.transactions.single.amountCents, 3655);
    expect(r.transactions.single.date, DateTime(2026, 10, 12));
    expect(r.transactions.single.category, 'Essen & Trinken');
  });

  test('same file twice adds nothing; unreadable lines are counted', () {
    const csv = 'Buchungstag;Empfänger;Betrag\n'
        '24.10.2026;Aldi Süd;-84,29\n'
        'kaputt;x;y\n';
    final first = BankCsvImporter.parse(csv);
    expect(first.transactions.length, 1);
    expect(first.skipped, 1);
    final again = BankCsvImporter.parse(csv, existing: first.transactions);
    expect(again.transactions, isEmpty);
    expect(again.duplicates, 1);
  });

  test('tells a bank export from the own format', () {
    expect(BankCsvImporter.looksLikeBank('Buchungstag;Empfänger;Betrag\n'), isTrue);
    expect(BankCsvImporter.looksLikeBank('Datum;Kategorie;Beschreibung;Betrag\n'), isFalse);
  });

  test('equal bookings on one day are all kept, and only as many as exist are duplicates', () {
    const csv = 'Buchung;Valuta;Auftraggeber/Empfänger;Buchungstext;Verwendungszweck;Saldo;Währung;Betrag;Währung\n'
        '20.10.2026;20.10.2026;Café;Lastschrift;Kaffee;1,00;EUR;-3,50;EUR\n'
        '20.10.2026;20.10.2026;Café;Lastschrift;Kaffee;1,00;EUR;-3,50;EUR\n';
    final first = BankCsvImporter.parse(csv);
    expect(first.transactions.length, 2);
    expect(first.transactions.map((t) => t.id).toSet().length, 2);

    // one of the two is already in the app: the other one is new
    final again = BankCsvImporter.parse(csv, existing: first.transactions.take(1).toList());
    expect(again.transactions.length, 1);
    expect(again.duplicates, 1);
  });
}
