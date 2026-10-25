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
  });
}
