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
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/holding.dart';
import 'db.dart';

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
      final fx = await _fxUsdToEur();
      return fx == null ? usdCents : (usdCents * fx).round();
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
    final id = _coinIds[symbol.toUpperCase()];
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
  static Future<Map<String, int>> fetchCryptoPricesEur(List<String> symbols) async {
    final symToId = <String, String>{};
    for (final s in symbols) {
      final id = _coinIds[s.toUpperCase()];
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
      final out = <String, int>{};
      symToId.forEach((sym, id) {
        final eur = (map[id] as Map?)?['eur'];
        if (eur is num && eur > 0) out[sym] = (eur * 100).round();
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

  static Future<String?> _yahooRaw(String symbol) async {
    try {
      final url = Uri.parse(
          'https://query1.finance.yahoo.com/v8/finance/chart/$symbol?interval=1d&range=1d');
      final res = await http.get(url);
      return res.statusCode == 200 ? res.body : null;
    } catch (_) {
      return null;
    }
  }

  // conversion rate from the given currency into EUR (cached per session)
  static Future<double?> _fxToEur(String currency) async {
    if (currency == 'EUR') return 1.0;
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
    final id = _coinIds[symbol.toUpperCase()];
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

  static Future<List<(DateTime, double)>> _yahooPoints(String symbol, int days) async {
    final range = days <= 7 ? '7d' : days <= 31 ? '1mo' : days <= 93 ? '3mo' : '1y';
    try {
      final res = await http.get(Uri.parse(
          'https://query1.finance.yahoo.com/v8/finance/chart/$symbol?interval=1d&range=$range'));
      if (res.statusCode != 200) return [];
      final parsed = parseYahooPoints(res.body);
      if (parsed == null) return [];
      final rate = await _fxToEur(parsed.currency) ?? 1.0;
      return [for (final p in parsed.points) (p.$1, p.$2 * rate)];
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

    final pts = type == 'Krypto'
        ? await _coinGeckoPoints(symbol, days)
        : await _yahooPoints(symbol, days);
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
  // calendar days. Each holding's price is taken from the most recent quote
  // on-or-before that day (date-aligned, so mixed instruments sum correctly);
  // holdings without any history contribute a flat line at their current price.
  static Future<List<int>> portfolioHistory({int days = 30}) async {
    final holdings = DB.getHoldings();
    if (holdings.isEmpty) return [];

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final axis = [for (int i = days - 1; i >= 0; i--) today.subtract(Duration(days: i))];
    final axisKeys = [for (final d in axis) _dayKey(d)];

    final series = List<int>.filled(days, 0);
    for (final h in holdings) {
      final pts = await historyPoints(symbol: h.symbol, type: h.type, days: days);

      // last price seen per calendar day
      final byDay = <int, double>{};
      for (final p in pts) {
        byDay[_dayKey(p.$1)] = p.$2;
      }
      final keys = byDay.keys.toList()..sort();
      final fallback = h.currentPriceCents / 100;

      for (int i = 0; i < days; i++) {
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
          price = atOrBefore ?? byDay[keys.first]!;
        }
        series[i] += (h.shares * price * 100).round();
      }
    }
    return series;
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
    final cryptoPrices =
        cryptoSymbols.isEmpty ? <String, int>{} : await fetchCryptoPricesEur(cryptoSymbols);

    for (final h in holdings) {
      final newPrice = h.type == 'Krypto'
          ? cryptoPrices[h.symbol.toUpperCase()]
          : await livePrice(symbol: h.symbol, type: h.type);
      if (newPrice == null || newPrice <= 0) {
        failed++;
        continue;
      }
      live++;
      if (newPrice != h.currentPriceCents) {
        await DB.addHolding(Holding(
          id: h.id,
          name: h.name,
          symbol: h.symbol,
          type: h.type,
          shares: h.shares,
          buyPriceCents: h.buyPriceCents,
          currentPriceCents: newPrice,
        ));
        updated++;
      }
    }
    return (updated: updated, live: live, failed: failed);
  }
}
