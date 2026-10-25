import 'package:flutter_test/flutter_test.dart';
import 'package:budget_buddy/services/price_service.dart';

void main() {
  group('PriceService.parseFinnhubQuote', () {
    test('reads the current price into cents', () {
      expect(PriceService.parseFinnhubQuote('{"c": 180.50, "h": 181, "l": 179}'), 18050);
      expect(PriceService.parseFinnhubQuote('{"c": 42}'), 4200);
    });

    test('returns null for a zero or missing price', () {
      expect(PriceService.parseFinnhubQuote('{"c": 0}'), isNull);
      expect(PriceService.parseFinnhubQuote('{"h": 10}'), isNull);
    });
  });

  group('PriceService.parseCoinGecko', () {
    test('reads the EUR price into cents', () {
      expect(PriceService.parseCoinGecko('{"bitcoin":{"eur":58000.5}}', 'bitcoin'), 5800050);
      expect(PriceService.parseCoinGecko('{"cardano":{"eur":0.40}}', 'cardano'), 40);
    });

    test('returns null when the coin or price is missing', () {
      expect(PriceService.parseCoinGecko('{}', 'bitcoin'), isNull);
      expect(PriceService.parseCoinGecko('{"bitcoin":{"usd":58000}}', 'bitcoin'), isNull);
    });
  });

  group('PriceService.parseUsdEur', () {
    test('reads the EUR rate', () {
      expect(PriceService.parseUsdEur('{"result":"success","rates":{"EUR":0.88183,"GBP":0.79}}'),
          0.88183);
    });
    test('returns null when missing', () {
      expect(PriceService.parseUsdEur('{"rates":{"GBP":0.79}}'), isNull);
    });
  });

  group('PriceService history helpers', () {
    test('parseCoinGeckoSeries extracts prices', () {
      expect(PriceService.parseCoinGeckoSeries('{"prices":[[1,100.5],[2,101.0]]}'),
          [100.5, 101.0]);
      expect(PriceService.parseCoinGeckoSeries('{}'), isEmpty);
    });

    test('parseYahooSeries extracts closes and currency, skipping nulls', () {
      final r = PriceService.parseYahooSeries(
          '{"chart":{"result":[{"meta":{"currency":"USD"},"indicators":{"quote":[{"close":[1.0,2.0,null,3.0]}]}}]}}');
      expect(r, isNotNull);
      expect(r!.closes, [1.0, 2.0, 3.0]);
      expect(r.currency, 'USD');
    });

    test('resample picks evenly spaced points', () {
      expect(PriceService.resample([1, 2, 3, 4, 5], 3), [1, 3, 5]);
      expect(PriceService.resample([1, 2, 3], 3), [1, 2, 3]);
      expect(PriceService.resample([5], 1), [5]);
      expect(PriceService.resample([], 4), isEmpty);
    });
  });

  group('PriceService timestamped history', () {
    test('parseCoinGeckoPoints keeps timestamp + price', () {
      final pts = PriceService.parseCoinGeckoPoints(
          '{"prices":[[1609459200000,100.0],[1609545600000,110.0]]}');
      expect(pts.length, 2);
      expect(pts[0].$2, 100.0);
      expect(pts[1].$2, 110.0);
      expect(pts[0].$1.millisecondsSinceEpoch, 1609459200000);
    });

    test('parseYahooPoints pairs timestamps with closes, skipping nulls', () {
      final r = PriceService.parseYahooPoints(
          '{"chart":{"result":[{"meta":{"currency":"USD"},"timestamp":[1,2],"indicators":{"quote":[{"close":[100.0,null]}]}}]}}');
      expect(r, isNotNull);
      expect(r!.points.length, 1); // the null close is dropped
      expect(r.points[0].$2, 100.0);
      expect(r.currency, 'USD');
    });
  });

  group('PriceService.parseYahooChart', () {
    test('reads price and currency', () {
      final r = PriceService.parseYahooChart(
          '{"chart":{"result":[{"meta":{"regularMarketPrice":293.08,"currency":"USD"}}]}}');
      expect(r, isNotNull);
      expect(r!.price, 293.08);
      expect(r.currency, 'USD');
    });

    test('returns null on an empty or error response', () {
      expect(PriceService.parseYahooChart('{"chart":{"result":null}}'), isNull);
      expect(PriceService.parseYahooChart('{"chart":{"result":[]}}'), isNull);
    });
  });

}
