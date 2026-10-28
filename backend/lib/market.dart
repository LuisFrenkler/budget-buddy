// Shapes Yahoo Finance search JSON into the small payload the app reads.
// /market/search and /market/news in server.dart fetch and cache the raw call.
import 'dart:convert';

final _badQuery = RegExp('[\x00-\x1f<>]');

// a search box query we are willing to forward
bool marketQueryOk(String q) {
  final t = q.trim();
  return t.isNotEmpty && t.length <= 80 && !_badQuery.hasMatch(t);
}

const _quoteTypes = {'EQUITY', 'ETF', 'CRYPTOCURRENCY'};

// quotes the picker can turn into Aktie / ETF / Krypto; other types are dropped
List<Map<String, String>> marketQuotes(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return [];
    final quotes = decoded['quotes'];
    if (quotes is! List) return [];
    final out = <Map<String, String>>[];
    for (final q in quotes) {
      if (q is! Map) continue;
      final type = '${q['quoteType'] ?? ''}';
      if (!_quoteTypes.contains(type)) continue;
      final symbol = '${q['symbol'] ?? ''}'.trim();
      if (symbol.isEmpty) continue;
      var name = '${q['shortname'] ?? ''}'.trim();
      if (name.isEmpty) name = '${q['longname'] ?? ''}'.trim();
      if (name.isEmpty) name = symbol;
      out.add({
        'symbol': symbol,
        'shortname': name,
        'quoteType': type,
        'exchange': '${q['exchange'] ?? ''}',
      });
      if (out.length == 10) break;
    }
    return out;
  } catch (_) {
    return [];
  }
}

// Yahoo chart windows the web app may ask for. The interval stays on an
// allowlist so the proxy never forwards an arbitrary query string.
const marketChartRanges = {'1d', '5d', '7d', '1mo', '3mo', '6mo', '1y'};
const marketChartIntervals = {'5m', '1d'};

bool marketChartQueryOk(String symbol, String range, String interval) {
  return RegExp(r'^[A-Za-z0-9.=^-]{1,20}$').hasMatch(symbol) &&
      marketChartRanges.contains(range) &&
      marketChartIntervals.contains(interval);
}

String _webLink(Object? raw) {
  if (raw is! String) return '';
  final link = raw.trim();
  if (link.startsWith('https://') || link.startsWith('http://')) return link;
  return '';
}

// up to five headlines. when [symbol] is set and any story tags it, the rest
// are dropped and stories that lead with that symbol come first
List<Map<String, dynamic>> marketNews(String body, {String symbol = ''}) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return [];
    final raw = decoded['news'];
    if (raw is! List) return [];
    final want = symbol.trim().toUpperCase();
    final all = <({Map<String, dynamic> item, int rank})>[];
    final about = <({Map<String, dynamic> item, int rank})>[];
    for (final n in raw) {
      if (n is! Map) continue;
      final title = '${n['title'] ?? ''}'.trim();
      final link = _webLink(n['link'] ?? n['url']);
      if (title.isEmpty || link.isEmpty) continue;
      final item = <String, dynamic>{
        'title': title,
        'link': link,
        'publisher': '${n['publisher'] ?? ''}'.trim(),
      };
      final time = n['providerPublishTime'];
      if (time is num) item['time'] = time.toInt();
      final tickers = [
        if (n['relatedTickers'] is List)
          for (final t in n['relatedTickers'] as List) '$t'.toUpperCase(),
      ];
      final row = (item: item, rank: tickers.isNotEmpty && tickers.first == want ? 0 : 1);
      all.add(row);
      if (want.isEmpty || tickers.contains(want)) about.add(row);
    }
    final picked = want.isNotEmpty && about.isNotEmpty ? about : all;
    picked.sort((a, b) => a.rank.compareTo(b.rank));
    return [for (final row in picked.take(5)) row.item];
  } catch (_) {
    return [];
  }
}
