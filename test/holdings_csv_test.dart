import 'package:flutter_test/flutter_test.dart';
import 'package:budget_buddy/services/holdings_csv_importer.dart';

void main() {
  group('HoldingsCsvImporter', () {
    test('parses positions with amounts in cents', () {
      const csv = 'Name;Symbol;Typ;Anzahl;Kaufpreis;AktuellerKurs\n'
          'Apple;AAPL;Aktie;10;150,00;180,00\n'
          'Bitcoin;BTC;Krypto;0,5;40000;58000\n';
      final result = HoldingsCsvImporter.parse(csv);

      expect(result.holdings.length, 2);
      expect(result.skipped, 0);

      final apple = result.holdings[0];
      expect(apple.name, 'Apple');
      expect(apple.symbol, 'AAPL');
      expect(apple.type, 'Aktie');
      expect(apple.shares, 10);
      expect(apple.buyPriceCents, 15000);
      expect(apple.currentPriceCents, 18000);

      final btc = result.holdings[1];
      expect(btc.type, 'Krypto');
      expect(btc.shares, 0.5);
    });

    test('falls back to buy price when current is missing', () {
      const csv = 'h\nSAP;SAP;Aktie;5;190,00\n';
      final h = HoldingsCsvImporter.parse(csv).holdings.single;
      expect(h.buyPriceCents, 19000);
      expect(h.currentPriceCents, 19000);
    });

    test('skips invalid lines and counts them', () {
      const csv = 'h\n'
          'Apple;AAPL;Aktie;10;150,00\n'
          'too;few\n' // not enough columns
          ';AAPL;Aktie;10;150,00\n' // empty name
          'Bad;X;Aktie;abc;150,00\n'; // bad share count
      final result = HoldingsCsvImporter.parse(csv);
      expect(result.holdings.length, 1);
      expect(result.skipped, 3);
    });

    test('unknown type defaults to Aktie', () {
      const csv = 'h\nFoo;FOO;Quatsch;1;10,00;12,00\n';
      expect(HoldingsCsvImporter.parse(csv).holdings.single.type, 'Aktie');
    });
  });

  test('a share count with a thousands dot and decimals is read in full', () {
    const csv = 'Name;Symbol;Typ;Anzahl;Kaufpreis;AktuellerKurs\n'
        'Hedera;HBAR;Krypto;7.441,35;0,15;0,07\n'
        'Bitcoin;BTC;Krypto;0.001;60.000,00;\n';
    final r = HoldingsCsvImporter.parse(csv);
    expect(r.holdings.map((h) => h.shares), [7441.35, 0.001]);
  });
}
