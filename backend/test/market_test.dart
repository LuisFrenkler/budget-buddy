import 'package:budget_buddy_backend/market.dart';
import 'package:test/test.dart';

void main() {
  test('search keeps equity, etf and crypto and drops the rest', () {
    const body = '''
{"quotes":[
  {"symbol":"AAPL","shortname":"Apple Inc.","quoteType":"EQUITY","exchange":"NMS"},
  {"symbol":"VWCE.DE","longname":"Vanguard FTSE All-World","quoteType":"ETF","exchange":"GER"},
  {"symbol":"BTC-USD","shortname":"Bitcoin USD","quoteType":"CRYPTOCURRENCY","exchange":"CCC"},
  {"symbol":"EURUSD=X","shortname":"EUR/USD","quoteType":"CURRENCY","exchange":"CCY"},
  {"quoteType":"EQUITY","shortname":"ohne Symbol"}
]}''';
    expect(marketQuotes(body), [
      {'symbol': 'AAPL', 'shortname': 'Apple Inc.', 'quoteType': 'EQUITY', 'exchange': 'NMS'},
      {'symbol': 'VWCE.DE', 'shortname': 'Vanguard FTSE All-World', 'quoteType': 'ETF', 'exchange': 'GER'},
      {'symbol': 'BTC-USD', 'shortname': 'Bitcoin USD', 'quoteType': 'CRYPTOCURRENCY', 'exchange': 'CCC'},
    ]);
    expect(marketQuotes('nope'), isEmpty);
  });

  test('news keeps web headlines, prefers the symbol and stops at five', () {
    final items = [
      for (var i = 0; i < 6; i++)
        '{"title":"Meldung $i","link":"https://example.com/$i","publisher":"Reuters","providerPublishTime":170000000$i,"relatedTickers":["AAPL"]}',
    ].join(',');
    final body = '{"news":[$items,{"title":"ohne","publisher":"X"},{"title":"böse","link":"javascript:alert(1)"}]}';
    final news = marketNews(body, symbol: 'AAPL');
    expect(news, hasLength(5));
    expect(news.first['title'], 'Meldung 0');
    expect(news.first['link'], 'https://example.com/0');
    expect(news.first['publisher'], 'Reuters');
    expect(news.first['time'], 1700000000);

    const mixed = '''
{"news":[
  {"title":"Nur erwähnt","link":"https://example.com/m","publisher":"X","relatedTickers":["QCOM","AAPL"]},
  {"title":"Im Fokus","link":"https://example.com/a","publisher":"Y","relatedTickers":["AAPL"]},
  {"title":"Anderes","link":"https://example.com/o","publisher":"Z","relatedTickers":["QCOM"]}
]}''';
    final ranked = marketNews(mixed, symbol: 'aapl');
    expect(ranked.map((n) => n['title']).toList(), ['Im Fokus', 'Nur erwähnt']);

    const loose = '{"news":[{"title":"Loose","link":"https://example.com/l","publisher":"Z","relatedTickers":["QCOM"]}]}';
    expect(marketNews(loose, symbol: 'AAPL').single['title'], 'Loose');
    expect(marketNews('{'), isEmpty);
  });

  test('chart proxy accepts 1d intraday and 5d, and rejects other intervals', () {
    expect(marketChartQueryOk('VWCE.DE', '1d', '5m'), isTrue);
    expect(marketChartQueryOk('EURUSD=X', '5d', '1d'), isTrue);
    expect(marketChartQueryOk('AAPL', '1d', '1d'), isTrue);
    expect(marketChartQueryOk('AAPL', '7d', '1d'), isTrue);
    expect(marketChartQueryOk('AAPL', '1d', '1m'), isFalse);
    expect(marketChartQueryOk('AAPL', '2y', '1d'), isFalse);
    expect(marketChartQueryOk('bad symbol', '1d', '1d'), isFalse);
  });

  test('a search query rejects empty, huge and markup', () {
    expect(marketQueryOk('Münchener Rück'), isTrue);
    expect(marketQueryOk('AT&T'), isTrue);
    expect(marketQueryOk('  '), isFalse);
    expect(marketQueryOk('a<b'), isFalse);
    expect(marketQueryOk('x' * 81), isFalse);
  });
}
