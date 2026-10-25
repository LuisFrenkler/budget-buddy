// BudgetBuddy backend — a small local server so the app can link a real bank
// account (Enable Banking / PSD2) and a Parqet depot without ever holding
// secrets in the client. Run it from this folder:
//
//   dart pub get
//   dart run server.dart
//
// Configure via environment variables (never commit these):
//   EB_APP_ID, EB_PRIVATE_KEY_PATH   Enable Banking app id and its .pem key.
//                                    Without them the server runs a demo bank.
//   EB_REDIRECT_URL                  whitelisted redirect (default <PUBLIC_URL>/bank/callback)
//   PARQET_TOKEN, PARQET_PORTFOLIO_ID  optional, for the depot
//   PORT (default 8090), PUBLIC_URL (default http://localhost:<PORT>)
//
// The server only listens on localhost. Users sign in with email and
// password (see lib/accounts.dart); every bank link belongs to one user and
// is identified by a random "state" token. Data survives restarts in .data/.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'lib/accounts.dart';
import 'lib/bank_provider.dart';
import 'lib/demo_bank.dart';
import 'lib/enable_banking.dart';

const _parqetBase = 'https://api.parqet.com/v1';

String _env(String k) => Platform.environment[k] ?? '';

late final BankProvider _bank;
late final String _publicUrl;
late final String _redirectUrl;

// consent started but not finished yet: state -> (bank name, owner id)
final _pending = <String, ({String bank, String owner})>{};
// consent failed: state -> message
final _failed = <String, String>{};
// linked banks: state -> session
final _sessions = <String, Map<String, dynamic>>{};
final _dataDir = '${File.fromUri(Platform.script).parent.path}/.data';
final _store = File('$_dataDir/sessions.json');
final _accounts = Accounts(File('$_dataDir/users.json'));

Future<void> main() async {
  final port = int.tryParse(_env('PORT')) ?? 8090;
  _publicUrl = _env('PUBLIC_URL').isNotEmpty ? _env('PUBLIC_URL') : 'http://localhost:$port';
  _redirectUrl = _env('EB_REDIRECT_URL').isNotEmpty ? _env('EB_REDIRECT_URL') : '$_publicUrl/bank/callback';

  final keyPath = _env('EB_PRIVATE_KEY_PATH');
  if (_env('EB_APP_ID').isNotEmpty && keyPath.isNotEmpty) {
    _bank = EnableBanking(appId: _env('EB_APP_ID'), privateKeyPem: await File(keyPath).readAsString());
  } else {
    _bank = DemoBank(_publicUrl);
  }
  await _load();
  await _accounts.load();

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  stdout.writeln('BudgetBuddy backend on $_publicUrl');
  stdout.writeln('  Bank:   ${_bank.mode == 'live' ? 'Enable Banking (live)' : 'Demo-Bank (set EB_APP_ID + EB_PRIVATE_KEY_PATH for real banks)'}');
  stdout.writeln('  Parqet: ${_env('PARQET_TOKEN').isEmpty ? 'not configured' : 'configured'}');

  await for (final req in server) {
    try {
      await _handle(req);
    } on AuthError catch (e) {
      await _json(req, e.status, {'error': e.message});
    } catch (e) {
      await _json(req, 500, {'error': '$e'});
    }
  }
}

Future<void> _load() async {
  if (!await _store.exists()) return;
  final map = jsonDecode(await _store.readAsString()) as Map<String, dynamic>;
  map.forEach((k, v) => _sessions[k] = (v as Map).cast<String, dynamic>());
}

Future<void> _save() async {
  await _store.parent.create(recursive: true);
  await _store.writeAsString(jsonEncode(_sessions));
}

String _newState() {
  final rnd = math.Random.secure();
  return List.generate(16, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

void _cors(HttpResponse res) {
  res.headers
    ..set('Access-Control-Allow-Origin', '*')
    ..set('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS')
    ..set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
}

Future<void> _json(HttpRequest req, int status, Object body) async {
  _cors(req.response);
  req.response
    ..statusCode = status
    ..headers.contentType = ContentType.json;
  req.response.write(jsonEncode(body));
  await req.response.close();
}

Future<void> _html(HttpRequest req, String body) async {
  req.response.headers.contentType = ContentType.html;
  req.response.write(_page(body));
  await req.response.close();
}

Future<Map<String, dynamic>> _body(HttpRequest req) async {
  final text = await utf8.decodeStream(req);
  return text.isEmpty ? {} : jsonDecode(text) as Map<String, dynamic>;
}

String? _bearer(HttpRequest req) {
  final h = req.headers.value('authorization') ?? '';
  return h.startsWith('Bearer ') ? h.substring(7) : null;
}

// the signed-in user; throws 401 when the token is missing or expired
Map<String, dynamic> _user(HttpRequest req) {
  final u = _accounts.userFor(_bearer(req));
  if (u == null) throw const AuthError(401, 'Bitte melde dich erneut an.');
  return u;
}

// a linked bank of the signed-in user; throws 404 for anyone else's
Map<String, dynamic> _ownSession(HttpRequest req, String state) {
  final user = _user(req);
  final s = _sessions[state];
  if (s == null || s['owner'] != user['id']) throw const AuthError(404, 'Keine Verbindung gefunden. Bitte neu verbinden.');
  return s;
}

Future<void> _handle(HttpRequest req) async {
  if (req.method == 'OPTIONS') {
    _cors(req.response);
    req.response.statusCode = 204;
    await req.response.close();
    return;
  }

  final q = req.uri.queryParameters;
  switch (req.uri.path) {
    case '/health':
      return _json(req, 200, {'ok': true, 'bank': _bank.mode, 'parqet': _env('PARQET_TOKEN').isNotEmpty});
    case '/auth/register':
      final b = await _body(req);
      return _json(req, 200,
          await _accounts.register(email: '${b['email'] ?? ''}', password: '${b['password'] ?? ''}', name: '${b['name'] ?? ''}'));
    case '/auth/login':
      final b = await _body(req);
      return _json(req, 200, await _accounts.login(email: '${b['email'] ?? ''}', password: '${b['password'] ?? ''}'));
    case '/auth/me':
      return _json(req, 200, {'user': Accounts.public(_user(req))});
    case '/auth/logout':
      final token = _bearer(req);
      if (token != null) await _accounts.logout(token);
      return _json(req, 200, {'ok': true});
    case '/auth/account':
      if (req.method != 'DELETE') return _json(req, 405, {'error': 'DELETE only'});
      return _deleteAccount(req);
    case '/bank/institutions':
      return _json(req, 200, {'institutions': await _bank.institutions(q['country'] ?? 'DE')});
    case '/bank/connect':
      return _connect(req);
    case '/bank/demo-consent':
      return _demoConsent(req);
    case '/bank/callback':
      return _callback(req);
    case '/bank/status':
      return _status(req);
    case '/bank/sync':
      return _sync(req);
    case '/bank/disconnect':
      return _disconnect(req);
    case '/parqet/portfolio':
      return _parqetPortfolio(req);
    default:
      return _json(req, 404, {'error': 'unknown endpoint: ${req.uri.path}'});
  }
}

// --- bank ---

// POST {institution, country} -> {state, link}
Future<void> _connect(HttpRequest req) async {
  final user = _user(req);
  final body = await _body(req);
  final institution = '${body['institution'] ?? ''}';
  if (institution.isEmpty) return _json(req, 400, {'error': 'institution required'});
  final state = _newState();
  final link = await _bank.startAuth(
    institution: institution,
    country: '${body['country'] ?? 'DE'}',
    state: state,
    redirectUrl: _redirectUrl,
  );
  _pending[state] = (bank: institution, owner: user['id'] as String);
  return _json(req, 200, {'state': state, 'link': link});
}

// the demo bank's "login": one button that grants access
Future<void> _demoConsent(HttpRequest req) {
  final state = req.uri.queryParameters['state'] ?? '';
  final bank = _escape(req.uri.queryParameters['bank'] ?? 'Demo-Bank');
  final ok = '/bank/callback?state=${Uri.encodeQueryComponent(state)}&code=${Uri.encodeQueryComponent(state)}';
  final no = '/bank/callback?state=${Uri.encodeQueryComponent(state)}&error=access_denied';
  return _html(req, '''
<div class="tag">DEMO · keine echten Daten</div>
<h1>$bank</h1>
<p>BudgetBuddy möchte <b>lesend</b> auf dein Girokonto zugreifen:</p>
<ul><li>Kontostand</li><li>Umsätze der letzten 90 Tage</li></ul>
<p class="dim">Bei einer echten Bank meldest du dich hier mit deinen Zugangsdaten an und bestätigst per App oder TAN.</p>
<a class="btn" href="$ok">Zugriff erlauben</a>
<a class="link" href="$no">Abbrechen</a>''');
}

// the bank redirects here with ?code=...&state=... (or ?error=...)
Future<void> _callback(HttpRequest req) async {
  final q = req.uri.queryParameters;
  final state = q['state'] ?? '';
  final pending = _pending[state];
  if (pending == null) {
    return _html(req, '<h1>Link abgelaufen</h1><p>Bitte starte die Verbindung in BudgetBuddy erneut.</p>');
  }
  if (q['code'] == null) {
    _pending.remove(state);
    _failed[state] = q['error_description'] ?? q['error'] ?? 'abgebrochen';
    return _html(req, '<h1>Nicht verbunden</h1><p>Der Zugriff wurde nicht erteilt. Du kannst dieses Fenster schließen.</p>');
  }
  try {
    final session = await _bank.createSession(q['code']!);
    final bankName = pending.bank;
    _sessions[state] = {
      'owner': pending.owner,
      'sessionId': session.id,
      'bank': bankName,
      'accounts': [for (final a in session.accounts) a.toJson()],
      'validUntil': session.validUntil.toIso8601String(),
    };
    _pending.remove(state);
    await _save();
    return _html(req, '''
<div class="check">✓</div>
<h1>Verbunden</h1>
<p>${_escape(bankName)} ist jetzt mit BudgetBuddy verbunden. Du kannst dieses Fenster schließen.</p>
<script>setTimeout(() => window.close(), 1500)</script>''');
  } catch (e) {
    _pending.remove(state);
    _failed[state] = '$e';
    return _html(req, '<h1>Fehler</h1><p>${_escape('$e')}</p>');
  }
}

// GET ?state= -> {status: pending|linked|failed|unknown, ...}
Future<void> _status(HttpRequest req) {
  final user = _user(req);
  final state = req.uri.queryParameters['state'] ?? '';
  final s = _sessions[state];
  if (s != null && s['owner'] == user['id']) {
    return _json(req, 200, {
      'status': 'linked',
      'bank': s['bank'],
      'accounts': s['accounts'],
      'validUntil': s['validUntil'],
      'mode': _bank.mode,
    });
  }
  if (_pending[state]?.owner == user['id']) return _json(req, 200, {'status': 'pending'});
  if (_failed.containsKey(state)) return _json(req, 200, {'status': 'failed', 'error': _failed[state]});
  return _json(req, 200, {'status': 'unknown'});
}

// GET ?state=&days=90 -> {balanceCents, transactions} over all accounts
Future<void> _sync(HttpRequest req) async {
  final q = req.uri.queryParameters;
  final s = _ownSession(req, q['state'] ?? '');
  final days = (int.tryParse(q['days'] ?? '') ?? 90).clamp(1, 730);
  final from = DateTime.now().subtract(Duration(days: days));

  int balance = 0;
  final txs = <Map<String, dynamic>>[];
  for (final a in (s['accounts'] as List)) {
    final uid = (a as Map)['uid'] as String;
    balance += await _bank.balance(uid);
    for (final t in await _bank.transactions(uid, from)) {
      // prefix the account so ids stay unique across accounts
      txs.add(t.toJson()..['id'] = '$uid:${t.id}');
    }
  }
  return _json(req, 200, {'bank': s['bank'], 'balanceCents': balance, 'transactions': txs});
}

// POST {state}
Future<void> _disconnect(HttpRequest req) async {
  final state = '${(await _body(req))['state'] ?? ''}';
  _ownSession(req, state);
  final s = _sessions.remove(state);
  if (s != null) {
    await _save();
    try {
      await _bank.endSession(s['sessionId'] as String);
    } catch (_) {
      // the consent is gone from our side either way
    }
  }
  return _json(req, 200, {'ok': true});
}

// DELETE /auth/account: the user, their sign-ins and every bank link
Future<void> _deleteAccount(HttpRequest req) async {
  final user = _user(req);
  final own = _sessions.entries.where((e) => e.value['owner'] == user['id']).toList();
  for (final e in own) {
    _sessions.remove(e.key);
    try {
      await _bank.endSession(e.value['sessionId'] as String);
    } catch (_) {
      // revoked locally either way
    }
  }
  await _save();
  await _accounts.delete(user['id'] as String);
  return _json(req, 200, {'ok': true});
}

// --- Parqet (depot) ---

// GET /parqet/portfolio -> holdings + total value
Future<void> _parqetPortfolio(HttpRequest req) async {
  _user(req);
  final token = _env('PARQET_TOKEN');
  final id = req.uri.queryParameters['id'] ?? _env('PARQET_PORTFOLIO_ID');
  if (token.isEmpty) return _json(req, 400, {'error': 'Parqet nicht eingerichtet (PARQET_TOKEN fehlt)'});
  if (id.isEmpty) return _json(req, 400, {'error': 'Portfolio-ID fehlt (PARQET_PORTFOLIO_ID oder ?id=)'});

  final res = await http.get(Uri.parse('$_parqetBase/portfolios/$id'), headers: {'Authorization': 'Bearer $token'});
  if (res.statusCode != 200) return _json(req, res.statusCode, {'error': res.body});

  // Parqet's exact shape can vary by plan; pass through the holdings/value we find.
  final map = jsonDecode(res.body) as Map<String, dynamic>;
  final holdings = (map['holdings'] as List?) ?? (map['positions'] as List?) ?? [];
  final out = holdings.map((h) {
    final name = h['name'] ?? h['assetName'] ?? h['asset']?['name'];
    final shares = (h['shares'] ?? h['quantity'] ?? 0) as num;
    final value = (h['value'] ?? h['marketValue'] ?? 0) as num;
    return {'name': name, 'shares': shares.toDouble(), 'valueCents': (value * 100).round()};
  }).toList();
  return _json(req, 200, {'holdings': out});
}

// --- html ---

String _escape(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

String _page(String body) => '''<!doctype html>
<html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>BudgetBuddy</title>
<style>
  body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;
       background:#0b0b10;color:#f2f4f7;font:16px/1.5 -apple-system,BlinkMacSystemFont,Inter,sans-serif}
  main{max-width:380px;padding:32px 24px}
  h1{font-size:28px;margin:8px 0 12px}
  p{color:#c9ced6}.dim{color:#7d8590;font-size:14px}
  ul{color:#c9ced6;padding-left:20px}
  .tag{display:inline-block;font-size:12px;font-weight:700;letter-spacing:.5px;color:#f5b84c;
       background:rgba(245,184,76,.12);padding:4px 10px;border-radius:999px}
  .btn{display:block;text-align:center;background:#7c5cff;color:#fff;font-weight:700;
       padding:14px;border-radius:14px;text-decoration:none;margin-top:24px}
  .link{display:block;text-align:center;color:#7d8590;margin-top:14px;text-decoration:none}
  .check{width:56px;height:56px;border-radius:50%;background:rgba(124,92,255,.18);color:#a48bff;
         display:flex;align-items:center;justify-content:center;font-size:28px;font-weight:800}
</style></head><body><main>$body</main></body></html>''';
