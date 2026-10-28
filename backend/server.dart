// BudgetBuddy backend — a small local server so the app can link a real bank
// account (Enable Banking / PSD2) and a depot (Parqet Connect) without ever holding
// secrets in the client. Run it from this folder:
//
//   dart pub get
//   dart run server.dart
//
// Configure via environment variables or a backend/.env file with KEY=value
// lines (git-ignored; real environment variables win). Never commit these:
//   EB_APP_ID, EB_PRIVATE_KEY_PATH   Enable Banking app id and its .pem key.
//                                    Without them the server runs a demo bank.
//   EB_REDIRECT_URL                  whitelisted redirect (default <PUBLIC_URL>/bank/callback)
//   ANTHROPIC_API_KEY                optional, enables the AI features (lib/ai.dart)
//   GEMINI_API_KEY, GEMINI_MODEL     optional, the free alternative when no Anthropic key is set
//   PARQET_CLIENT_ID                 Parqet Connect integration (depot sync, lib/depot.dart).
//   PARQET_CLIENT_SECRET             only if the integration has one.
//                                    Without the id the server runs a demo depot.
//   PARQET_REDIRECT_URL              whitelisted redirect (default <PUBLIC_URL>/depot/callback)
//   STRIPE_SECRET_KEY                Plus payments on the web (lib/billing.dart). Without it
//                                    the server runs a demo checkout that never charges.
//   STRIPE_PRICE_MONTHLY, STRIPE_PRICE_YEARLY  the two Stripe price ids
//   STRIPE_WEBHOOK_SECRET            optional, for /stripe/webhook (whsec_...)
//   APPLE_BUNDLE_ID, APPLE_ISSUER_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY_PATH
//                                    Plus bought in the iPhone app (lib/store_billing.dart):
//                                    an In-App Purchase key (.p8) from App Store Connect.
//   GOOGLE_PACKAGE_NAME, GOOGLE_SERVICE_ACCOUNT_PATH
//                                    Plus bought in the Android app: a service account
//                                    JSON key with access to the app in the Play Console.
//                                    Without them purchases from that store are refused.
//   PLUS_PRODUCT_MONTHLY, PLUS_PRODUCT_YEARLY  store product ids (default
//                                    budgetbuddy_plus_monthly / budgetbuddy_plus_yearly)
//   WHATSAPP_TOKEN, WHATSAPP_PHONE_ID, WHATSAPP_VERIFY_TOKEN
//                                    optional WhatsApp Cloud API (lib/whatsapp.dart).
//                                    Without them the routes answer but send nothing.
//                                    Numbers are stored as a hash; opt-in required.
//   PORT (default 8090), PUBLIC_URL (default http://localhost:<PORT>)
//   BIND (default 127.0.0.1)         set to 0.0.0.0 behind a reverse proxy
//   HTTPS_PORT (default 8443)        with a certificate in .data/tls (see README), the
//                                    server also answers on https://localhost:<HTTPS_PORT>,
//                                    for providers that only redirect to https
//
// Default: localhost only. For hosting set BIND=0.0.0.0 + HTTPS via a proxy.
// Users sign in with email and password (see lib/accounts.dart); every bank
// link belongs to one user. Data survives restarts in .data/.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';


// the app's legal texts, so app and web pages never drift apart
import '../lib/legal/legal_texts.dart';
import 'lib/accounts.dart';
import 'lib/ai.dart';
import 'lib/bank_provider.dart';
import 'lib/billing.dart';
import 'lib/store_billing.dart';
import 'lib/demo_bank.dart';
import 'lib/depot.dart';
import 'lib/market.dart';
import 'lib/enable_banking.dart';
import 'lib/json_store.dart';
import 'lib/rate_limit.dart';
import 'lib/vault.dart';
import 'lib/splits.dart';
import 'lib/net.dart';
import 'lib/whatsapp.dart';

String _env(String k) => Platform.environment[k] ?? _dotEnv[k] ?? '';

// backend/.env, read once at start
final Map<String, String> _dotEnv = () {
  final file = File('${File.fromUri(Platform.script).parent.path}/.env');
  if (!file.existsSync()) return <String, String>{};
  return {
    for (final line in file.readAsLinesSync())
      if (line.contains('=') && !line.trimLeft().startsWith('#'))
        line.substring(0, line.indexOf('=')).trim(): line.substring(line.indexOf('=') + 1).trim(),
  };
}();

late final BankProvider _bank;
late final String _publicUrl;
late final String _redirectUrl;
late final DepotProvider _depot;
late final String _depotRedirect;
late final Billing _billing;
late final StoreBilling _stores;

// consent started but not finished yet: state -> (bank name, owner id)
final _pending = <String, ({String bank, String owner})>{};
// consent failed: state -> (owner, message) — owner-scoped so others cannot probe
final _failed = <String, ({String owner, String error})>{};
// linked banks: state -> session
final _sessions = <String, Map<String, dynamic>>{};
final _dataDir = '${File.fromUri(Platform.script).parent.path}/.data';
final _store = File('$_dataDir/sessions.json');
// linked depots: state -> {owner, tokens, linkedAt, portfolioIds}; consent in progress
final _depots = <String, Map<String, dynamic>>{};
final _depotPending = <String, ({String owner, String verifier})>{};
final _depotFailed = <String, ({String owner, String error})>{};
// failed logins and new accounts per address
final _loginLimit = RateLimit(20, const Duration(minutes: 15));
final _registerLimit = RateLimit(10, const Duration(hours: 1));
final _chartLimit = RateLimit(60, const Duration(minutes: 1));
final _marketLimit = RateLimit(60, const Duration(minutes: 1));
final _storeLimit = RateLimit(30, const Duration(minutes: 1));
final _lookupLimit = RateLimit(20, const Duration(minutes: 15));
final _lookupUserLimit = RateLimit(10, const Duration(minutes: 15));
final _aiIpLimit = RateLimit(40, const Duration(minutes: 1));
final _institutionsLimit = RateLimit(30, const Duration(minutes: 1));
final _waLimit = RateLimit(120, const Duration(minutes: 1));
final _waLinkLimit = RateLimit(10, const Duration(hours: 1));

// production hardening
var _inflight = 0;
const _maxInflight = 100;
var _publicBind = false; // true when BIND is not loopback
var _shuttingDown = false;
HttpServer? _httpServer;
HttpServer? _httpsServer;
final _stripeSeen = <String>{}; // webhook event ids (idempotency)
final _stripeSeenStore = File('${File.fromUri(Platform.script).parent.path}/.data/stripe_events.json');

// Rate limits key off the peer address. X-Forwarded-For is only trusted when
// TRUST_PROXY=1 (reverse proxy in front); otherwise clients could rotate IPs.
String _clientIp(HttpRequest req) {
  final peer = req.connectionInfo?.remoteAddress.address ?? 'unknown';
  if (_env('TRUST_PROXY') != '1') return peer;
  final forwarded = req.headers.value('x-forwarded-for');
  if (forwarded == null || forwarded.trim().isEmpty) return peer;
  // first hop is the original client when the proxy appends
  return forwarded.split(',').first.trim();
}

// when each consent above began: abandoned ones are dropped after an hour
final _started = <String, DateTime>{};

void _dropAbandoned() {
  final cutoff = DateTime.now().subtract(const Duration(hours: 1));
  final old = [for (final e in _started.entries) if (e.value.isBefore(cutoff)) e.key];
  for (final state in old) {
    _started.remove(state);
    _pending.remove(state);
    _failed.remove(state);
    _depotPending.remove(state);
    _depotFailed.remove(state);
  }
}
final _depotStore = File('$_dataDir/depots.json');
final _vault = Vault('$_dataDir/vault');
final _symbols = SymbolLookup();
// who has Plus: user id -> entitlement
final _plus = <String, Entitlement>{};
final _plusStore = File('$_dataDir/plus.json');

// extra free days on top of the 7-day trial (the same codes as in the app)
const _trialDays = 7;
const _promoCodes = {'BUDDY30': 30, 'FREUND': 30, 'CREATOR60': 60, 'START14': 14};
final _accounts = Accounts(File('$_dataDir/users.json'));
final _splits = SharedSplits(File('$_dataDir/splits.json'));
final _whatsapp = WhatsApp(
  token: _env('WHATSAPP_TOKEN'),
  phoneId: _env('WHATSAPP_PHONE_ID'),
  verifyToken: _env('WHATSAPP_VERIFY_TOKEN'),
  store: File('$_dataDir/whatsapp.json'),
);
final _ai = Ai(_env('ANTHROPIC_API_KEY'), geminiKey: _env('GEMINI_API_KEY'), geminiModel: _env('GEMINI_MODEL'));

// AI calls cost money: at most this many per user and day
// about 5 cents a day at most per person with Haiku
const _aiDailyLimit = 50;
final _aiUsage = <String, ({String day, int count})>{};

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
  _depotRedirect =
      _env('PARQET_REDIRECT_URL').isNotEmpty ? _env('PARQET_REDIRECT_URL') : '$_publicUrl/depot/callback';
  _depot = _env('PARQET_CLIENT_ID').isNotEmpty
      ? ParqetConnect(_env('PARQET_CLIENT_ID'), _env('PARQET_CLIENT_SECRET'))
      : DemoDepot(_publicUrl);
  _billing = _env('STRIPE_SECRET_KEY').isNotEmpty
      ? StripeBilling(
          secretKey: _env('STRIPE_SECRET_KEY'),
          priceMonthly: _env('STRIPE_PRICE_MONTHLY'),
          priceYearly: _env('STRIPE_PRICE_YEARLY'))
      : DemoBilling(_publicUrl);
  _stores = await _storeBilling();
  await _load();
  await _accounts.load();
  await _splits.load();
  await _whatsapp.load();

  // 127.0.0.1 for local; BIND=0.0.0.0 when a reverse proxy terminates TLS
  final bindHost = _env('BIND').isNotEmpty ? _env('BIND') : InternetAddress.loopbackIPv4.address;
  _publicBind = bindHost != '127.0.0.1' && bindHost != '::1' && bindHost != 'localhost';
  if (_billing.mode == 'demo' && _publicBind && _env('ALLOW_DEMO_BILLING') != '1') {
    stdout.writeln('  WARN:   Demo-Plus is OFF on public bind (set ALLOW_DEMO_BILLING=1 or STRIPE_SECRET_KEY)');
  }
  await _loadStripeSeen();
  final server = await HttpServer.bind(bindHost, port);
  _httpServer = server;
  stdout.writeln('BudgetBuddy backend on $_publicUrl (bind $bindHost:$port)');
  final secure = await _bindHttps();
  if (secure != null) {
    _httpsServer = secure;
    stdout.writeln('  HTTPS:  https://localhost:${secure.port}');
    unawaited(_serve(secure));
  }
  stdout.writeln('  Bank:   ${_bank.mode == 'live' ? 'Enable Banking (live)' : 'Demo-Bank (set EB_APP_ID + EB_PRIVATE_KEY_PATH for real banks)'}');
  stdout.writeln('  KI:     ${_ai.enabled ? '${_ai.name} (live)' : 'not configured (set ANTHROPIC_API_KEY or GEMINI_API_KEY)'}');
  stdout.writeln('  Plus:   ${_billing.mode == 'live' ? 'Stripe (live)' : 'Demo-Checkout (set STRIPE_SECRET_KEY for real payments)'}');
  stdout.writeln('  Stores: ${_stores.mode.isEmpty ? 'not configured (App Store / Google Play purchases are refused)' : _stores.mode}');
  stdout.writeln('  Depot:  ${_depot.mode == 'live' ? 'Parqet Connect (live)' : 'Demo-Depot (set PARQET_CLIENT_ID for real depots)'}');
  stdout.writeln('  WhatsApp: ${_whatsapp.configured ? 'Cloud API (opt-in)' : 'not configured'}');

  // drain in-flight work on deploy / Ctrl-C
  for (final sig in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    sig.watch().listen((_) => unawaited(_shutdown()));
  }

  await _serve(server);
}

Future<void> _shutdown() async {
  if (_shuttingDown) return;
  _shuttingDown = true;
  stdout.writeln('Shutting down…');
  await _httpServer?.close(force: false);
  await _httpsServer?.close(force: false);
  // give in-flight handlers a moment to finish writes
  for (var i = 0; i < 50 && _inflight > 0; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  await _saveStripeSeen();
  exit(0);
}

Future<void> _loadStripeSeen() async {
  try {
    if (!await _stripeSeenStore.exists()) return;
    final list = jsonDecode(await _stripeSeenStore.readAsString());
    if (list is List) {
      for (final id in list.take(500)) {
        _stripeSeen.add('$id');
      }
    }
  } catch (_) {}
}

Future<void> _saveStripeSeen() async {
  final ids = _stripeSeen.length <= 500 ? _stripeSeen.toList() : _stripeSeen.skip(_stripeSeen.length - 500).toList();
  await writeJsonAtomic(_stripeSeenStore, ids);
}

// Demo Plus only on localhost, or when explicitly allowed — never free Plus on a public host by accident
void _requireBilling() {
  if (_billing.mode == 'live') return;
  if (_env('ALLOW_DEMO_BILLING') == '1') return;
  if (!_publicBind) return;
  throw const AuthError(503, 'Zahlungen sind noch nicht eingerichtet.');
}

// the same server on https, when .data/tls has a certificate (mkcert)
Future<HttpServer?> _bindHttps() async {
  final cert = File('$_dataDir/tls/localhost.pem');
  final key = File('$_dataDir/tls/localhost-key.pem');
  if (!await cert.exists() || !await key.exists()) return null;
  final context = SecurityContext()
    ..useCertificateChain(cert.path)
    ..usePrivateKey(key.path);
  final port = int.tryParse(_env('HTTPS_PORT')) ?? 8443;
  return HttpServer.bindSecure(InternetAddress.loopbackIPv4, port, context);
}

// every request runs on its own, so one slow upstream call (a Buddy stream,
// a bank sync) never makes the others wait — capped so one noisy client cannot
// exhaust the process
Future<void> _serve(HttpServer server) async {
  await for (final req in server) {
    if (_shuttingDown) {
      unawaited(_json(req, 503, {'error': 'Server fährt herunter.'}));
      continue;
    }
    if (_inflight >= _maxInflight) {
      unawaited(_json(req, 503, {'error': 'Server ausgelastet. Bitte gleich noch einmal.'}));
      continue;
    }
    _inflight++;
    unawaited(_handleSafe(req).whenComplete(() => _inflight--));
  }
}

String _requestId(HttpRequest req) {
  final incoming = req.headers.value('x-request-id')?.trim();
  if (incoming != null && incoming.isNotEmpty && incoming.length <= 64) return incoming;
  return _newState();
}

Future<void> _handleSafe(HttpRequest req) async {
  final id = _requestId(req);
  req.response.headers.set('X-Request-Id', id);
  final started = DateTime.now();
  var status = 500;
  try {
    try {
      await _handle(req);
      status = req.response.statusCode;
    } on AuthError catch (e) {
      status = e.status;
      await _json(req, e.status, {'error': e.message});
    } on BillingError catch (e) {
      status = 502;
      await _json(req, 502, {'error': e.message});
    } on AiError catch (e) {
      status = 502;
      stderr.writeln('{"id":"$id","path":"${req.uri.path}","err":${jsonEncode(e.message)}}');
      await _json(req, 502, {'error': e.message});
    } on TimeoutException {
      status = 504;
      await _json(req, 504, {'error': 'Der Dienst antwortet gerade nicht. Versuch es gleich noch einmal.'});
    } on FormatException {
      status = 400;
      await _json(req, 400, {'error': 'Ungültige Anfrage.'});
    } on TypeError {
      status = 400;
      await _json(req, 400, {'error': 'Ungültige Anfrage.'});
    } catch (e, st) {
      status = 500;
      stderr.writeln('{"id":"$id","method":"${req.method}","path":"${req.uri.path}","err":${jsonEncode('$e')}}\n$st');
      await _json(req, 500, {'error': 'Interner Fehler.'});
    }
  } catch (_) {
    // the response had already started or the client is gone; nothing to send
  } finally {
    final ms = DateTime.now().difference(started).inMilliseconds;
    if (status >= 400 || ms > 2000) {
      stdout.writeln('{"id":"$id","method":"${req.method}","path":"${req.uri.path}","status":$status,"ms":$ms}');
    }
  }
}

Future<void> _load() async {
  if (await _store.exists()) {
    final map = jsonDecode(await _store.readAsString()) as Map<String, dynamic>;
    map.forEach((k, v) => _sessions[k] = (v as Map).cast<String, dynamic>());
  }
  if (await _plusStore.exists()) {
    final map = jsonDecode(await _plusStore.readAsString()) as Map<String, dynamic>;
    map.forEach((k, v) => _plus[k] = Entitlement.fromJson(v as Map));
  }
  if (await _depotStore.exists()) {
    final map = jsonDecode(await _depotStore.readAsString()) as Map<String, dynamic>;
    map.forEach((k, v) => _depots[k] = (v as Map).cast<String, dynamic>());
  }
}

Future<void> _save() => writeJsonAtomic(_store, _sessions);

Future<void> _savePlus() =>
    writeJsonAtomic(_plusStore, {for (final e in _plus.entries) e.key: e.value.toJson()});

Future<void> _saveDepots() => writeJsonAtomic(_depotStore, _depots);

String _newState() {
  final rnd = math.Random.secure();
  return List.generate(16, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

void _securityHeaders(HttpResponse res) {
  res.headers
    ..set('X-Content-Type-Options', 'nosniff')
    ..set('Referrer-Policy', 'no-referrer')
    ..set('X-Frame-Options', 'DENY')
    ..set('Permissions-Policy', 'camera=(), microphone=(), geolocation=()');
}

// CORS_ORIGINS=https://app.example.com,http://localhost:8765 — empty keeps *
// only on loopback; public hosts without an allowlist send no ACAO (fail closed)
void _cors(HttpRequest req, HttpResponse res) {
  final origin = req.headers.value('origin');
  final raw = _env('CORS_ORIGINS').trim();
  if (raw.isEmpty) {
    if (!_publicBind) {
      res.headers.set('Access-Control-Allow-Origin', '*');
    } else if (origin != null && origin.isNotEmpty) {
      // public + no allowlist: reflect nothing (browser blocks). Local Flutter
      // apps are not browsers so Bearer calls still work.
    }
  } else {
    final allowed = {for (final o in raw.split(',')) o.trim()}.where((o) => o.isNotEmpty).toSet();
    if (origin != null && allowed.contains(origin)) {
      res.headers
        ..set('Access-Control-Allow-Origin', origin)
        ..set('Vary', 'Origin');
    }
  }
  res.headers
    ..set('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS')
    ..set('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Request-Id');
}

Future<void> _plain(HttpRequest req, int status, String body) async {
  _securityHeaders(req.response);
  req.response
    ..statusCode = status
    ..headers.contentType = ContentType.text
    ..write(body);
  await req.response.close();
}

Future<void> _json(HttpRequest req, int status, Object body) async {
  _cors(req, req.response);
  _securityHeaders(req.response);
  req.response
    ..statusCode = status
    ..headers.contentType = ContentType.json;
  req.response.write(jsonEncode(body));
  await req.response.close();
}

Future<void> _html(HttpRequest req, String body) async {
  _securityHeaders(req.response);
  req.response.headers
    ..contentType = ContentType.html
    ..set('Content-Security-Policy', "default-src 'none'; style-src 'unsafe-inline'; img-src 'self' data:; base-uri 'none'; form-action 'self'");
  req.response.write(_page(body));
  await req.response.close();
}

// receipts arrive as photos; everything else is small
Future<Map<String, dynamic>> _body(HttpRequest req) async {
  final limit = {'/ai/receipt', '/ai/entries', '/vault'}.contains(req.uri.path) ? 16 << 20 : 256 << 10;
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in req) {
    bytes.add(chunk);
    if (bytes.length > limit) throw AuthError(413, 'Die Anfrage ist zu groß.');
  }
  final text = utf8.decode(bytes.takeBytes());
  if (text.isEmpty) return {};
  final body = jsonDecode(text);
  if (body is! Map<String, dynamic>) throw const FormatException('body is no object');
  return body;
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
    _cors(req, req.response);
    _securityHeaders(req.response);
    req.response.statusCode = 204;
    await req.response.close();
    return;
  }

  final q = req.uri.queryParameters;
  switch (req.uri.path) {
    case '/health':
      // app reads aiProvider / feature modes from here
      return _json(req, 200, {
        'ok': true,
        'bank': _bank.mode,
        'ai': _ai.enabled,
        'aiProvider': _ai.enabled ? _ai.provider : null,
        'depot': _depot.mode,
        'billing': _billing.mode,
        'stores': _stores.mode,
      });
    case '/ready':
      // orchestrators: data dir must be writable
      try {
        final probe = File('$_dataDir/.ready');
        await probe.parent.create(recursive: true);
        await probe.writeAsString('${DateTime.now().toIso8601String()}', flush: true);
        return _json(req, 200, {'ok': true});
      } catch (_) {
        return _json(req, 503, {'ok': false, 'error': 'data dir not writable'});
      }
    case '/auth/register':
      final ip = _clientIp(req);
      if (_registerLimit.blocked(ip)) {
        final minutes = (_registerLimit.wait(ip).inSeconds / 60).ceil().clamp(1, 60);
        throw AuthError(429, 'Zu viele neue Konten von hier. Bitte versuch es in $minutes ${minutes == 1 ? 'Minute' : 'Minuten'} noch einmal.');
      }
      _registerLimit.hit(ip);
      final b = await _body(req);
      return _json(
          req,
          200,
          await _accounts.register(
              email: '${b['email'] ?? ''}',
              password: '${b['password'] ?? ''}',
              name: '${b['name'] ?? ''}',
              device: '${b['device'] ?? ''}'));
    case '/auth/login':
      // the per-email lockout stops guessing one password; this stops one
      // address from trying many accounts. A correct password on a 2FA
      // account is not a failure: the client still has to send the code.
      final ip = _clientIp(req);
      if (_loginLimit.blocked(ip)) throw AuthError.wait(_loginLimit.wait(ip));
      final b = await _body(req);
      try {
        final result = await _accounts.login(
            email: '${b['email'] ?? ''}', password: '${b['password'] ?? ''}', device: '${b['device'] ?? ''}');
        if (result['needsTotp'] == true) {
          return _json(req, 401, {
            'needsTotp': true,
            'challenge': result['challenge'],
            'error': 'Dieses Konto nutzt Zwei-Faktor. Bitte gib den Code aus der Authenticator-App ein.',
          });
        }
        return _json(req, 200, result);
      } on AuthError catch (e) {
        if (e.status == 401) _loginLimit.hit(ip);
        rethrow;
      }
    case '/auth/login/totp':
      final ip = _clientIp(req);
      if (_loginLimit.blocked(ip)) throw AuthError.wait(_loginLimit.wait(ip));
      final b = await _body(req);
      try {
        return _json(
            req,
            200,
            await _accounts.loginTotp(
                challenge: '${b['challenge'] ?? ''}', code: '${b['code'] ?? ''}', device: '${b['device'] ?? ''}'));
      } on AuthError catch (e) {
        if (e.status == 401) _loginLimit.hit(ip);
        rethrow;
      }
    case '/auth/me':
      return _json(req, 200, {'user': Accounts.public(_user(req))});
    case '/auth/logout':
      final token = _bearer(req);
      if (token != null) await _accounts.logout(token);
      return _json(req, 200, {'ok': true});
    case '/auth/logout-all':
      if (req.method != 'POST') return _json(req, 405, {'error': 'POST only'});
      await _accounts.logoutAll(_user(req)['id'] as String);
      return _json(req, 200, {'ok': true});
    case '/auth/sessions':
      if (req.method != 'GET') return _json(req, 405, {'error': 'GET only'});
      final user = _user(req);
      return _json(req, 200, {'sessions': _accounts.sessions(user['id'] as String, currentToken: _bearer(req))});
    case '/auth/sessions/revoke':
      if (req.method != 'POST') return _json(req, 405, {'error': 'POST only'});
      final user = _user(req);
      final b = await _body(req);
      await _accounts.revokeSession(user['id'] as String, '${b['id'] ?? ''}');
      return _json(req, 200, {'ok': true});
    case '/auth/totp/setup':
      if (req.method != 'POST') return _json(req, 405, {'error': 'POST only'});
      final user = _user(req);
      final b = await _body(req);
      return _json(req, 200, await _accounts.beginTotp(user['id'] as String, '${b['password'] ?? ''}'));
    case '/auth/totp/confirm':
      if (req.method != 'POST') return _json(req, 405, {'error': 'POST only'});
      final user = _user(req);
      final b = await _body(req);
      return _json(req, 200, {
        'user': await _accounts.confirmTotp(user['id'] as String, '${b['code'] ?? ''}', keepToken: _bearer(req)),
      });
    case '/auth/totp/disable':
      if (req.method != 'POST') return _json(req, 405, {'error': 'POST only'});
      final user = _user(req);
      final b = await _body(req);
      return _json(req, 200, {
        'user': await _accounts.disableTotp(user['id'] as String, '${b['password'] ?? ''}', '${b['code'] ?? ''}',
            keepToken: _bearer(req)),
      });
    case '/auth/profile':
      final user = _user(req);
      final b = await _body(req);
      return _json(req, 200, {'user': await _accounts.changeName(user['id'] as String, '${b['name'] ?? ''}')});
    // POST {email} → {found, name?} — never GET (keeps emails out of access logs)
    case '/users/lookup':
      if (req.method != 'POST') return _json(req, 405, {'error': 'POST only'});
      final user = _user(req);
      final uid = user['id'] as String;
      final ip = _clientIp(req);
      if (_lookupLimit.blocked(ip) || _lookupUserLimit.blocked(uid)) {
        throw AuthError.wait(_lookupLimit.blocked(ip) ? _lookupLimit.wait(ip) : _lookupUserLimit.wait(uid));
      }
      _lookupLimit.hit(ip);
      _lookupUserLimit.hit(uid);
      final email = '${(await _body(req))['email'] ?? ''}';
      final name = _accounts.lookupNameByEmail(email, exceptUserId: uid);
      // same shape for unknown and self — no enumeration oracle
      return _json(req, 200, name == null ? {'found': false} : {'found': true, 'name': name});
    case '/auth/email':
      final user = _user(req);
      final b = await _body(req);
      return _json(req, 200, {
        'user': await _accounts.changeEmail(user['id'] as String, '${b['email'] ?? ''}', '${b['password'] ?? ''}')
      });
    case '/auth/password':
      final user = _user(req);
      final b = await _body(req);
      await _accounts.changePassword(
          user['id'] as String, '${b['current'] ?? ''}', '${b['next'] ?? ''}', _bearer(req) ?? '');
      return _json(req, 200, {'ok': true});
    case '/auth/account':
      if (req.method != 'DELETE') return _json(req, 405, {'error': 'DELETE only'});
      return _deleteAccount(req);
    // GET -> {version, updatedAt, data} or 404; POST {data} -> {version}
    case '/vault':
      final id = _user(req)['id'] as String;
      if (req.method == 'POST') {
        final b = await _body(req);
        final expected = b['expectedVersion'];
        final ev = expected is int ? expected : int.tryParse('$expected');
        if (ev == null) throw const AuthError(400, 'expectedVersion fehlt.');
        return _json(req, 200, {'version': await _vault.put(id, b['data'], expectedVersion: ev)});
      }
      if (req.method != 'GET') return _json(req, 405, {'error': 'GET or POST only'});
      final v = await _vault.get(id);
      return v == null ? _json(req, 404, {'error': 'Noch keine Sicherung.'}) : _json(req, 200, v);
    case '/ai/chat':
      _guardAi(req);
      return _aiChat(req);
    case '/ai/parse':
      _guardAi(req);
      final user = _aiUser(req);
      final b = await _body(req);
      _countAi(user);
      return _json(req, 200, {'booking': await _ai.parse('${b['text'] ?? ''}', _categories(b))});
    // POST {text, image?, mediaType?, categories, accounts: [{id, name, kind}], depots} -> {reply, entries}
    case '/ai/entries':
      _guardAi(req);
      final user = _aiUser(req);
      final b = await _body(req);
      _countAi(user);
      return _json(
          req,
          200,
          await _ai.entries(
            text: '${b['text'] ?? ''}'.trim(),
            base64Image: b['image'] as String?,
            mediaType: '${b['mediaType'] ?? 'image/jpeg'}',
            categories: _categories(b),
            accounts: [for (final a in (b['accounts'] as List? ?? const [])) if (a is Map) a.cast<String, dynamic>()],
            depots: [for (final d in (b['depots'] as List? ?? const [])) '$d'],
          ));
    case '/ai/receipt':
      _guardAi(req);
      final user = _aiUser(req);
      final b = await _body(req);
      _countAi(user);
      return _json(req, 200, {
        'booking': await _ai.receipt('${b['image'] ?? ''}', '${b['mediaType'] ?? 'image/jpeg'}', _categories(b))
      });
    case '/bank/institutions':
      _user(req); // auth required — was an open proxy into Enable Banking
      final ip = _clientIp(req);
      if (_institutionsLimit.blocked(ip)) throw AuthError.wait(_institutionsLimit.wait(ip));
      _institutionsLimit.hit(ip);
      final country = q['country'] ?? 'DE';
      if (!RegExp(r'^[A-Za-z]{2}$').hasMatch(country)) {
        return _json(req, 400, {'error': 'country ungültig'});
      }
      return _json(req, 200, {'institutions': await _bank.institutions(country.toUpperCase())});
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
    case '/plus/status':
      return _plusStatus(req);
    case '/plus/checkout':
      _requireBilling();
      return _plusCheckout(req);
    case '/plus/store':
      if (_storeLimit.blocked(_clientIp(req))) throw AuthError.wait(_storeLimit.wait(_clientIp(req)));
      return _plusFromStore(req);
    case '/plus/demo-checkout':
      _requireBilling();
      return _plusDemoCheckout(req);
    case '/plus/demo-pay':
      _requireBilling();
      return _plusDemoPay(req);
    case '/plus/return':
      return _plusReturn(req);
    case '/plus/portal':
      return _plusPortal(req);
    case '/plus/demo-portal':
      return _html(req, '''
<div class="tag">DEMO · keine echten Daten</div>
<h1>Kundenportal</h1>
<p>Hier änderst du im echten Betrieb bei Stripe deine Zahlungsmethode und deinen Tarif und lädst Rechnungen herunter.</p>
<p class="dim">Im Demo-Modus gibt es dafür nichts zu tun. Du kannst dieses Fenster schließen.</p>''');
    case '/plus/cancel':
      return _plusCancel(req);
    case '/plus/withdraw':
      return _plusWithdraw(req);
    case '/stripe/webhook':
      return _stripeWebhook(req);
    case '/depot/connect':
      return _depotConnect(req);
    case '/depot/demo-consent':
      return _depotDemoConsent(req);
    case '/depot/callback':
      return _depotCallback(req);
    case '/depot/status':
      return _depotStatus(req);
    case '/depot/sync':
      return _depotSync(req);
    case '/depot/disconnect':
      return _depotDisconnect(req);
    case '/splits/share':
      final user = _user(req);
      final b = await _body(req);
      return _json(req, 200,
          await _splits.share(user['id'] as String, (b['group'] as Map).cast<String, dynamic>(), (b['me'] as num?)?.toInt() ?? 0));
    case '/splits/preview':
      _user(req);
      return _json(req, 200, _splits.preview(q['code'] ?? ''));
    case '/splits/join':
      final user = _user(req);
      final b = await _body(req);
      return _json(req, 200,
          await _splits.join(user['id'] as String, '${b['code'] ?? ''}', (b['member'] as num?)?.toInt() ?? -1));
    case '/splits/get':
      final user = _user(req);
      return _json(req, 200, _splits.get(user['id'] as String, q['id'] ?? ''));
    case '/splits/op':
      final user = _user(req);
      final b = await _body(req);
      return _json(req, 200,
          await _splits.apply(user['id'] as String, '${b['id'] ?? ''}', (b['op'] as Map).cast<String, dynamic>()));
    case '/splits/leave':
      final user = _user(req);
      final b = await _body(req);
      await _splits.leave(user['id'] as String, '${b['id'] ?? ''}');
      return _json(req, 200, {'ok': true});
    case '/datenschutz':
      return _legal(req, LegalTexts.privacy);
    case '/nutzungsbedingungen':
      return _legal(req, LegalTexts.terms);
    case '/impressum':
      return _legal(req, LegalTexts.imprint);
    case '/widerruf':
      return _legal(req, LegalTexts.withdrawal);
    case '/market/search':
      return _marketSearch(req);
    case '/market/news':
      return _marketNews(req);
    case '/market/chart':
      return _marketChart(req);
    case '/notify/whatsapp':
      if (req.method != 'GET') return _json(req, 405, {'error': 'GET only'});
      return _json(req, 200, {
        'configured': _whatsapp.configured,
        'optedIn': _whatsapp.optedIn(_user(req)['id'] as String),
      });
    case '/notify/whatsapp/link':
      return _waLink(req);
    case '/notify/whatsapp/unlink':
      return _waUnlink(req);
    case '/notify/whatsapp/webhook':
      return _waWebhook(req);
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
  final country = '${body['country'] ?? 'DE'}';
  if (!RegExp(r'^[A-Za-z]{2}$').hasMatch(country)) {
    return _json(req, 400, {'error': 'country ungültig'});
  }
  final state = _newState();
  final link = await _bank.startAuth(
    institution: institution,
    country: country.toUpperCase(),
    state: state,
    redirectUrl: _redirectUrl,
  );
  _dropAbandoned();
  _started[state] = DateTime.now();
  _pending[state] = (bank: institution, owner: user['id'] as String);
  return _json(req, 200, {'state': state, 'link': link});
}

// the demo bank's "login": one button that grants access
Future<void> _demoConsent(HttpRequest req) {
  final state = req.uri.queryParameters['state'] ?? '';
  final bank = _escape(req.uri.queryParameters['bank'] ?? 'Demo-Bank');
  final pending = _pending[state];
  final forWhom = pending == null
      ? ''
      : '<p class="dim">Die Freigabe landet im Konto <b>${_escape(_accounts.emailOf(pending.owner) ?? 'unbekannt')}</b>. '
          'Wenn das nicht dein Konto ist, brich ab.</p>';
  final ok = '/bank/callback?state=${Uri.encodeQueryComponent(state)}&code=${Uri.encodeQueryComponent(state)}';
  final no = '/bank/callback?state=${Uri.encodeQueryComponent(state)}&error=access_denied';
  return _html(req, '''
<div class="tag">DEMO · keine echten Daten</div>
<h1>$bank</h1>
<p>BudgetBuddy möchte <b>lesend</b> auf dein Girokonto zugreifen:</p>
<ul><li>Kontostand</li><li>Umsätze der letzten 90 Tage</li></ul>
$forWhom
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
    _failed[state] = (owner: pending.owner, error: q['error_description'] ?? q['error'] ?? 'abgebrochen');
    return _html(req, '<h1>Nicht verbunden</h1><p>Der Zugriff wurde nicht erteilt. Du kannst dieses Fenster schließen.</p>');
  }
  try {
    final session = await _bank.createSession(q['code']!);
    // refuse if any IBAN is already linked to another BudgetBuddy account
    for (final a in session.accounts) {
      final taken = _ibanOwner(a.iban);
      if (taken != null && taken != pending.owner) {
        try {
          await _bank.endSession(session.id);
        } catch (_) {}
        _pending.remove(state);
        _failed[state] = (
          owner: pending.owner,
          error: 'Dieses Bankkonto ist schon mit einem anderen BudgetBuddy-Konto verbunden.',
        );
        return _html(req, '<h1>Nicht verbunden</h1><p>Dieses Bankkonto gehört schon zu einem anderen Konto. '
            'Du kannst dieses Fenster schließen.</p>');
      }
    }
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
    _failed[state] = (owner: pending.owner, error: '$e');
    return _html(req, '<h1>Fehler</h1><p>${_escape('$e')}</p>');
  }
}

// which account already owns this IBAN, if any
String? _ibanOwner(String? iban) {
  if (iban == null || iban.isEmpty) return null;
  for (final s in _sessions.values) {
    for (final a in (s['accounts'] as List? ?? const [])) {
      if (a is Map && '${a['iban']}' == iban) return '${s['owner']}';
    }
  }
  return null;
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
  final failed = _failed[state];
  if (failed != null && failed.owner == user['id']) {
    return _json(req, 200, {'status': 'failed', 'error': failed.error});
  }
  return _json(req, 200, {'status': 'unknown'});
}

// GET ?state=&days=90 -> {balanceCents, accounts: [{uid, name, iban, balanceCents}], transactions}
// with each transaction's account uid, so every account can stand on its own
Future<void> _sync(HttpRequest req) async {
  final q = req.uri.queryParameters;
  final s = _ownSession(req, q['state'] ?? '');
  final days = (int.tryParse(q['days'] ?? '') ?? 90).clamp(1, 730);
  final from = DateTime.now().subtract(Duration(days: days));
  int balance = 0;
  final accounts = <Map<String, dynamic>>[];
  final txs = <Map<String, dynamic>>[];
  for (final a in (s['accounts'] as List)) {
    final uid = (a as Map)['uid'] as String;
    final cents = await _bank.balance(uid);
    balance += cents;
    accounts.add({'uid': uid, 'name': a['name'], 'iban': a['iban'], 'balanceCents': cents});
    for (final t in await _bank.transactions(uid, from)) {
      // prefix the account so ids stay unique across accounts
      txs.add(t.toJson()
        ..['id'] = '$uid:${t.id}'
        ..['account'] = uid);
    }
  }
  return _json(req, 200, {'bank': s['bank'], 'balanceCents': balance, 'accounts': accounts, 'transactions': txs});
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

// DELETE /auth/account {password}: the user, their sign-ins and every bank link
Future<void> _deleteAccount(HttpRequest req) async {
  final user = _user(req);
  final body = await _body(req);
  _accounts.confirmPassword(user['id'] as String, '${body['password'] ?? ''}');
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
  final ownDepots = _depots.entries.where((e) => e.value['owner'] == user['id']).toList();
  for (final e in ownDepots) {
    _depots.remove(e.key);
    try {
      await _depot.revoke(DepotTokens.fromJson(e.value['tokens'] as Map));
    } catch (_) {}
  }
  await _vault.delete(user['id'] as String);
  // a deleted account must not keep paying
  final plus = _plus.remove(user['id']);
  if (plus != null && plus.active && !StoreBilling.owns(plus)) {
    try {
      await _billing.setCancel(plus, true);
    } catch (_) {
      // logged by Stripe; the user can still cancel there
    }
  }
  await _savePlus();
  await _saveDepots();
  await _splits.forget(user['id'] as String);
  await _whatsapp.unlink(user['id'] as String);
  await _accounts.delete(user['id'] as String);
  return _json(req, 200, {'ok': true});
}

// --- WhatsApp (opt-in; no-op without the three env vars) ---

Future<void> _waLink(HttpRequest req) async {
  if (req.method != 'POST') return _json(req, 405, {'error': 'POST only'});
  final id = _user(req)['id'] as String;
  if (_waLinkLimit.blocked(id)) throw AuthError.wait(_waLinkLimit.wait(id));
  _waLinkLimit.hit(id);
  final phone = '${(await _body(req))['phone'] ?? ''}';
  await _whatsapp.link(id, phone);
  return _json(req, 200, {'ok': true, 'optedIn': true, 'instructions': WhatsApp.linkInstructions});
}

Future<void> _waUnlink(HttpRequest req) async {
  if (req.method != 'POST') return _json(req, 405, {'error': 'POST only'});
  await _whatsapp.unlink(_user(req)['id'] as String);
  return _json(req, 200, {'ok': true, 'optedIn': false});
}

Future<void> _waWebhook(HttpRequest req) async {
  final ip = _clientIp(req);
  if (_waLimit.blocked(ip)) throw AuthError.wait(_waLimit.wait(ip));
  _waLimit.hit(ip);
  if (req.method == 'GET') {
    final q = req.uri.queryParameters;
    final challenge = _whatsapp.verify(q['hub.mode'], q['hub.verify_token'], q['hub.challenge']);
    if (challenge == null) return _plain(req, 403, 'forbidden');
    return _plain(req, 200, challenge);
  }
  if (req.method != 'POST') return _json(req, 405, {'error': 'GET or POST only'});
  try {
    await _whatsapp.receive(await _body(req));
  } catch (e) {
    stderr.writeln('whatsapp webhook error ${e.runtimeType}');
  }
  return _json(req, 200, {'ok': true});
}

// --- AI ---

Map<String, dynamic> _aiUser(HttpRequest req) {
  final user = _user(req);
  if (!_ai.enabled) throw const AiError('KI ist auf dem Server nicht eingerichtet.');
  return user;
}

void _countAi(Map<String, dynamic> user) {
  final day = DateTime.now().toIso8601String().substring(0, 10);
  final id = user['id'] as String;
  final used = _aiUsage[id];
  final count = used != null && used.day == day ? used.count : 0;
  if (count >= _aiDailyLimit) throw const AuthError(429, 'Tageslimit für Buddy erreicht. Morgen geht es weiter.');
  _aiUsage[id] = (day: day, count: count + 1);
}

List<String> _categories(Map<String, dynamic> body) {
  final list = (body['categories'] as List?)?.map((e) => '$e').where((e) => e.isNotEmpty).toList();
  return list == null || list.isEmpty ? const ['Sonstiges'] : list;
}

void _guardAi(HttpRequest req) {
  final ip = _clientIp(req);
  if (_aiIpLimit.blocked(ip)) throw AuthError.wait(_aiIpLimit.wait(ip));
  _aiIpLimit.hit(ip);
}

// POST {finances, history} -> server-sent events: {"t": "..."} pieces, then {"done": true}
Future<void> _aiChat(HttpRequest req) async {
  final user = _aiUser(req);
  final body = await _body(req);
  _countAi(user);
  final history = [for (final m in (body['history'] as List? ?? [])) (m as Map).cast<String, dynamic>()];
  if (history.isEmpty) return _json(req, 400, {'error': 'Frage fehlt'});

  final res = req.response;
  _cors(req, res);
  _securityHeaders(res);
  res.headers
    ..contentType = ContentType('text', 'event-stream', charset: 'utf-8')
    ..set('Cache-Control', 'no-cache');
  res.bufferOutput = false;
  void send(Map<String, dynamic> event) => res.write('data: ${jsonEncode(event)}\n\n');
  try {
    await for (final piece in _ai.chat(finances: (body['finances'] as Map?)?.cast<String, dynamic>() ?? {}, history: history)) {
      send({'t': piece});
      await res.flush();
    }
    send({'done': true});
  } catch (e) {
    stderr.writeln('/ai/chat: $e');
    send({'error': e is AiError ? e.message : 'Buddy ist gerade nicht erreichbar. Bitte gleich noch einmal.'});
  }
  await res.close();
}

// --- Plus (payments) ---

// GET -> {mode, plus: entitlement or null}; re-reads Stripe when the copy is
// older than 30 minutes (or ?fresh=1), so renewals and failed payments show
// up even without webhooks
Future<void> _plusStatus(HttpRequest req) async {
  final user = _user(req);
  final id = user['id'] as String;
  var e = _plus[id];
  final stale = e != null && DateTime.now().difference(e.checked) > const Duration(minutes: 30);
  if (e != null && (stale || req.uri.queryParameters['fresh'] == '1')) {
    try {
      e = StoreBilling.owns(e) ? await _stores.refresh(e) : await _billing.refresh(e);
      _plus[id] = e;
      await _savePlus();
    } on BillingError catch (err) {
      // Stripe or a store is down: a paying user keeps Plus as last seen
      stderr.writeln('plus refresh for $id failed: ${err.message}');
    }
  }
  return _json(req, 200, {'mode': _billing.mode, 'plus': e?.active == true ? e!.toJson() : null});
}

// POST {plan, promo?} -> {url}: the payment page
Future<void> _plusCheckout(HttpRequest req) async {
  final user = _user(req);
  final b = await _body(req);
  final plan = b['plan'] == 'yearly' ? 'yearly' : 'monthly';
  final current = _plus[user['id']];
  if (current != null && current.active) return _json(req, 409, {'error': 'Du hast Plus schon.'});
  final promo = '${b['promo'] ?? ''}'.trim().toUpperCase();
  if (promo.isNotEmpty && !_promoCodes.containsKey(promo)) return _json(req, 400, {'error': 'Code unbekannt'});
  // whoever had Plus before gets no second trial
  final trial = current == null ? _trialDays + (_promoCodes[promo] ?? 0) : (_promoCodes[promo] ?? 0);
  final url = await _billing.checkout(
    user: user['id'] as String,
    email: '${user['email']}',
    plan: plan,
    trialDays: trial,
    returnUrl: '$_publicUrl/plus/return',
    cancelUrl: '$_publicUrl/plus/return?cancelled=1',
    customer: current?.customer,
  );
  return _json(req, 200, {'url': url, 'trialDays': trial});
}

Future<void> _plusDemoCheckout(HttpRequest req) {
  // the test checkout exists only while no real payments are set up
  if (_billing is! DemoBilling) throw const AuthError(404, 'Nicht gefunden.');
  final id = req.uri.queryParameters['session'] ?? '';
  final s = (_billing as DemoBilling).session(id);
  if (s == null) return _html(req, '<h1>Link abgelaufen</h1><p>Bitte starte den Kauf in BudgetBuddy erneut.</p>');
  final price = s.plan == 'yearly' ? '39,99 € im Jahr' : '4,99 € im Monat';
  final enc = Uri.encodeQueryComponent(id);
  return _html(req, '''
<div class="tag">DEMO · es wird nichts abgebucht</div>
<h1>BudgetBuddy Plus</h1>
<p>${s.trialDays > 0 ? '<b>${s.trialDays} Tage gratis</b>, danach $price.' : price}</p>
<p class="dim">Im echten Betrieb ist das die Zahlungsseite von Stripe. Dort wählst du Karte, PayPal, SEPA-Lastschrift, Apple Pay, Google Pay oder Klarna. BudgetBuddy sieht deine Zahlungsdaten nie.</p>
<a class="btn" href="/plus/demo-pay?session=$enc">Test-Zahlung bestätigen</a>
<a class="link" href="/plus/return?cancelled=1">Abbrechen</a>''');
}

Future<void> _plusDemoPay(HttpRequest req) async {
  // the test checkout exists only while no real payments are set up
  if (_billing is! DemoBilling) throw const AuthError(404, 'Nicht gefunden.');
  final id = req.uri.queryParameters['session'] ?? '';
  (_billing as DemoBilling).markPaid(id);
  req.response
    ..statusCode = 303
    ..headers.set('Location', '/plus/return?session_id=${Uri.encodeQueryComponent(id)}');
  await req.response.close();
}

// the payment page sends the browser here; the app notices Plus by polling /plus/status
Future<void> _plusReturn(HttpRequest req) async {
  final q = req.uri.queryParameters;
  if (q['cancelled'] == '1' || q['session_id'] == null) {
    return _html(req, '<h1>Abgebrochen</h1><p>Es wurde nichts gebucht. Du kannst dieses Fenster schließen.</p>');
  }
  final e = await _billing.fromSession(q['session_id']!);
  final user = e == null ? null : await _ownerOf(q['session_id']!, e);
  if (e == null || user == null) {
    return _html(req, '<h1>Noch nicht bezahlt</h1><p>Die Zahlung ist nicht abgeschlossen. Bitte versuche es erneut.</p>');
  }
  _plus[user] = e;
  await _savePlus();
  return _html(req, '''
<div class="check">✓</div>
<h1>Willkommen bei Plus</h1>
<p>Alles ist freigeschaltet. Du kannst dieses Fenster schließen und zu BudgetBuddy zurückkehren.</p>
<script>setTimeout(() => window.close(), 1800)</script>''');
}

// the user a checkout belongs to: Stripe keeps it in the session, the demo in memory
Future<String?> _ownerOf(String sessionId, Entitlement e) async {
  if (_billing is DemoBilling) return (_billing as DemoBilling).session(sessionId)?.user;
  final s = await net.get(Uri.parse('https://api.stripe.com/v1/checkout/sessions/${Uri.encodeComponent(sessionId)}'),
      headers: {'Authorization': 'Bearer ${_env('STRIPE_SECRET_KEY')}'});
  return (jsonDecode(s.body) as Map)['client_reference_id'] as String?;
}

// a Stripe subscription of the signed-in user; store ones are managed in the store
Entitlement _ownPlus(HttpRequest req) {
  final user = _user(req);
  final e = _plus[user['id']];
  if (e == null || !e.active) throw const AuthError(404, 'Kein Plus-Abo gefunden.');
  if (StoreBilling.owns(e)) {
    throw AuthError(409, 'Dein Abo verwaltest du in ${e.method == 'appStore' ? 'den Abos deiner Apple-ID' : 'Google Play'}.');
  }
  return e;
}

// POST {platform: apple|google, id} -> {plus}: a purchase from the App Store
// (id = transaction id) or Google Play (id = purchase token), checked with the
// store itself. Signed in, the subscription belongs to the account from then
// on; for a guest the answer is only returned.
Future<void> _plusFromStore(HttpRequest req) async {
  final user = _accounts.userFor(_bearer(req));
  final b = await _body(req);
  final e = await _stores.verify('${b['platform']}', '${b['id'] ?? ''}');
  if (user != null) {
    final id = user['id'] as String;
    // one store subscription unlocks one account
    final taken = _plus.entries.any((p) => p.key != id && p.value.active && p.value.subscription == e.subscription);
    if (taken) return _json(req, 409, {'error': 'Dieses Abo gehört schon zu einem anderen BudgetBuddy-Konto.'});
    final current = _plus[id];
    // a running Stripe subscription is not replaced by an expired store purchase
    if (e.active || current == null || !current.active || StoreBilling.owns(current)) {
      _plus[id] = e;
      await _savePlus();
    }
  }
  return _json(req, 200, {'plus': e.active ? e.toJson() : null});
}

// the stores whose credentials are set
Future<StoreBilling> _storeBilling() async {
  final products = PlusProducts(
    monthly: _env('PLUS_PRODUCT_MONTHLY').isNotEmpty ? _env('PLUS_PRODUCT_MONTHLY') : 'budgetbuddy_plus_monthly',
    yearly: _env('PLUS_PRODUCT_YEARLY').isNotEmpty ? _env('PLUS_PRODUCT_YEARLY') : 'budgetbuddy_plus_yearly',
  );
  final appleKey = _env('APPLE_PRIVATE_KEY_PATH');
  final googleKey = _env('GOOGLE_SERVICE_ACCOUNT_PATH');
  return StoreBilling(
    apple: _env('APPLE_BUNDLE_ID').isEmpty || appleKey.isEmpty
        ? null
        : AppleStore(
            bundleId: _env('APPLE_BUNDLE_ID'),
            issuerId: _env('APPLE_ISSUER_ID'),
            keyId: _env('APPLE_KEY_ID'),
            privateKeyPem: await File(appleKey).readAsString(),
            products: products,
          ),
    google: _env('GOOGLE_PACKAGE_NAME').isEmpty || googleKey.isEmpty
        ? null
        : GooglePlay(
            packageName: _env('GOOGLE_PACKAGE_NAME'),
            serviceAccount: jsonDecode(await File(googleKey).readAsString()) as Map<String, dynamic>,
            products: products,
          ),
  );
}

// POST -> {url}: Stripe's customer portal (payment method, plan, invoices)
Future<void> _plusPortal(HttpRequest req) async {
  final e = _ownPlus(req);
  return _json(req, 200, {'url': await _billing.portal(e, '$_publicUrl/plus/return?cancelled=1')});
}

// POST {cancel: true|false}: cancel at the end of the period, or take it back
Future<void> _plusCancel(HttpRequest req) async {
  final user = _user(req);
  final e = _ownPlus(req);
  final cancel = (await _body(req))['cancel'] != false;
  final next = await _billing.setCancel(e, cancel);
  _plus[user['id'] as String] = next;
  await _savePlus();
  return _json(req, 200, {'plus': next.toJson()});
}

// POST: the 14-day withdrawal, ends Plus now and refunds
Future<void> _plusWithdraw(HttpRequest req) async {
  final user = _user(req);
  final e = _ownPlus(req);
  if (DateTime.now().difference(e.started) > const Duration(days: 14)) {
    return _json(req, 400, {'error': 'Die 14-Tage-Frist für den Widerruf ist vorbei.'});
  }
  _plus[user['id'] as String] = await _billing.withdraw(e);
  await _savePlus();
  return _json(req, 200, {'ok': true});
}

// Stripe tells us about renewals, failed payments and cancellations
Future<void> _stripeWebhook(HttpRequest req) async {
  final secret = _env('STRIPE_WEBHOOK_SECRET');
  // same size cap as other POSTs — never buffer an unbounded body
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in req) {
    bytes.add(chunk);
    if (bytes.length > 256 << 10) return _json(req, 413, {'error': 'Die Anfrage ist zu groß.'});
  }
  final payload = utf8.decode(bytes.takeBytes());
  if (secret.isEmpty || !StripeBilling.verifyWebhook(payload, req.headers.value('stripe-signature') ?? '', secret)) {
    return _json(req, 400, {'error': 'invalid signature'});
  }
  final event = jsonDecode(payload) as Map<String, dynamic>;
  final eventId = '${event['id'] ?? ''}';
  if (eventId.isNotEmpty && _stripeSeen.contains(eventId)) {
    return _json(req, 200, {'received': true, 'duplicate': true});
  }
  if (eventId.isNotEmpty) {
    _stripeSeen.add(eventId);
    if (_stripeSeen.length > 500) {
      final drop = _stripeSeen.length - 500;
      _stripeSeen.removeAll(_stripeSeen.take(drop).toList());
    }
    unawaited(_saveStripeSeen());
  }
  final obj = ((event['data'] as Map?)?['object'] as Map?) ?? const {};
  if ('${event['type']}'.startsWith('customer.subscription.')) {
    final user = '${(obj['metadata'] as Map?)?['user'] ?? ''}';
    var known = _plus[user];
    // a new subscription after the old one ended: follow the new one, but
    // never let a late event of an old subscription replace a live one
    final sub = '${obj['id'] ?? ''}';
    if (known != null && sub.isNotEmpty && known.subscription != sub && !known.active &&
        {'active', 'trialing'}.contains(obj['status'])) {
      known = Entitlement.fromJson({...known.toJson(), 'subscription': sub});
    }
    if (user.isNotEmpty) {
      final base = known ??
          Entitlement.fromJson({
            'plan': 'monthly',
            'status': 'incomplete',
            'started': DateTime.now().toIso8601String(),
            'trialEnds': DateTime.now().toIso8601String(),
            'periodEnd': DateTime.now().toIso8601String(),
            'customer': '${obj['customer'] ?? ''}',
            'subscription': '${obj['id']}',
          });
      _plus[user] = await _billing.refresh(base);
      await _savePlus();
    }
  }
  return _json(req, 200, {'received': true});
}

// --- depot (Parqet Connect) ---

// POST -> {state, link}: the page where the user allows BudgetBuddy to read their depot
Future<void> _depotConnect(HttpRequest req) async {
  final user = _user(req);
  final state = _newState();
  final p = pkce();
  _dropAbandoned();
  _started[state] = DateTime.now();
  _depotPending[state] = (owner: user['id'] as String, verifier: p.verifier);
  return _json(req, 200, {
    'state': state,
    'link': _depot.authUrl(state: state, challenge: p.challenge, redirectUrl: _depotRedirect),
  });
}

Future<void> _depotDemoConsent(HttpRequest req) {
  final raw = req.uri.queryParameters['state'] ?? '';
  final state = Uri.encodeQueryComponent(raw);
  final pending = _depotPending[raw];
  final forWhom = pending == null
      ? ''
      : '<p class="dim">Die Freigabe landet im Konto <b>${_escape(_accounts.emailOf(pending.owner) ?? 'unbekannt')}</b>. '
          'Wenn das nicht dein Konto ist, brich ab.</p>';
  return _html(req, '''
<div class="tag">DEMO · keine echten Daten</div>
<h1>Parqet</h1>
<p>BudgetBuddy möchte <b>lesend</b> auf deine Depots zugreifen:</p>
<ul><li>Positionen und Stückzahlen</li><li>Kaufkurse und aktuelle Kurse</li></ul>
$forWhom
<p class="dim">Bei Parqet meldest du dich hier an. Dein Trade-Republic-Login bleibt bei Parqet, BudgetBuddy sieht ihn nie.</p>
<a class="btn" href="/depot/callback?state=$state&code=$state">Zugriff erlauben</a>
<a class="link" href="/depot/callback?state=$state&error=access_denied">Abbrechen</a>''');
}

Future<void> _depotCallback(HttpRequest req) async {
  final q = req.uri.queryParameters;
  final state = q['state'] ?? '';
  final pending = _depotPending.remove(state);
  if (pending == null) {
    return _html(req, '<h1>Link abgelaufen</h1><p>Bitte starte die Verbindung in BudgetBuddy erneut.</p>');
  }
  if (q['code'] == null) {
    _depotFailed[state] = (owner: pending.owner, error: q['error_description'] ?? q['error'] ?? 'abgebrochen');
    return _html(req, '<h1>Nicht verbunden</h1><p>Der Zugriff wurde nicht erteilt. Du kannst dieses Fenster schließen.</p>');
  }
  try {
    final tokens = await _depot.exchange(code: q['code']!, verifier: pending.verifier, redirectUrl: _depotRedirect);
    // refuse Parqet portfolios already linked to another BudgetBuddy account
    final snap = await _depot.snapshot(tokens);
    final portfolios = _portfolioIdsFrom(snap);
    for (final id in portfolios) {
      final taken = _portfolioOwner(id);
      if (taken != null && taken != pending.owner) {
        try {
          await _depot.revoke(tokens);
        } catch (_) {}
        _depotFailed[state] = (
          owner: pending.owner,
          error: 'Dieses Depot ist schon mit einem anderen BudgetBuddy-Konto verbunden.',
        );
        return _html(req, '<h1>Nicht verbunden</h1><p>Dieses Depot gehört schon zu einem anderen Konto. '
            'Du kannst dieses Fenster schließen.</p>');
      }
    }
    _depots[state] = {
      'owner': pending.owner,
      'tokens': tokens.toJson(),
      'linkedAt': DateTime.now().toIso8601String(),
      'portfolioIds': portfolios.toList(),
    };
    await _saveDepots();
    return _html(req, '''
<div class="check">✓</div>
<h1>Verbunden</h1>
<p>Dein Depot ist jetzt mit BudgetBuddy verbunden. Du kannst dieses Fenster schließen.</p>
<script>setTimeout(() => window.close(), 1500)</script>''');
  } catch (e) {
    _depotFailed[state] = (owner: pending.owner, error: '$e');
    return _html(req, '<h1>Fehler</h1><p>${_escape('$e')}</p>');
  }
}

Set<String> _portfolioIdsFrom(DepotSnapshot snap) {
  final ids = <String>{};
  for (final p in snap.positions) {
    if (p.id.contains(':')) ids.add(p.id.split(':').first);
  }
  return ids;
}

String? _portfolioOwner(String portfolioId) {
  for (final d in _depots.values) {
    for (final id in (d['portfolioIds'] as List? ?? const [])) {
      if ('$id' == portfolioId) return '${d['owner']}';
    }
  }
  return null;
}

Map<String, dynamic> _ownDepot(HttpRequest req, String state) {
  final user = _user(req);
  final d = _depots[state];
  if (d == null || d['owner'] != user['id']) throw const AuthError(404, 'Kein Depot verbunden. Bitte neu verbinden.');
  return d;
}

// GET ?state= -> {status: pending|linked|failed|unknown}
Future<void> _depotStatus(HttpRequest req) {
  final user = _user(req);
  final state = req.uri.queryParameters['state'] ?? '';
  if (_depots[state]?['owner'] == user['id']) return _json(req, 200, {'status': 'linked', 'mode': _depot.mode});
  if (_depotPending[state]?.owner == user['id']) return _json(req, 200, {'status': 'pending'});
  final failed = _depotFailed[state];
  if (failed != null && failed.owner == user['id']) {
    return _json(req, 200, {'status': 'failed', 'error': failed.error});
  }
  return _json(req, 200, {'status': 'unknown'});
}

// GET ?state= -> {positions, history, mode}; refreshes the access token when needed
Future<void> _depotSync(HttpRequest req) async {
  final state = req.uri.queryParameters['state'] ?? '';
  final d = _ownDepot(req, state);
  var tokens = DepotTokens.fromJson(d['tokens'] as Map);
  Future<void> renew() async {
    tokens = await _depot.refresh(tokens);
    d['tokens'] = tokens.toJson();
    await _saveDepots();
  }

  if (DateTime.now().isAfter(tokens.expires)) await renew();
  DepotSnapshot snap;
  try {
    snap = await _depot.snapshot(tokens);
  } on DepotAuthExpired {
    await renew();
    snap = await _depot.snapshot(tokens);
  }
  snap = await _symbols.complete(snap);
  return _json(req, 200, {...snap.toJson(), 'mode': _depot.mode});
}

// POST {state}
Future<void> _depotDisconnect(HttpRequest req) async {
  final state = '${(await _body(req))['state'] ?? ''}';
  final d = _ownDepot(req, state);
  _depots.remove(state);
  await _saveDepots();
  try {
    await _depot.revoke(DepotTokens.fromJson(d['tokens'] as Map));
  } catch (_) {}
  return _json(req, 200, {'ok': true});
}

// --- market data ---

// Yahoo's chart API sends no CORS headers, so the web app asks through here.
// Public data only, no sign-in needed; answers are cached for five minutes.
final _chartCache = <String, (DateTime, String)>{};

Future<void> _marketChart(HttpRequest req) async {
  final ip = _clientIp(req);
  if (_chartLimit.blocked(ip)) throw AuthError.wait(_chartLimit.wait(ip));
  final symbol = req.uri.queryParameters['symbol'] ?? '';
  final range = req.uri.queryParameters['range'] ?? '1d';
  final interval = req.uri.queryParameters['interval'] ?? '1d';
  if (!marketChartQueryOk(symbol, range, interval)) {
    return _json(req, 400, {'error': 'symbol oder range ungültig'});
  }
  final key = '$symbol|$range|$interval';
  final hit = _chartCache[key];
  if (hit != null && DateTime.now().difference(hit.$1) < const Duration(minutes: 5)) {
    return _raw(req, hit.$2);
  }
  final res = await net.get(
    Uri.parse('https://query1.finance.yahoo.com/v8/finance/chart/${Uri.encodeComponent(symbol)}'
        '?interval=$interval&range=$range'),
    headers: {'User-Agent': 'Mozilla/5.0 BudgetBuddy'},
  );
  if (res.statusCode != 200) return _json(req, 502, {'error': 'Kursdaten gerade nicht verfügbar'});
  if (_chartCache.length > 500) _chartCache.clear();
  _chartCache[key] = (DateTime.now(), res.body);
  return _raw(req, res.body);
}

// Public, like /market/chart: five-minute cache, 60 requests a minute per IP.
final _searchCache = <String, (DateTime, String)>{};
final _newsCache = <String, (DateTime, String)>{};

Future<void> _marketSearch(HttpRequest req) {
  final q = (req.uri.queryParameters['q'] ?? '').trim();
  if (!marketQueryOk(q)) return _json(req, 400, {'error': 'Suchbegriff ungültig'});
  return _marketCached(
    req,
    cache: _searchCache,
    key: q.toLowerCase(),
    uri: Uri.https('query2.finance.yahoo.com', '/v1/finance/search', {
      'q': q,
      'quotesCount': '10',
      'newsCount': '0',
    }),
    shape: (body) => jsonEncode({'quotes': marketQuotes(body)}),
  );
}

Future<void> _marketNews(HttpRequest req) {
  final symbol = req.uri.queryParameters['symbol'] ?? '';
  if (!RegExp(r'^[A-Za-z0-9.=^-]{1,20}$').hasMatch(symbol)) {
    return _json(req, 400, {'error': 'symbol ungültig'});
  }
  return _marketCached(
    req,
    cache: _newsCache,
    key: symbol,
    uri: Uri.https('query2.finance.yahoo.com', '/v1/finance/search', {
      'q': symbol,
      'quotesCount': '0',
      'newsCount': '8',
    }),
    shape: (body) => jsonEncode({'news': marketNews(body, symbol: symbol)}),
  );
}

Future<void> _marketCached(
  HttpRequest req, {
  required Map<String, (DateTime, String)> cache,
  required String key,
  required Uri uri,
  required String Function(String body) shape,
}) async {
  final ip = _clientIp(req);
  if (_marketLimit.blocked(ip)) throw AuthError.wait(_marketLimit.wait(ip));
  _marketLimit.hit(ip);
  final hit = cache[key];
  if (hit != null && DateTime.now().difference(hit.$1) < const Duration(minutes: 5)) {
    return _raw(req, hit.$2);
  }
  final res = await net.get(uri, headers: {'User-Agent': 'Mozilla/5.0 BudgetBuddy'});
  if (res.statusCode != 200) return _json(req, 502, {'error': 'Marktdaten gerade nicht verfügbar'});
  if (cache.length > 500) cache.clear();
  final body = shape(res.body);
  cache[key] = (DateTime.now(), body);
  return _raw(req, body);
}

Future<void> _raw(HttpRequest req, String json) async {
  _cors(req, req.response);
  _securityHeaders(req.response);
  req.response
    ..statusCode = 200
    ..headers.contentType = ContentType.json;
  req.response.write(json);
  await req.response.close();
}

// --- html ---

// a legal page from the app's texts, readable in any browser
Future<void> _legal(HttpRequest req, LegalDoc doc) {
  final body = StringBuffer('<article><h1>${_escape(doc.title)}</h1>');
  for (final s in doc.sections) {
    body.write('<h2>${_escape(s.heading)}</h2>');
    for (final para in s.body.split('\n\n')) {
      body.write('<p>${_escape(para).replaceAll('\n', '<br>')}</p>');
    }
  }
  body.write('</article>');
  return _html(req, body.toString());
}

String _escape(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

String _page(String body) => '''<!doctype html>
<html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>BudgetBuddy</title>
<style>
  body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;
       background:#0b0b10;color:#f2f4f7;font:16px/1.5 -apple-system,BlinkMacSystemFont,Inter,sans-serif}
  main{max-width:380px;padding:32px 24px}
  main:has(article){max-width:680px;align-self:flex-start}
  article h2{font-size:18px;margin:28px 0 8px}
  article p{line-height:1.6}
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
