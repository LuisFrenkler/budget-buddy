// Enable Banking (https://enablebanking.com): PSD2 access to 2,500+ European
// banks. Free for your own accounts ("restricted" production mode).
//
// Every request is authorized with a short-lived JWT signed (RS256) by the
// private key that belongs to the registered application.
import 'dart:io';
import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

import 'bank_provider.dart';
import 'net.dart';

class EnableBanking implements BankProvider {
  static const _base = 'https://api.enablebanking.com';

  final String appId;
  final String privateKeyPem;

  EnableBanking({required this.appId, required this.privateKeyPem});

  @override
  String get mode => 'live';

  String? _jwt;
  DateTime _jwtExp = DateTime.fromMillisecondsSinceEpoch(0);

  String _token() {
    if (_jwt != null && DateTime.now().isBefore(_jwtExp)) return _jwt!;
    final jwt = JWT(
      {},
      issuer: 'enablebanking.com',
      audience: Audience.one('api.enablebanking.com'),
      header: {'kid': appId},
    );
    _jwt = jwt.sign(RSAPrivateKey(privateKeyPem), algorithm: JWTAlgorithm.RS256, expiresIn: const Duration(hours: 1));
    // renew a little early so a request never carries an expired token
    _jwtExp = DateTime.now().add(const Duration(minutes: 55));
    return _jwt!;
  }

  Map<String, String> get _headers => {'Authorization': 'Bearer ${_token()}', 'Content-Type': 'application/json'};

  Future<Map<String, dynamic>> _get(String path) async {
    final res = await net.get(Uri.parse('$_base$path'), headers: _headers);
    if (res.statusCode != 200) _fail(res.statusCode, res.body);
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _post(String path, Object body) async {
    final res = await net.post(Uri.parse('$_base$path'), headers: _headers, body: jsonEncode(body));
    if (res.statusCode >= 300) _fail(res.statusCode, res.body);
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  @override
  Future<List<Map<String, dynamic>>> institutions(String country) async {
    final body = await _get('/aspsps?country=$country&psu_type=personal');
    return [
      for (final a in (body['aspsps'] as List? ?? []))
        // the name is the identifier Enable Banking expects in /auth
        {
          'id': a['name'],
          'name': a['name'],
          'logo': a['logo'],
          'bic': a['bic'],
          'group': a['group'] is Map ? a['group']['name'] : a['group'],
        }
    ];
  }

  @override
  Future<String> startAuth({
    required String institution,
    required String country,
    required String state,
    required String redirectUrl,
  }) async {
    final body = await _post('/auth', {
      // PSD2 allows up to 180 days of access without a new login
      'access': {'valid_until': DateTime.now().toUtc().add(const Duration(days: 180)).toIso8601String()},
      'aspsp': {'name': institution, 'country': country},
      'state': state,
      'redirect_url': redirectUrl,
      'psu_type': 'personal',
    });
    return body['url'] as String;
  }

  @override
  Future<BankSession> createSession(String code) async {
    final body = await _post('/sessions', {'code': code});
    final accounts = [
      for (final a in (body['accounts'] as List? ?? []))
        BankAccount(
          '${a['uid']}',
          iban: a['account_id']?['iban'] as String?,
          name: (a['name'] ?? a['product']) as String?,
        )
    ];
    final until = DateTime.tryParse('${body['access']?['valid_until']}') ??
        DateTime.now().add(const Duration(days: 90));
    return BankSession('${body['session_id']}', accounts, until);
  }

  // the bank's answer goes to the log only: it can hold account details and
  // would end up on the status page the user sees
  static Never _fail(int status, String body) {
    stderr.writeln('Enable Banking $status: $body');
    throw 'Die Bank hat die Anfrage abgelehnt ($status).';
  }

  @override
  Future<int> balance(String accountUid) async {
    final body = await _get('/accounts/$accountUid/balances');
    final balances = (body['balances'] as List? ?? []).cast<Map<String, dynamic>>();
    if (balances.isEmpty) return 0;
    Map<String, dynamic>? ofType(String type) {
      for (final b in balances) {
        if (b['balance_type'] == type) return b;
      }
      return null;
    }

    // what the banking app shows: booked plus the pending ("vorgemerkt")
    // card payments and debits. XPCD is exactly that when the bank sends it.
    final expected = ofType('XPCD');
    if (expected != null) return _cents(expected);
    // ITBD/ITAV = interim booked now; safe to add pending card payments
    final interim = ofType('ITBD') ?? ofType('ITAV');
    if (interim != null) return _cents(interim) + await _pendingCents(accountUid);
    // CLBD is yesterday's close — do not mix with today's pending window
    final closed = ofType('CLBD') ?? ofType('CLAV') ?? balances.first;
    return _cents(closed);
  }

  static int _cents(Map<String, dynamic> balance) {
    final cents = amountToCents('${balance['balance_amount']?['amount']}');
    // some banks give the amount unsigned with a debit indicator for an overdrawn account
    final debit = balance['credit_debit_indicator'] == 'DBIT' && cents > 0;
    return debit ? -cents : cents;
  }

  // bank amount strings → integer cents without binary float (e.g. "12.34", "-0.10")
  static int amountToCents(String raw) {
    var s = raw.trim().replaceAll(' ', '').replaceAll(',', '.');
    if (s.isEmpty || s == 'null') return 0;
    var neg = false;
    if (s.startsWith('-')) {
      neg = true;
      s = s.substring(1);
    } else if (s.startsWith('+')) {
      s = s.substring(1);
    }
    final dot = s.indexOf('.');
    final wholeStr = dot < 0 ? s : s.substring(0, dot);
    final fracStr = dot < 0 ? '' : s.substring(dot + 1);
    final whole = int.tryParse(wholeStr.isEmpty ? '0' : wholeStr) ?? 0;
    final fracCents =
        fracStr.isEmpty ? 0 : (int.tryParse(fracStr.padRight(2, '0').substring(0, 2)) ?? 0);
    final cents = whole * 100 + fracCents;
    return neg ? -cents : cents;
  }

  // the signed sum of transactions that are not booked yet
  Future<int> _pendingCents(String accountUid) async {
    final from = DateTime.now().subtract(const Duration(days: 30));
    final day = '${from.year}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}';
    var sum = 0;
    String? continuation;
    do {
      final query = 'date_from=$day&transaction_status=PDNG'
          '${continuation != null ? '&continuation_key=${Uri.encodeQueryComponent(continuation)}' : ''}';
      final body = await _get('/accounts/$accountUid/transactions?$query');
      for (final t in (body['transactions'] as List? ?? [])) {
        // only what is marked pending: a bank that ignores the filter sends
        // booked ones too, sometimes without any status
        if (t['status'] != 'PDNG') continue;
        final tx = parseTx(t as Map<String, dynamic>);
        if (tx != null) sum += tx.amountCents;
      }
      continuation = body['continuation_key'] as String?;
    } while (continuation != null && continuation.isNotEmpty);
    return sum;
  }

  @override
  Future<List<BankTx>> transactions(String accountUid, DateTime from) async {
    final out = <BankTx>[];
    final day = '${from.year}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}';
    // fingerprints that collide (two REWE same day) get #0, #1, …
    final fpCount = <String, int>{};
    String? continuation;
    do {
      final query = 'date_from=$day${continuation != null ? '&continuation_key=${Uri.encodeQueryComponent(continuation)}' : ''}';
      final body = await _get('/accounts/$accountUid/transactions?$query');
      for (final t in (body['transactions'] as List? ?? [])) {
        if (t['status'] != null && t['status'] != 'BOOK') continue; // skip pending
        final tx = parseTx(t as Map<String, dynamic>, fpCount);
        if (tx != null) out.add(tx);
      }
      continuation = body['continuation_key'] as String?;
    } while (continuation != null && continuation.isNotEmpty);
    return out;
  }

  static BankTx? parseTx(Map<String, dynamic> t, [Map<String, int>? fpCount]) {
    final date = DateTime.tryParse('${t['booking_date'] ?? t['value_date'] ?? t['transaction_date']}');
    if (date == null) return null;
    final cents = amountToCents('${t['transaction_amount']?['amount']}').abs();
    final incoming = t['credit_debit_indicator'] == 'CRDT';
    // the other party: who paid us, or whom we paid. A non-object must not abort the sync.
    final rawOther = incoming ? t['debtor'] : t['creditor'];
    final other = rawOther is Map ? rawOther : null;
    final party = other?['name'];
    final remittance = t['remittance_information'];
    final purpose = remittance is List ? remittance.map(_remitPiece).join(' ') : '${remittance ?? ''}';
    // prefer stable bank ids; fingerprint only when the bank sends none.
    // transaction_id first: entry_reference sometimes appears only on a later sync
    // and would otherwise re-import the same booking under a new id.
    // party and purpose stay exactly as before so an old fingerprint still matches.
    final bankId = '${t['transaction_id'] ?? ''}'.trim();
    final entry = '${t['entry_reference'] ?? ''}'.trim();
    String id;
    if (bankId.isNotEmpty) {
      id = bankId;
    } else if (entry.isNotEmpty) {
      id = entry;
    } else {
      final fingerprint = '${date.toIso8601String()}|$cents|$party|$purpose';
      final n = fpCount?[fingerprint] ?? 0;
      if (fpCount != null) fpCount[fingerprint] = n + 1;
      id = n == 0 ? fingerprint : '$fingerprint#$n';
    }
    final code = t['bank_transaction_code'];
    final codeText = code is Map ? '${code['description'] ?? ''}'.trim() : '';
    final note = '${t['note'] ?? ''}'.trim();
    final hint = [codeText, if (note.isNotEmpty && note != codeText) note].where((s) => s.isNotEmpty).join(' ');
    return BankTx(id, date, incoming ? cents : -cents, '${party ?? ''}'.trim(), purpose.trim(),
        mcc: '${t['merchant_category_code'] ?? ''}'.trim(), hint: hint.length > 180 ? hint.substring(0, 180) : hint);
  }

  // a string stays itself so fingerprints of normal remittance do not change
  static String _remitPiece(dynamic e) => e is String ? e : _flatten(e);

  static String _flatten(dynamic v) {
    if (v is String) return v;
    if (v is List) return v.map(_flatten).join(' ');
    if (v is Map) return v.values.map(_flatten).join(' ');
    return '';
  }

  @override
  Future<void> endSession(String sessionId) async {
    await net.delete(Uri.parse('$_base/sessions/$sessionId'), headers: _headers);
  }
}
