// Depot sync through Parqet Connect (https://developer.parqet.com).
//
// Trade Republic, Scalable and most other brokers have no open interface for
// depots. Parqet syncs them (Autosync) and lets other apps read the result
// with the user's consent: OAuth 2.0 with PKCE, scope portfolio:read. So a
// user links Trade Republic -> Parqet once, then Parqet -> BudgetBuddy here,
// and never gives BudgetBuddy their broker login.
//
// Without PARQET_CLIENT_ID the server runs a demo depot with the same steps
// (consent page, polling, sync) and generated positions.
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class DepotPosition {
  final String id; // stable across syncs (ISIN or crypto symbol)
  final String name;
  final String symbol; // crypto symbol, empty for securities
  final String type; // 'Aktie' | 'ETF' | 'Krypto' | 'Sonstiges'
  final double shares;
  final int buyPriceCents; // per share
  final int priceCents; // per share
  final String broker;
  const DepotPosition(this.id, this.name, this.symbol, this.type, this.shares, this.buyPriceCents, this.priceCents,
      this.broker);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'symbol': symbol,
        'type': type,
        'shares': shares,
        'buyPriceCents': buyPriceCents,
        'priceCents': priceCents,
        'broker': broker,
      };
}

class DepotTokens {
  final String access;
  final String? refresh;
  final DateTime expires;
  const DepotTokens(this.access, this.refresh, this.expires);

  Map<String, dynamic> toJson() => {'access': access, 'refresh': refresh, 'expires': expires.toIso8601String()};
  static DepotTokens fromJson(Map m) =>
      DepotTokens('${m['access']}', m['refresh'] as String?, DateTime.parse('${m['expires']}'));
}

abstract class DepotProvider {
  String get mode; // 'live' or 'demo'
  // where the user grants access; [challenge] is the PKCE S256 challenge
  String authUrl({required String state, required String challenge, required String redirectUrl});
  Future<DepotTokens> exchange({required String code, required String verifier, required String redirectUrl});
  Future<DepotTokens> refresh(DepotTokens tokens);
  Future<List<DepotPosition>> positions(DepotTokens tokens);
}

// PKCE: a random verifier and its SHA-256 challenge, both base64url
({String verifier, String challenge}) pkce() {
  final rnd = math.Random.secure();
  final verifier = base64Url.encode(List.generate(48, (_) => rnd.nextInt(256))).replaceAll('=', '');
  final challenge = base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');
  return (verifier: verifier, challenge: challenge);
}

class ParqetConnect implements DepotProvider {
  static const _base = 'https://connect.parqet.com';
  final String clientId;
  final String clientSecret; // optional; Parqet's own examples use PKCE without one
  ParqetConnect(this.clientId, [this.clientSecret = '']);

  @override
  String get mode => 'live';

  @override
  String authUrl({required String state, required String challenge, required String redirectUrl}) =>
      Uri.parse('$_base/oauth2/authorize').replace(queryParameters: {
        'client_id': clientId,
        'redirect_uri': redirectUrl,
        'response_type': 'code',
        'scope': 'portfolio:read',
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'state': state,
      }).toString();

  Future<DepotTokens> _token(Map<String, String> form) async {
    final res = await http.post(Uri.parse('$_base/oauth2/token'), body: {
      ...form,
      'client_id': clientId,
      if (clientSecret.isNotEmpty) 'client_secret': clientSecret,
    });
    if (res.statusCode != 200) throw Exception('Parqet hat die Anmeldung abgelehnt (${res.statusCode})');
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    final seconds = (m['expires_in'] as num?)?.toInt() ?? 3600;
    return DepotTokens('${m['access_token']}', m['refresh_token'] as String?,
        DateTime.now().add(Duration(seconds: seconds - 60)));
  }

  @override
  Future<DepotTokens> exchange({required String code, required String verifier, required String redirectUrl}) =>
      _token({'grant_type': 'authorization_code', 'code': code, 'code_verifier': verifier, 'redirect_uri': redirectUrl});

  @override
  Future<DepotTokens> refresh(DepotTokens tokens) {
    if (tokens.refresh == null) throw Exception('Parqet-Freigabe abgelaufen. Bitte neu verbinden.');
    return _token({'grant_type': 'refresh_token', 'refresh_token': tokens.refresh!});
  }

  Future<Map<String, dynamic>> _call(String method, String path, DepotTokens t, [Object? body]) async {
    final headers = {'Authorization': 'Bearer ${t.access}', 'Content-Type': 'application/json'};
    final uri = Uri.parse('$_base$path');
    final res = method == 'GET'
        ? await http.get(uri, headers: headers)
        : await http.post(uri, headers: headers, body: jsonEncode(body));
    if (res.statusCode == 401) throw const DepotAuthExpired();
    if (res.statusCode != 200) throw Exception('Parqet antwortet gerade nicht (${res.statusCode})');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  @override
  Future<List<DepotPosition>> positions(DepotTokens tokens) async {
    final portfolios = ((await _call('GET', '/portfolios', tokens))['items'] as List? ?? []).cast<Map>();
    if (portfolios.isEmpty) return const [];
    final perf = await _call('POST', '/performance', tokens, {
      'portfolioIds': [for (final p in portfolios) p['id']],
      'interval': {'type': 'relative', 'value': 'max'},
      'currency': 'EUR',
    });
    // the brokers behind the portfolios for display, e.g. "Trade Republic"
    // (performance holdings do not say which portfolio they belong to)
    final broker = {for (final p in portfolios) ...((p['distinctBrokers'] as List?) ?? const []).map((b) => '$b')}
        .join(', ');
    final out = <DepotPosition>[];
    for (final h in (perf['holdings'] as List? ?? []).cast<Map>()) {
      final pos = (h['position'] as Map?) ?? const {};
      final shares = (pos['shares'] as num?)?.toDouble() ?? 0;
      if (pos['isSold'] == true || shares <= 0) continue;
      final asset = (h['asset'] as Map?) ?? const {};
      final kind = '${asset['type']}';
      if (kind == 'cash') continue;
      final name = '${h['nickname'] ?? asset['name'] ?? 'Position'}';
      final isin = '${asset['isin'] ?? ''}';
      final symbol = kind == 'crypto' ? '${asset['symbol'] ?? ''}' : '';
      out.add(DepotPosition(
        isin.isNotEmpty ? isin : (symbol.isNotEmpty ? symbol : '${h['id']}'),
        name,
        symbol,
        _type(kind, name),
        shares,
        (((pos['purchasePrice'] as num?) ?? 0) * 100).round(),
        (((pos['currentPrice'] as num?) ?? 0) * 100).round(),
        broker,
      ));
    }
    return out;
  }

  static String _type(String kind, String name) {
    if (kind == 'crypto') return 'Krypto';
    if (kind == 'commodity') return 'Sonstiges';
    final n = name.toLowerCase();
    if (n.contains('etf') || n.contains('ishares') || n.contains('msci') || n.contains('xtrackers') ||
        n.contains('vanguard') || n.contains('ucits')) {
      return 'ETF';
    }
    return 'Aktie';
  }
}

class DepotAuthExpired implements Exception {
  const DepotAuthExpired();
}

// A pretend Parqet with a typical Trade Republic depot. Prices drift a little
// per day so a sync visibly updates them.
class DemoDepot implements DepotProvider {
  final String serverUrl;
  DemoDepot(this.serverUrl);

  @override
  String get mode => 'demo';

  @override
  String authUrl({required String state, required String challenge, required String redirectUrl}) =>
      '$serverUrl/depot/demo-consent?state=${Uri.encodeQueryComponent(state)}';

  @override
  Future<DepotTokens> exchange({required String code, required String verifier, required String redirectUrl}) async =>
      DepotTokens('demo-$code', 'demo-refresh', DateTime.now().add(const Duration(days: 365)));

  @override
  Future<DepotTokens> refresh(DepotTokens tokens) async => tokens;

  static const _demo = [
    // id, name, symbol, type, shares, buy, price (cents)
    ('IE00B4L5Y983', 'iShares Core MSCI World', '', 'ETF', 84.2316, 8245, 10890),
    ('IE00BKM4GZ66', 'iShares Core MSCI EM IMI', '', 'ETF', 61.5, 2950, 3412),
    ('US0378331005', 'Apple', '', 'Aktie', 6.0, 15420, 21980),
    ('US67066G1040', 'NVIDIA', '', 'Aktie', 12.0, 9810, 16540),
    ('DE0007164600', 'SAP', '', 'Aktie', 4.0, 17230, 24610),
    ('BTC', 'Bitcoin', 'BTC', 'Krypto', 0.0142, 5480000, 9450000),
  ];

  @override
  Future<List<DepotPosition>> positions(DepotTokens tokens) async {
    final day = DateTime.now().difference(DateTime(2026)).inDays;
    return [
      for (final (i, d) in _demo.indexed)
        DepotPosition(d.$1, d.$2, d.$3, d.$4, d.$5, d.$6,
            (d.$7 * (1 + 0.01 * math.sin(day * 0.7 + i))).round(), 'Trade Republic'),
    ];
  }
}
