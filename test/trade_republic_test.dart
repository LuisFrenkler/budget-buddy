import 'package:flutter_test/flutter_test.dart';
import 'package:budget_buddy/services/trade_republic_importer.dart';

void main() {
  group('TradeRepublicImporter', () {
    const csv = '"type","asset_class","name","symbol","shares","price"\n'
        '"BUY","CRYPTO","Bitcoin","BTC","0.002","40000"\n'
        '"SELL","CRYPTO","Bitcoin","BTC","-0.001","45000"\n'
        '"CUSTOMER_INPAYMENT","","","","",""\n'
        '"BUY","STOCK","Apple","AAPL","2","150"\n'
        '"BUY","CRYPTO","Solana","SOL","3","100"\n'
        '"SELL","CRYPTO","Solana","SOL","-3","120"\n';

    test('detects the Trade Republic format', () {
      expect(TradeRepublicImporter.looksLikeTradeRepublic(csv), isTrue);
      expect(TradeRepublicImporter.looksLikeTradeRepublic('Name;Symbol;Typ\n'), isFalse);
    });

    test('reconstructs net positions with an average buy price', () {
      final res = TradeRepublicImporter.parse(csv);
      // Solana was fully sold (3 - 3 = 0) -> excluded; BTC + Apple remain
      expect(res.holdings.length, 2);

      final btc = res.holdings.firstWhere((h) => h.symbol == 'BTC');
      expect(btc.type, 'Krypto');
      expect(btc.shares, closeTo(0.001, 1e-9));
      expect(btc.buyPriceCents, 4000000); // avg of the single buy at 40000
      expect(btc.currentPriceCents, 4500000); // last seen price (the sell at 45000)

      final apple = res.holdings.firstWhere((h) => h.symbol == 'AAPL');
      expect(apple.type, 'Aktie');
      expect(apple.shares, 2);
      expect(apple.buyPriceCents, 15000);
    });

    test('ignores cash rows and counts no skips', () {
      expect(TradeRepublicImporter.parse(csv).skipped, 0);
    });

    test('uses moving-average cost basis after a sell and re-buy', () {
      const csv2 = '"type","asset_class","name","symbol","shares","price"\n'
          '"BUY","STOCK","Foo","FOO","1","100"\n'
          '"SELL","STOCK","Foo","FOO","-1","120"\n'
          '"BUY","STOCK","Foo","FOO","1","200"\n';
      final h = TradeRepublicImporter.parse(csv2).holdings.single;
      expect(h.shares, closeTo(1, 1e-9));
      // basis reset by the full sell, so it's the re-buy price (200), not 150
      expect(h.buyPriceCents, 20000);
    });
  });
}
