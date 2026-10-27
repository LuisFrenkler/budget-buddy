import 'package:flutter_test/flutter_test.dart';
import 'package:budget_buddy/models/holding.dart';

void main() {
  Holding make({double shares = 10, int buy = 10000, int cur = 12000}) => Holding(
      id: 'a', name: 'Apple', symbol: 'AAPL', type: 'Aktie',
      shares: shares, buyPriceCents: buy, currentPriceCents: cur);

  group('Holding', () {
    test('computes invested, value, gain and percent in cents', () {
      final h = make(); // 10 shares, buy 100€, now 120€
      expect(h.investedCents, 100000);
      expect(h.valueCents, 120000);
      expect(h.gainCents, 20000);
      expect(h.gainPercent, 20);
      expect(h.isUp, isTrue);
    });

    test('handles a loss', () {
      final h = make(cur: 8000); // now 80€
      expect(h.gainCents, -20000);
      expect(h.gainPercent, -20);
      expect(h.isUp, isFalse);
    });

    test('rounds fractional-share values to whole cents', () {
      final h = make(shares: 0.5, buy: 333, cur: 777);
      expect(h.investedCents, (0.5 * 333).round());
      expect(h.valueCents, (0.5 * 777).round());
    });

    test('gainPercent is 0 when nothing was invested', () {
      expect(make(buy: 0).gainPercent, 0);
    });

    test('round-trips through toMap/fromMap', () {
      final back = Holding.fromMap(make().toMap());
      expect(back.name, 'Apple');
      expect(back.valueCents, 120000);
    });

    test('a live price keeps when it was fetched; older data has none', () {
      final at = DateTime(2026, 10, 27, 9, 30);
      final h = Holding(
              id: 'b', name: 'Bitcoin', symbol: 'BTC', type: 'Krypto', shares: 0.05,
              buyPriceCents: 4000000, currentPriceCents: 5800000)
          .withLivePrice(6000000, at);
      final back = Holding.fromMap(h.toMap());
      expect(back.currentPriceCents, 6000000);
      expect(back.priceAt, at);
      expect(back.shares, 0.05);
      final legacy = Map<String, dynamic>.from(h.toMap())..remove('priceAt');
      expect(Holding.fromMap(legacy).priceAt, isNull);
    });

    test('coins under a cent keep their value: 10.000 HBAR at 0,0543 €', () {
      final h = Holding(
              id: 'h', name: 'Hedera', symbol: 'HBAR', type: 'Krypto', shares: 10000,
              buyPriceCents: 4, currentPriceCents: 4)
          .withLivePrice(5, DateTime(2026, 10, 27), unitEur: 0.0543);
      expect(h.valueCents, 54300); // not 50000 from 0,05 €
      expect(Holding.fromMap(h.toMap()).valueCents, 54300);
      // a price typed in later wins over the old precise one
      final typed = Holding.fromMap({...h.toMap(), 'currentPriceCents': 7});
      expect(typed.valueCents, 70000);
    });
  });
}
