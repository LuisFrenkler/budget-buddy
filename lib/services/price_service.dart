// Fetches live market prices for portfolio holdings.
//
// Real quotes come from Finnhub (https://finnhub.io). A free API key is read at
// build time via --dart-define=FINNHUB_KEY=xxxx. For production the key belongs
// in a small backend proxy (never shipped in the client, and to avoid browser
// CORS limits); the dart-define path is fine for local/personal use.
//
// Without a key the service runs in DEMO mode: it nudges each price slightly so
// the feature is fully usable (button → prices move → gain/loss + donut update)
// without any network call.
import 'package:hive/hive.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../utils/instruments.dart';
import 'backend_service.dart';
import 'db.dart';
import 'depot_sync.dart';
import 'settings_service.dart';

class MarketHeadline {
  final String title;
  final String url;
  final String publisher;
  const MarketHeadline(this.title, this.url, this.publisher);
}

class PriceService {
  static const _finnhubKey = String.fromEnvironment('FINNHUB_KEY');

  static bool get hasApiKey => _finnhubKey.isNotEmpty;

  // CoinGecko's free API rate-limits bursts, so all CoinGecko calls are run
  // through a serialized queue that spaces them out, and history is cached.
  static Future<void> _cgChain = Future<void>.value();
  static final Map<String, List<(DateTime, double)>> _historyCache = {};

  static Future<T> _cgThrottled<T>(Future<T> Function() task) {
    final result = _cgChain.then((_) => task());
    _cgChain = result.then(
      (_) => Future<void>.delayed(const Duration(milliseconds: 1600)),
      onError: (_) => Future<void>.delayed(const Duration(milliseconds: 1600)),
    );
    return result;
  }

  // crypto symbol -> CoinGecko id (CoinGecko is keyless and CORS-friendly, so
  // crypto prices are genuinely live even in the browser without any key)
  static const _coinIds = {
    'BTC': 'bitcoin',
    'ETH': 'ethereum',
    'SOL': 'solana',
    'ADA': 'cardano',
    'XRP': 'ripple',
    'DOGE': 'dogecoin',
    'DOT': 'polkadot',
    'LTC': 'litecoin',
    'HBAR': 'hedera-hashgraph',
    'FET': 'fetch-ai',
    'SAND': 'the-sandbox',
  };

  // "BTC-EUR", "btc", "XF000BTC0017" (Trade Republic's crypto ISIN) -> "BTC"
  static String coinSymbol(String raw) {
    var s = raw.trim().toUpperCase();
    final isin = RegExp(r'^XF000([A-Z0-9]{2,8}?)\d{4}$').firstMatch(s);
    if (isin != null) return isin.group(1)!;
    s = s.replaceFirst(RegExp(r'[-/]?(EUR|USD|USDT)$'), '');
    return s.isEmpty ? raw.trim().toUpperCase() : s;
  }

  static final Map<String, String?> _foundIds = {};

  // picks the coin with this exact symbol and the biggest market cap from a
  // CoinGecko /search response (many tokens share a ticker)
  static String? parseCoinSearch(String body, String symbol) {
    final coins = ((jsonDecode(body) as Map)['coins'] as List?) ?? const [];
    String? best;
    num bestRank = double.infinity;
    for (final c in coins.whereType<Map>()) {
      if ('${c['symbol']}'.toUpperCase() != symbol) continue;
      final rank = (c['market_cap_rank'] as num?) ?? 1e9;
      if (best == null || rank < bestRank) {
        best = '${c['id']}';
        bestRank = rank;
      }
    }
    return best;
  }

  // the CoinGecko id for any coin, not only the well-known ones: looked up
  // once and remembered on the device
  static Future<String?> coinId(String raw) async {
    final symbol = coinSymbol(raw);
    final known = _coinIds[symbol];
    if (known != null) return known;
    if (_foundIds.containsKey(symbol)) return _foundIds[symbol];
    final settings = Hive.isBoxOpen('settings') ? Hive.box('settings') : null;
    final saved = (settings?.get('coinIds') as Map?)?[symbol];
    if (saved is String) return _foundIds[symbol] = saved;
    try {
      final res = await _cgThrottled(() =>
          http.get(Uri.parse('https://api.coingecko.com/api/v3/search?query=${Uri.encodeQueryComponent(symbol)}')));
      if (res.statusCode != 200) return null; // rate limit: try again next time
      final id = parseCoinSearch(res.body, symbol);
      _foundIds[symbol] = id;
      if (id != null && settings != null) {
        await settings.put('coinIds', {...(settings.get('coinIds') as Map? ?? const {}), symbol: id});
      }
      return id;
    } catch (_) {
      return null;
    }
  }

  // a coin the app knows by its ticker, e.g. for a position Buddy adds
  static bool isKnownCoin(String symbol) => _coinIds.containsKey(coinSymbol(symbol));

  // parses a Finnhub /quote response; field 'c' is the current price.
  // returns the price in cents, or null if unavailable.
  static int? parseFinnhubQuote(String body) {
    final map = jsonDecode(body) as Map<String, dynamic>;
    final c = map['c'];
    if (c is num && c > 0) return (c * 100).round();
    return null;
  }

  // fetches the latest price for one symbol via Finnhub (free tier = US stocks,
  // priced in USD) and converts it to EUR cents. returns null on failure.
  static Future<int?> fetchQuote(String symbol) async {
    if (!hasApiKey || symbol.isEmpty) return null;
    try {
      final url = Uri.parse(
          'https://finnhub.io/api/v1/quote?symbol=$symbol&token=$_finnhubKey');
      final res = await http.get(url);
      if (res.statusCode != 200) return null;
      final usdCents = parseFinnhubQuote(res.body);
      if (usdCents == null) return null;
      // without the rate a dollar price would be shown as euros: better none
      final fx = await _fxUsdToEur();
      return fx == null ? null : (usdCents * fx).round();
    } catch (_) {
      return null;
    }
  }

  // parses an open.er-api.com response into the USD->EUR rate
  static double? parseUsdEur(String body) {
    final map = jsonDecode(body) as Map<String, dynamic>;
    final eur = (map['rates'] as Map?)?['EUR'];
    return (eur is num && eur > 0) ? eur.toDouble() : null;
  }

  // USD->EUR rate from a keyless, CORS-friendly source (cached per session)
  static Future<double?> _fxUsdToEur() async {
    if (_fxCache.containsKey('USD')) return _fxCache['USD'];
    try {
      final res = await http.get(Uri.parse('https://open.er-api.com/v6/latest/USD'));
      if (res.statusCode != 200) return null;
      final fx = parseUsdEur(res.body);
      if (fx != null) _fxCache['USD'] = fx;
      return fx;
    } catch (_) {
      return null;
    }
  }

  // parses a CoinGecko /simple/price response into EUR cents
  static int? parseCoinGecko(String body, String coinId) {
    final map = jsonDecode(body) as Map<String, dynamic>;
    final eur = (map[coinId] as Map?)?['eur'];
    if (eur is num && eur > 0) return (eur * 100).round();
    return null;
  }

  // fetches a live crypto price in EUR cents (keyless), or null
  static Future<int?> fetchCryptoEur(String symbol) async {
    final id = await coinId(symbol);
    if (id == null) return null;
    try {
      final url = Uri.parse(
          'https://api.coingecko.com/api/v3/simple/price?ids=$id&vs_currencies=eur');
      final res = await _cgThrottled(() => http.get(url));
      if (res.statusCode != 200) return null;
      return parseCoinGecko(res.body, id);
    } catch (_) {
      return null;
    }
  }

  // fetches many crypto prices in ONE call (symbol -> EUR cents), avoiding a
  // burst of per-coin requests that would hit the rate limit.
  static Future<Map<String, int>> fetchCryptoPricesEur(List<String> symbols) async =>
      {for (final e in (await fetchCryptoEuros(symbols)).entries) e.key: (e.value * 100).round()};

  // the same in euros with every decimal (0,0543 € for HBAR)
  static Future<Map<String, double>> fetchCryptoEuros(List<String> symbols) async {
    final symToId = <String, String>{};
    for (final s in symbols) {
      final id = await coinId(s);
      if (id != null) symToId[s.toUpperCase()] = id;
    }
    if (symToId.isEmpty) return {};
    try {
      final ids = symToId.values.toSet().join(',');
      final url = Uri.parse(
          'https://api.coingecko.com/api/v3/simple/price?ids=$ids&vs_currencies=eur');
      final res = await _cgThrottled(() => http.get(url));
      if (res.statusCode != 200) return {};
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final out = <String, double>{};
      symToId.forEach((sym, id) {
        final eur = (map[id] as Map?)?['eur'];
        if (eur is num && eur > 0) out[sym] = eur.toDouble();
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  // --- stocks/ETFs via Yahoo Finance (keyless; works on device, blocked by
  // CORS in the browser where a Finnhub key is used instead) ---

  static final Map<String, double> _fxCache = {};

  // parses a Yahoo chart response into price + listing currency
  static ({double price, String currency})? parseYahooChart(String body) {
    final map = jsonDecode(body) as Map<String, dynamic>;
    final result = (map['chart']?['result'] as List?);
    if (result == null || result.isEmpty) return null;
    final meta = result.first['meta'] as Map<String, dynamic>?;
    final price = meta?['regularMarketPrice'];
    final currency = meta?['currency'];
    if (price is num && price > 0 && currency is String) {
      return (price: price.toDouble(), currency: currency);
    }
    return null;
  }

  // which Yahoo window a chart of [days] needs. 1T is the session (5-minute
  // bars); 1W is the 5-day daily chart Yahoo actually serves.
  static ({String range, String interval}) yahooWindow(int days) {
    if (days <= 1) return (range: '1d', interval: '5m');
    if (days <= 7) return (range: '5d', interval: '1d');
    if (days <= 31) return (range: '1mo', interval: '1d');
    if (days <= 93) return (range: '3mo', interval: '1d');
    if (days <= 186) return (range: '6mo', interval: '1d');
    return (range: '1y', interval: '1d');
  }

  // a 1-day chart that only has daily closes: the last session when it has
  // several points, otherwise the last two closes so a line can be drawn
  static List<(DateTime, double)> lastDayPoints(List<(DateTime, double)> pts) {
    if (pts.length < 2) return pts;
    final last = pts.last.$1;
    final same = [
      for (final p in pts)
        if (p.$1.year == last.year && p.$1.month == last.month && p.$1.day == last.day) p,
    ];
    if (same.length >= 2) return same;
    return [pts[pts.length - 2], pts.last];
  }

  // Yahoo's chart API; in the browser it sends no CORS headers, so the web
  // build asks through the backend proxy instead
  static Uri _yahooUrl(String symbol, String range, {String interval = '1d'}) {
    final query = 'interval=$interval&range=$range';
    return kIsWeb
        ? Uri.parse('${BackendService.base}/market/chart?symbol=${Uri.encodeQueryComponent(symbol)}&$query')
        : Uri.parse('https://query1.finance.yahoo.com/v8/finance/chart/$symbol?$query');
  }

  static Future<String?> _yahooRaw(String symbol) async {
    try {
      final res = await http.get(_yahooUrl(symbol, '1d'));
      return res.statusCode == 200 ? res.body : null;
    } catch (_) {
      return null;
    }
  }

  // conversion rate from the given currency into EUR (cached per session)
  static Future<double?> _fxToEur(String currency) async {
    if (currency == 'EUR') return 1.0;
    // London and Johannesburg quote in pence and cents: GBp = GBP / 100
    if (currency == 'GBp' || currency == 'ZAc') {
      final major = await _fxToEur(currency.toUpperCase());
      return major == null ? null : major / 100;
    }
    if (_fxCache.containsKey(currency)) return _fxCache[currency];
    final body = await _yahooRaw('${currency}EUR=X');
    final parsed = body == null ? null : parseYahooChart(body);
    if (parsed != null) {
      _fxCache[currency] = parsed.price;
      return parsed.price;
    }
    return null;
  }

  // live stock/ETF price in EUR cents (Yahoo + FX), or null
  static Future<int?> fetchStockEur(String symbol) async {
    if (symbol.isEmpty) return null;
    final body = await _yahooRaw(symbol);
    if (body == null) return null;
    final parsed = parseYahooChart(body);
    if (parsed == null) return null;
    final fx = await _fxToEur(parsed.currency);
    if (fx == null) return null;
    return (parsed.price * fx * 100).round();
  }

  // --- historical price series (for charts) ---

  // parses a CoinGecko market_chart response into a list of EUR prices
  static List<double> parseCoinGeckoSeries(String body) {
    final map = jsonDecode(body) as Map<String, dynamic>;
    final prices = map['prices'] as List?;
    if (prices == null) return [];
    final out = <double>[];
    for (final p in prices) {
      final v = (p is List && p.length > 1) ? p[1] : null;
      if (v is num && v > 0) out.add(v.toDouble());
    }
    return out;
  }

  // parses a Yahoo chart response into close prices + listing currency
  static ({List<double> closes, String currency})? parseYahooSeries(String body) {
    final map = jsonDecode(body) as Map<String, dynamic>;
    final result = (map['chart']?['result'] as List?);
    if (result == null || result.isEmpty) return null;
    final r0 = result.first as Map<String, dynamic>;
    final currency = r0['meta']?['currency'];
    final closes = r0['indicators']?['quote']?[0]?['close'] as List?;
    if (closes == null || currency is! String) return null;
    final out = <double>[];
    for (final c in closes) {
      if (c is num && c > 0) out.add(c.toDouble());
    }
    return (closes: out, currency: currency);
  }

  // resamples a series to exactly [n] evenly spaced points
  static List<double> resample(List<double> src, int n) {
    if (src.isEmpty || n <= 0) return [];
    if (n == 1) return [src.last];
    if (src.length == n) return src;
    final out = <double>[];
    for (int i = 0; i < n; i++) {
      final pos = (i * (src.length - 1) / (n - 1)).round().clamp(0, src.length - 1);
      out.add(src[pos]);
    }
    return out;
  }

  // parses a CoinGecko market_chart response into timestamped EUR prices
  static List<(DateTime, double)> parseCoinGeckoPoints(String body) {
    final map = jsonDecode(body) as Map<String, dynamic>;
    final prices = map['prices'] as List?;
    if (prices == null) return [];
    final out = <(DateTime, double)>[];
    for (final p in prices) {
      if (p is List && p.length > 1) {
        final ts = p[0];
        final v = p[1];
        if (ts is num && v is num && v > 0) {
          out.add((DateTime.fromMillisecondsSinceEpoch(ts.toInt()), v.toDouble()));
        }
      }
    }
    return out;
  }

  // parses a Yahoo chart response into timestamped close prices + currency
  static ({List<(DateTime, double)> points, String currency})? parseYahooPoints(String body) {
    final map = jsonDecode(body) as Map<String, dynamic>;
    final result = (map['chart']?['result'] as List?);
    if (result == null || result.isEmpty) return null;
    final r0 = result.first as Map<String, dynamic>;
    final currency = r0['meta']?['currency'];
    final ts = r0['timestamp'] as List?;
    final closes = r0['indicators']?['quote']?[0]?['close'] as List?;
    if (ts == null || closes == null || currency is! String) return null;
    final out = <(DateTime, double)>[];
    final n = ts.length < closes.length ? ts.length : closes.length;
    for (int i = 0; i < n; i++) {
      final t = ts[i];
      final c = closes[i];
      if (t is num && c is num && c > 0) {
        out.add((DateTime.fromMillisecondsSinceEpoch((t * 1000).round()), c.toDouble()));
      }
    }
    return (points: out, currency: currency);
  }

  static Future<List<(DateTime, double)>> _coinGeckoPoints(String symbol, int days) async {
    final id = await coinId(symbol);
    if (id == null) return [];
    try {
      final url = Uri.parse(
          'https://api.coingecko.com/api/v3/coins/$id/market_chart?vs_currency=eur&days=$days');
      final res = await _cgThrottled(() => http.get(url));
      return res.statusCode == 200 ? parseCoinGeckoPoints(res.body) : [];
    } catch (_) {
      return [];
    }
  }

  static Future<List<(DateTime, double)>> _yahooSeries(String symbol, String range, String interval) async {
    final res = await http.get(_yahooUrl(symbol, range, interval: interval));
    if (res.statusCode != 200) return [];
    final parsed = parseYahooPoints(res.body);
    if (parsed == null) return [];
    // without the rate a dollar chart would pass for euros: better none
    final rate = await _fxToEur(parsed.currency);
    if (rate == null) return [];
    return [for (final p in parsed.points) (p.$1, p.$2 * rate)];
  }

  static Future<List<(DateTime, double)>> _yahooPoints(String symbol, int days) async {
    final window = yahooWindow(days);
    try {
      final pts = await _yahooSeries(symbol, window.range, window.interval);
      // a closed or thin session has no 5-minute bars: fall back to 5d daily
      if (days > 1 || pts.length >= 2) return pts;
      final daily = await _yahooSeries(symbol, '5d', '1d');
      return lastDayPoints(daily.isEmpty ? pts : daily);
    } catch (_) {
      return [];
    }
  }

  // timestamped historical EUR prices (crypto via CoinGecko, stocks via Yahoo),
  // cached per session so repeated chart/trend loads don't refetch.
  static Future<List<(DateTime, double)>> historyPoints(
      {required String symbol, required String type, int days = 30}) async {
    final cacheKey = '$type:$symbol:$days';
    final cached = _historyCache[cacheKey];
    if (cached != null) return cached;

    var pts = type == 'Krypto'
        ? await _coinGeckoPoints(symbol, days)
        : await _yahooPoints(symbol, days);
    // a 1-day crypto series can be a single tick: take the last day of a short window
    if (type == 'Krypto' && days <= 1 && pts.length < 2) {
      pts = lastDayPoints(await _coinGeckoPoints(symbol, 5));
    }
    if (pts.isNotEmpty) _historyCache[cacheKey] = pts; // cache only real data
    return pts;
  }

  // historical EUR prices for an instrument's chart (just the values)
  static Future<List<double>> history(
      {required String symbol, required String type, int days = 30}) async {
    final pts = await historyPoints(symbol: symbol, type: type, days: days);
    return [for (final p in pts) p.$2];
  }

  static int _dayKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  // reconstructs the portfolio value (in cents) for each of the last [days]
  // calendar days (at least two: 1T is today against yesterday). Each holding's
  // price is taken from the most recent quote on-or-before that day
  // (date-aligned, so mixed instruments sum correctly);
  // holdings without any history contribute a flat line at their current price.
  //
  // Positions of a linked depot use the depot's own value history instead
  // (see [linkedHistory]): it is exact, includes buys and sells and needs no
  // price lookups.
  static Future<List<int>> portfolioHistory({int days = 30}) async {
    var holdings = DB.getHoldings();
    if (holdings.isEmpty) return [];

    // one point cannot draw a line: 1T is today against yesterday
    final span = days < 2 ? 2 : days;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final axis = [for (int i = span - 1; i >= 0; i--) today.subtract(Duration(days: i))];
    final axisKeys = [for (final d in axis) _dayKey(d)];

    final series = List<int>.filled(span, 0);
    final linked = holdings.where((h) => h.id.startsWith(DepotSync.prefix)).toList();
    final depotHistory = Settings.depotHistory;
    if (linked.isNotEmpty && depotHistory.isNotEmpty) {
      final current = linked.fold<int>(0, (s, h) => s + h.valueCents);
      final part = linkedHistory(depotHistory, axis, current);
      for (int i = 0; i < span; i++) {
        series[i] += part[i];
      }
      holdings = holdings.where((h) => !h.id.startsWith(DepotSync.prefix)).toList();
    }
    for (final h in holdings) {
      final pts = await historyPoints(symbol: h.symbol, type: h.type, days: span);

      // last price seen per calendar day
      final byDay = <int, double>{};
      for (final p in pts) {
        byDay[_dayKey(p.$1)] = p.$2;
      }
      final keys = byDay.keys.toList()..sort();
      final fallback = h.currentPriceCents / 100;
      // the series ends at the holding's current value, so chart and headline
      // agree, as long as the two are close (timing, rounding)
      final scale = keys.isEmpty ? 1.0 : alignScale(fallback, byDay[keys.last]!);

      for (int i = 0; i < span; i++) {
        double price;
        if (keys.isEmpty) {
          price = fallback; // no history (e.g. an ISIN stock in the browser)
        } else {
          double? atOrBefore;
          for (final k in keys) {
            if (k <= axisKeys[i]) {
              atOrBefore = byDay[k];
            } else {
              break;
            }
          }
          // before the first known quote: back-fill with the earliest price
          price = (atOrBefore ?? byDay[keys.first]!) * scale;
        }
        series[i] += (h.shares * price * 100).round();
      }
    }
    return series;
  }

  // a linked depot's value on each [axis] day: the last known value on or
  // before that day (0 before the depot existed), scaled so the last day
  // equals [currentCents] and chart and headline agree
  static List<int> linkedHistory(List<(DateTime, int)> points, List<DateTime> axis, int currentCents) {
    if (points.isEmpty) return List.filled(axis.length, currentCents);
    final sorted = [...points]..sort((a, b) => a.$1.compareTo(b.$1));
    final last = sorted.last.$2;
    final scale = last > 0 ? currentCents / last : 1.0;
    final out = <int>[];
    var j = -1;
    for (final day in axis) {
      final key = _dayKey(day);
      while (j + 1 < sorted.length && _dayKey(sorted[j + 1].$1) <= key) {
        j++;
      }
      out.add(j < 0 ? 0 : (sorted[j].$2 * scale).round());
    }
    // today is always the current value, even before Parqet has today's point
    if (out.isNotEmpty) out[out.length - 1] = currentCents;
    return out;
  }

  // best available live price in EUR cents for an instrument, or null.
  // crypto: always live & keyless (CoinGecko).
  // stocks/ETFs: Yahoo (keyless, EUR-correct) where reachable, else a Finnhub
  // key as a browser fallback.
  static Future<int?> livePrice({required String symbol, required String type}) async {
    if (type == 'Krypto') return fetchCryptoEur(symbol);
    final yahoo = await fetchStockEur(symbol);
    if (yahoo != null) return yahoo;
    if (hasApiKey && symbol.isNotEmpty) return fetchQuote(symbol);
    return null;
  }

  // How much a quote history is stretched so it ends at the stored price.
  // Only small gaps are closed (a few minutes of trading, rounding): a price
  // that was typed in or is weeks old must not bend the real history.
  static double alignScale(double stored, double lastQuote) {
    if (stored <= 0 || lastQuote <= 0) return 1;
    final ratio = stored / lastQuote;
    return ratio >= 0.95 && ratio <= 1.05 ? ratio : 1;
  }

  // refreshes every holding with a real live price. holdings whose price can't
  // be fetched live (e.g. a stock in the browser without a Finnhub key) are
  // left untouched — nothing is ever simulated. returns how many changed
  // (updated), how many were successfully fetched live (live, incl. unchanged),
  // and how many had no reachable live source (failed).
  static Future<({int updated, int live, int failed})> refreshAll() async {
    final holdings = DB.getHoldings();
    int updated = 0;
    int live = 0;
    int failed = 0;

    // fetch all crypto prices in one batched call (one request, no rate-limit burst)
    final cryptoSymbols = holdings
        .where((h) => h.type == 'Krypto' && h.symbol.isNotEmpty)
        .map((h) => h.symbol)
        .toList();
    final cryptoEuros =
        cryptoSymbols.isEmpty ? <String, double>{} : await fetchCryptoEuros(cryptoSymbols);

    final now = DateTime.now();
    for (final h in holdings) {
      final euros = h.type == 'Krypto' ? cryptoEuros[h.symbol.toUpperCase()] : null;
      final newPrice = h.type == 'Krypto'
          ? (euros == null ? null : (euros * 100).round())
          : await livePrice(symbol: h.symbol, type: h.type);
      // a coin under half a cent (PEPE, SHIB) is 0 in whole cents but still live
      if (newPrice == null || (newPrice <= 0 && (euros ?? 0) <= 0)) {
        failed++;
        continue;
      }
      live++;
      if (newPrice != h.currentPriceCents) updated++;
      // also an unchanged price is fresh now: the "Stand" moves on
      await DB.addHolding(h.withLivePrice(newPrice, now, unitEur: euros));
    }
    return (updated: updated, live: live, failed: failed);
  }

  // --- live instrument search and headlines, always through the backend ---

  static const _types = {'EQUITY': 'Aktie', 'ETF': 'ETF', 'CRYPTOCURRENCY': 'Krypto'};

  static List<Instrument> parseSearch(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return [];
    final quotes = decoded['quotes'];
    if (quotes is! List) return [];
    final out = <Instrument>[];
    for (final q in quotes.whereType<Map>()) {
      final type = _types['${q['quoteType']}'];
      final symbol = '${q['symbol'] ?? ''}'.trim();
      if (type == null || symbol.isEmpty) continue;
      var name = '${q['shortname'] ?? ''}'.trim();
      if (name.isEmpty) name = symbol;
      out.add(Instrument(name, symbol, type, 0));
      if (out.length == 10) break;
    }
    return out;
  }

  static List<MarketHeadline> parseNews(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return [];
    final news = decoded['news'];
    if (news is! List) return [];
    final out = <MarketHeadline>[];
    for (final n in news.whereType<Map>()) {
      final title = '${n['title'] ?? ''}'.trim();
      final link = '${n['link'] ?? ''}'.trim();
      if (title.isEmpty || !(link.startsWith('https://') || link.startsWith('http://'))) continue;
      out.add(MarketHeadline(title, link, '${n['publisher'] ?? ''}'.trim()));
      if (out.length == 5) break;
    }
    return out;
  }

  static Future<String?> _marketBody(String path) async {
    try {
      final res = await http.get(Uri.parse('${BackendService.base}$path')).timeout(const Duration(seconds: 8));
      return res.statusCode == 200 ? res.body : null;
    } catch (_) {
      return null;
    }
  }

  // live matches for the instrument picker; empty when the backend is down
  static Future<List<Instrument>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final body = await _marketBody('/market/search?q=${Uri.encodeQueryComponent(q)}');
    if (body == null) return [];
    try {
      return parseSearch(body);
    } catch (_) {
      return [];
    }
  }

  // a few headlines for one symbol; empty when there are none or the call fails
  static Future<List<MarketHeadline>> news(String symbol) async {
    final s = symbol.trim();
    if (s.isEmpty) return [];
    final body = await _marketBody('/market/news?symbol=${Uri.encodeQueryComponent(s)}');
    if (body == null) return [];
    try {
      return parseNews(body);
    } catch (_) {
      return [];
    }
  }
}
