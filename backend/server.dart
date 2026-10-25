// BudgetBuddy backend — a small local proxy so the app can link a real bank
// account (GoCardless / PSD2) and depot (Parqet) without ever holding secrets
// in the client. Run with:
//
//   dart run backend/server.dart
//
// Configure via environment variables (never commit these):
//   GOCARDLESS_SECRET_ID, GOCARDLESS_SECRET_KEY   (free: bankaccountdata.gocardless.com)
//   PARQET_TOKEN, PARQET_PORTFOLIO_ID             (optional, for the depot)
//   PORT                                          (default 8090)
//
// All responses carry permissive CORS headers so the Flutter web app on
// localhost can call it. For production this same service goes behind HTTPS.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const _gcBase = 'https://bankaccountdata.gocardless.com/api/v2';
const _parqetBase = 'https://api.parqet.com/v1';

String _env(String k) => Platform.environment[k] ?? '';

Future<void> main() async {
  final port = int.tryParse(_env('PORT')) ?? 8090;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  stdout.writeln('BudgetBuddy backend on http://localhost:$port');
  stdout.writeln('  GoCardless: ${_env('GOCARDLESS_SECRET_ID').isEmpty ? 'NOT configured' : 'configured'}');
  stdout.writeln('  Parqet:     ${_env('PARQET_TOKEN').isEmpty ? 'NOT configured' : 'configured'}');

  await for (final req in server) {
    try {
      await _handle(req);
    } catch (e) {
      await _json(req, 500, {'error': '$e'});
    }
  }
}

void _cors(HttpResponse res) {
  res.headers
    ..set('Access-Control-Allow-Origin', '*')
    ..set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
    ..set('Access-Control-Allow-Headers', 'Content-Type');
}

Future<void> _json(HttpRequest req, int status, Object body) async {
  _cors(req.response);
  req.response
    ..statusCode = status
    ..headers.contentType = ContentType.json;
  req.response.write(jsonEncode(body));
  await req.response.close();
}

Future<void> _handle(HttpRequest req) async {
  if (req.method == 'OPTIONS') {
    _cors(req.response);
    req.response.statusCode = 204;
    await req.response.close();
    return;
  }

  final path = req.uri.path;
  switch (path) {
    case '/health':
      return _json(req, 200, {
        'ok': true,
        'gocardless': _env('GOCARDLESS_SECRET_ID').isNotEmpty,
        'parqet': _env('PARQET_TOKEN').isNotEmpty,
      });
    case '/gc/institutions':
      return _institutions(req);
    case '/gc/requisition':
      return _createRequisition(req);
    case '/gc/transactions':
      return _transactions(req);
    case '/parqet/portfolio':
      return _parqetPortfolio(req);
    default:
      return _json(req, 404, {'error': 'unknown endpoint: $path'});
  }
}

// --- GoCardless (PSD2 bank account data) ---

String? _gcToken;
DateTime _gcTokenExp = DateTime.fromMillisecondsSinceEpoch(0);

Future<String> _gcAccessToken() async {
  if (_gcToken != null && DateTime.now().isBefore(_gcTokenExp)) return _gcToken!;
  final id = _env('GOCARDLESS_SECRET_ID');
  final key = _env('GOCARDLESS_SECRET_KEY');
  if (id.isEmpty || key.isEmpty) {
    throw 'GoCardless not configured (set GOCARDLESS_SECRET_ID / GOCARDLESS_SECRET_KEY)';
  }
  final res = await http.post(
    Uri.parse('$_gcBase/token/new/'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'secret_id': id, 'secret_key': key}),
  );
  if (res.statusCode != 200) throw 'GoCardless token failed: ${res.statusCode} ${res.body}';
  final map = jsonDecode(res.body) as Map<String, dynamic>;
  _gcToken = map['access'] as String;
  _gcTokenExp = DateTime.now().add(const Duration(hours: 20));
  return _gcToken!;
}

Future<Map<String, String>> _gcHeaders() async =>
    {'Authorization': 'Bearer ${await _gcAccessToken()}', 'Content-Type': 'application/json'};

// GET /gc/institutions?country=DE
Future<void> _institutions(HttpRequest req) async {
  final country = req.uri.queryParameters['country'] ?? 'DE';
  final res = await http.get(Uri.parse('$_gcBase/institutions/?country=$country'),
      headers: await _gcHeaders());
  if (res.statusCode != 200) return _json(req, res.statusCode, {'error': res.body});
  final list = (jsonDecode(res.body) as List)
      .map((e) => {'id': e['id'], 'name': e['name'], 'logo': e['logo']})
      .toList();
  return _json(req, 200, {'institutions': list});
}

// POST /gc/requisition  {institutionId, redirect}
Future<void> _createRequisition(HttpRequest req) async {
  final body = jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>;
  final institutionId = body['institutionId'];
  final redirect = body['redirect'] ?? 'http://localhost:8123';
  final res = await http.post(Uri.parse('$_gcBase/requisitions/'),
      headers: await _gcHeaders(),
      body: jsonEncode({'institution_id': institutionId, 'redirect': redirect}));
  if (res.statusCode >= 300) return _json(req, res.statusCode, {'error': res.body});
  final map = jsonDecode(res.body) as Map<String, dynamic>;
  return _json(req, 200, {'requisitionId': map['id'], 'link': map['link']});
}

// GET /gc/transactions?requisitionId=...  -> normalized booked transactions
Future<void> _transactions(HttpRequest req) async {
  final reqId = req.uri.queryParameters['requisitionId'];
  if (reqId == null) return _json(req, 400, {'error': 'requisitionId required'});
  final headers = await _gcHeaders();

  final rq = await http.get(Uri.parse('$_gcBase/requisitions/$reqId/'), headers: headers);
  if (rq.statusCode != 200) return _json(req, rq.statusCode, {'error': rq.body});
  final accounts = ((jsonDecode(rq.body) as Map)['accounts'] as List?) ?? [];

  final out = <Map<String, dynamic>>[];
  for (final acc in accounts) {
    final tr = await http.get(Uri.parse('$_gcBase/accounts/$acc/transactions/'), headers: headers);
    if (tr.statusCode != 200) continue;
    final booked = (((jsonDecode(tr.body) as Map)['transactions'] as Map?)?['booked'] as List?) ?? [];
    for (final t in booked) {
      final amount = double.tryParse('${t['transactionAmount']?['amount']}') ?? 0;
      out.add({
        'date': t['bookingDate'] ?? t['valueDate'],
        'amountCents': (amount * 100).round(),
        'description': t['remittanceInformationUnstructured'] ??
            (t['creditorName'] ?? t['debtorName'] ?? ''),
      });
    }
  }
  return _json(req, 200, {'transactions': out});
}

// --- Parqet (depot) ---

// GET /parqet/portfolio -> holdings + total value
Future<void> _parqetPortfolio(HttpRequest req) async {
  final token = _env('PARQET_TOKEN');
  final id = req.uri.queryParameters['id'].toString().isNotEmpty
      ? req.uri.queryParameters['id']!
      : _env('PARQET_PORTFOLIO_ID');
  if (token.isEmpty) return _json(req, 400, {'error': 'Parqet not configured (set PARQET_TOKEN)'});
  if (id.isEmpty) return _json(req, 400, {'error': 'portfolio id required (PARQET_PORTFOLIO_ID or ?id=)'});

  final res = await http.get(Uri.parse('$_parqetBase/portfolios/$id'),
      headers: {'Authorization': 'Bearer $token'});
  if (res.statusCode != 200) return _json(req, res.statusCode, {'error': res.body});

  // Parqet's exact shape can vary by plan; pass through the holdings/value we find.
  final map = jsonDecode(res.body) as Map<String, dynamic>;
  final holdings = (map['holdings'] as List?) ?? (map['positions'] as List?) ?? [];
  final out = holdings.map((h) {
    final name = h['name'] ?? h['assetName'] ?? h['asset']?['name'];
    final shares = (h['shares'] ?? h['quantity'] ?? 0) as num;
    final value = (h['value'] ?? h['marketValue'] ?? 0) as num;
    return {
      'name': name,
      'shares': shares.toDouble(),
      'valueCents': (value * 100).round(),
    };
  }).toList();
  return _json(req, 200, {'holdings': out, 'raw': map['totalValue'] ?? map['value']});
}
