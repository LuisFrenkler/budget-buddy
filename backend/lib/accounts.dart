// User accounts: sign-up, sign-in, sessions and deletion.
//
// - Passwords are stored only as bcrypt hashes.
// - Session tokens are 256-bit random values; the server keeps only their
//   SHA-256, so a leaked store does not leak usable tokens.
// - Five wrong passwords lock an email for five minutes.
// - Optional TOTP is checked after the password. The one-time login
//   challenge lives only in memory and dies with the process.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:bcrypt/bcrypt.dart';
import 'package:crypto/crypto.dart';

import 'json_store.dart';
import 'totp.dart';

class AuthError implements Exception {
  final int status;
  final String message;
  const AuthError(this.status, this.message);

  // too many attempts: says to the minute when the next try works
  factory AuthError.wait(Duration left) {
    final minutes = (left.inSeconds / 60).ceil().clamp(1, 1 << 20);
    return AuthError(429, 'Zu viele Versuche. Bitte warte $minutes ${minutes == 1 ? 'Minute' : 'Minuten'}.');
  }
  @override
  String toString() => message;
}

class Accounts {
  static const _tokenLifetime = Duration(days: 30);
  static const _maxFailures = 5;
  static const _lockout = Duration(minutes: 5);

  final File _store;
  final _users = <String, Map<String, dynamic>>{}; // id -> user
  final _tokens = <String, Map<String, dynamic>>{}; // sha256(token) -> {id, user, device, createdAt, expires}
  final _failures = <String, ({int count, DateTime until})>{};
  final _challenges = <String, _PendingLogin>{}; // sha256(challenge) -> pending 2FA login

  Accounts(this._store);

  Future<void> load() async {
    if (!await _store.exists()) return;
    final map = jsonDecode(await _store.readAsString()) as Map<String, dynamic>;
    (map['users'] as Map? ?? {}).forEach((k, v) => _users[k as String] = (v as Map).cast<String, dynamic>());
    (map['tokens'] as Map? ?? {}).forEach((k, v) => _tokens[k as String] = (v as Map).cast<String, dynamic>());
    var dirty = false;
    for (final t in _tokens.values) {
      if ('${t['id'] ?? ''}'.isEmpty) {
        t['id'] = _random(8);
        dirty = true;
      }
    }
    if (dirty) await _save();
  }

  Future<void> _save() {
    // expired sign-ins would otherwise pile up and be rewritten on every login
    final now = DateTime.now();
    _tokens.removeWhere((_, t) => now.isAfter(DateTime.tryParse('${t['expires']}') ?? now));
    return writeJsonAtomic(_store, {'users': _users, 'tokens': _tokens});
  }

  static String _random(int bytes) {
    final rnd = math.Random.secure();
    return List.generate(bytes, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  static String _digest(String token) => sha256.convert(utf8.encode(token)).toString();

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  // public view of a user: never the hash, the TOTP secret, or a pending secret
  static Map<String, dynamic> public(Map<String, dynamic> u) => {
        'id': u['id'],
        'email': u['email'],
        'name': u['name'],
        'createdAt': u['createdAt'],
        'totp': u['totpSecret'] is String && (u['totpSecret'] as String).isNotEmpty,
      };

  Map<String, dynamic>? _byEmail(String email) {
    for (final u in _users.values) {
      if (u['email'] == email) return u;
    }
    return null;
  }

  // exact email → display name for split invites. Self and unknown both
  // return null (same API shape) so the route cannot enumerate accounts.
  // Never returns user id. Rate-limit at the route (per IP + per user).
  String? lookupNameByEmail(String email, {required String exceptUserId}) {
    final mail = email.trim().toLowerCase();
    if (!_emailPattern.hasMatch(mail)) throw const AuthError(400, 'Bitte gib eine gültige E-Mail-Adresse ein.');
    final user = _byEmail(mail);
    if (user == null || user['id'] == exceptUserId) return null;
    return '${user['name']}';
  }

  static String _deviceLabel(String raw) {
    final clean = raw.replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), ' ').trim();
    if (clean.isEmpty) return '';
    return clean.length > 60 ? clean.substring(0, 60) : clean;
  }

  Future<String> _issueToken(String userId, {String device = ''}) async {
    final token = _random(32);
    _tokens[_digest(token)] = {
      'id': _random(8),
      'user': userId,
      'device': _deviceLabel(device),
      'createdAt': DateTime.now().toIso8601String(),
      'expires': DateTime.now().add(_tokenLifetime).toIso8601String(),
    };
    await _save();
    return token;
  }

  // returns {token, user}
  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String name,
    String device = '',
  }) async {
    final mail = email.trim().toLowerCase();
    if (!_emailPattern.hasMatch(mail)) throw const AuthError(400, 'Bitte gib eine gültige E-Mail-Adresse ein.');
    if (password.length < 8) throw const AuthError(400, 'Das Passwort braucht mindestens 8 Zeichen.');
    if (_byEmail(mail) != null) throw const AuthError(409, 'Für diese E-Mail gibt es schon ein Konto.');

    final clean = name.trim();
    if (clean.length > 60) throw const AuthError(400, 'Bitte gib einen Namen mit bis zu 60 Zeichen ein.');
    final id = _random(12);
    _users[id] = {
      'id': id,
      'email': mail,
      'name': clean.isEmpty ? mail.split('@').first : clean,
      'hash': BCrypt.hashpw(password, BCrypt.gensalt(logRounds: 11)),
      'createdAt': DateTime.now().toIso8601String(),
    };
    return {'token': await _issueToken(id, device: device), 'user': public(_users[id]!)};
  }

  String? emailOf(String userId) => _users[userId]?['email'] as String?;

  // step-up for destructive actions (account delete)
  void confirmPassword(String userId, String password) {
    final user = _users[userId];
    if (user == null) throw const AuthError(401, 'Bitte melde dich erneut an.');
    _checkPassword(user, password);
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    String device = '',
  }) async {
    final mail = email.trim().toLowerCase();
    final fail = _failures[mail];
    if (fail != null && fail.count >= _maxFailures && DateTime.now().isBefore(fail.until)) {
      throw AuthError.wait(fail.until.difference(DateTime.now()));
    }
    final user = _byEmail(mail);
    // same message for unknown email and wrong password, so emails can't be probed
    if (user == null || !BCrypt.checkpw(password, user['hash'] as String)) {
      final count = (fail != null && DateTime.now().isBefore(fail.until) ? fail.count : 0) + 1;
      _failures[mail] = (count: count, until: DateTime.now().add(_lockout));
      throw const AuthError(401, 'E-Mail oder Passwort ist falsch.');
    }
    _failures.remove(mail);
    if (user['totpSecret'] is String && (user['totpSecret'] as String).isNotEmpty) {
      _locked('totp:$mail');
      _pruneChallenges();
      final challenge = _random(32);
      _challenges[_digest(challenge)] = _PendingLogin(user['id'] as String, DateTime.now().add(const Duration(minutes: 5)));
      return {'needsTotp': true, 'challenge': challenge};
    }
    return {'token': await _issueToken(user['id'] as String, device: device), 'user': public(user)};
  }

  // the user behind a bearer token, or null when missing, unknown or expired
  Map<String, dynamic>? userFor(String? token) {
    if (token == null || token.isEmpty) return null;
    final t = _tokens[_digest(token)];
    if (t == null) return null;
    if (DateTime.now().isAfter(DateTime.parse(t['expires'] as String))) return null;
    return _users[t['user']];
  }

  Future<void> logout(String token) async {
    _tokens.remove(_digest(token));
    await _save();
  }

  // the password check shared by the changes below, with the same lockout as sign-in
  void _checkPassword(Map<String, dynamic> user, String password) {
    final mail = user['email'] as String;
    final fail = _failures[mail];
    if (fail != null && fail.count >= _maxFailures && DateTime.now().isBefore(fail.until)) {
      throw AuthError.wait(fail.until.difference(DateTime.now()));
    }
    if (!BCrypt.checkpw(password, user['hash'] as String)) {
      final count = (fail != null && DateTime.now().isBefore(fail.until) ? fail.count : 0) + 1;
      _failures[mail] = (count: count, until: DateTime.now().add(_lockout));
      throw const AuthError(403, 'Das aktuelle Passwort stimmt nicht.');
    }
    _failures.remove(mail);
  }

  Future<Map<String, dynamic>> changeName(String userId, String name) async {
    final user = _users[userId]!;
    final clean = name.trim();
    if (clean.isEmpty || clean.length > 60) throw const AuthError(400, 'Bitte gib einen Namen mit bis zu 60 Zeichen ein.');
    user['name'] = clean;
    await _save();
    return public(user);
  }

  Future<Map<String, dynamic>> changeEmail(String userId, String email, String password) async {
    final user = _users[userId]!;
    final mail = email.trim().toLowerCase();
    if (!_emailPattern.hasMatch(mail)) throw const AuthError(400, 'Bitte gib eine gültige E-Mail-Adresse ein.');
    _checkPassword(user, password);
    if (mail == user['email']) return public(user);
    if (_byEmail(mail) != null) throw const AuthError(409, 'Für diese E-Mail gibt es schon ein Konto.');
    user['email'] = mail;
    await _save();
    return public(user);
  }

  // new password; every other device is signed out, this one stays
  Future<void> changePassword(String userId, String current, String next, String keepToken) async {
    final user = _users[userId]!;
    _checkPassword(user, current);
    if (next.length < 8) throw const AuthError(400, 'Das neue Passwort braucht mindestens 8 Zeichen.');
    if (next == current) throw const AuthError(400, 'Das neue Passwort muss sich vom alten unterscheiden.');
    user['hash'] = BCrypt.hashpw(next, BCrypt.gensalt(logRounds: 11));
    _keepOnly(userId, keepToken);
    await _save();
  }

  // removes the user and every session of theirs
  Future<void> delete(String userId) async {
    _users.remove(userId);
    _tokens.removeWhere((_, t) => t['user'] == userId);
    _challenges.removeWhere((_, c) => c.userId == userId);
    await _save();
  }

  List<Map<String, dynamic>> sessions(String userId, {String? currentToken}) {
    final now = DateTime.now();
    final current = currentToken == null || currentToken.isEmpty ? null : _digest(currentToken);
    final out = <Map<String, dynamic>>[];
    for (final entry in _tokens.entries) {
      final token = entry.value;
      if (token['user'] != userId) continue;
      final expires = DateTime.tryParse('${token['expires']}');
      if (expires != null && now.isAfter(expires)) continue;
      out.add({
        'id': token['id'],
        'device': '${token['device'] ?? ''}',
        'createdAt': token['createdAt'],
        'current': entry.key == current,
      });
    }
    out.sort((a, b) {
      if (a['current'] == true) return -1;
      if (b['current'] == true) return 1;
      return '${b['createdAt']}'.compareTo('${a['createdAt']}');
    });
    return out;
  }

  Future<void> revokeSession(String userId, String sessionId) async {
    if (sessionId.isEmpty) throw const AuthError(400, 'Sitzung fehlt.');
    final before = _tokens.length;
    _tokens.removeWhere((_, t) => t['user'] == userId && t['id'] == sessionId);
    if (_tokens.length == before) throw const AuthError(404, 'Diese Sitzung gibt es nicht mehr.');
    await _save();
  }

  Future<void> logoutAll(String userId) async {
    _tokens.removeWhere((_, t) => t['user'] == userId);
    await _save();
  }

  // password already checked by the caller of login; this finishes 2FA
  Future<Map<String, dynamic>> loginTotp({
    required String challenge,
    required String code,
    String device = '',
    DateTime? now,
  }) async {
    _pruneChallenges();
    final key = _digest(challenge);
    final pending = _challenges[key];
    if (pending == null) {
      throw const AuthError(401, 'Die Anmeldung ist abgelaufen. Bitte melde dich erneut an.');
    }
    final user = _users[pending.userId];
    final secret = user?['totpSecret'] as String?;
    if (user == null || secret == null || secret.isEmpty) {
      _challenges.remove(key);
      throw const AuthError(401, 'Bitte melde dich erneut an.');
    }
    try {
      _acceptTotp(user, secret, code, now: now);
    } on AuthError catch (e) {
      if (e.status == 401) {
        pending.tries++;
        if (pending.tries >= _maxFailures) _challenges.remove(key);
      }
      rethrow;
    }
    _challenges.remove(key);
    return {'token': await _issueToken(user['id'] as String, device: device), 'user': public(user)};
  }

  Future<Map<String, dynamic>> beginTotp(String userId, String password) async {
    final user = _must(userId);
    _checkPassword(user, password);
    if (user['totpSecret'] is String && (user['totpSecret'] as String).isNotEmpty) {
      throw const AuthError(409, 'Zwei-Faktor ist schon aktiv.');
    }
    final secret = Totp.randomSecret();
    // shortcut: TOTP secret is plaintext in accounts.json, encrypt at rest when the user store is no longer one file
    user['totpPending'] = secret;
    await _save();
    final email = Uri.encodeComponent('${user['email']}');
    return {
      'secret': secret,
      'uri': 'otpauth://totp/BudgetBuddy:$email?secret=$secret&issuer=BudgetBuddy&algorithm=SHA1&digits=6&period=30',
    };
  }

  // enables 2FA and signs out every other device — those sessions never passed the new factor
  Future<Map<String, dynamic>> confirmTotp(String userId, String code, {String? keepToken, DateTime? now}) async {
    final user = _must(userId);
    final pending = user['totpPending'] as String?;
    if (pending == null || pending.isEmpty) throw const AuthError(400, 'Bitte starte die Einrichtung zuerst.');
    _acceptTotp(user, pending, code, now: now);
    user['totpSecret'] = pending;
    user.remove('totpPending');
    _keepOnly(userId, keepToken);
    await _save();
    return public(user);
  }

  Future<Map<String, dynamic>> disableTotp(
    String userId,
    String password,
    String code, {
    String? keepToken,
    DateTime? now,
  }) async {
    final user = _must(userId);
    _checkPassword(user, password);
    final secret = user['totpSecret'] as String?;
    if (secret == null || secret.isEmpty) return public(user);
    _acceptTotp(user, secret, code, now: now);
    user.remove('totpSecret');
    user.remove('totpStep');
    user.remove('totpPending');
    _keepOnly(userId, keepToken);
    await _save();
    return public(user);
  }

  Map<String, dynamic> _must(String userId) {
    final user = _users[userId];
    if (user == null) throw const AuthError(401, 'Bitte melde dich erneut an.');
    return user;
  }

  void _locked(String key) {
    final fail = _failures[key];
    if (fail != null && fail.count >= _maxFailures && DateTime.now().isBefore(fail.until)) {
      throw AuthError.wait(fail.until.difference(DateTime.now()));
    }
  }

  void _pruneChallenges() {
    final now = DateTime.now();
    _challenges.removeWhere((_, c) => !now.isBefore(c.expires));
  }

  // throws when the code is wrong, reused, or the email is briefly locked
  void _acceptTotp(Map<String, dynamic> user, String secret, String code, {DateTime? now}) {
    final key = 'totp:${user['email']}';
    _locked(key);
    final step = Totp.matchingStep(secret, code, now: now);
    final last = user['totpStep'];
    final lastStep = last is int ? last : (last is num ? last.toInt() : int.tryParse('$last') ?? -1);
    if (step == null || step <= lastStep) {
      final fail = _failures[key];
      final count = (fail != null && DateTime.now().isBefore(fail.until) ? fail.count : 0) + 1;
      _failures[key] = (count: count, until: DateTime.now().add(_lockout));
      throw AuthError(401, step != null ? 'Dieser Code wurde schon benutzt.' : 'Der Code stimmt nicht.');
    }
    _failures.remove(key);
    user['totpStep'] = step;
  }

  void _keepOnly(String userId, String? keepToken) {
    final keep = keepToken == null || keepToken.isEmpty ? null : _digest(keepToken);
    _tokens.removeWhere((digest, t) => t['user'] == userId && digest != keep);
  }
}

class _PendingLogin {
  final String userId;
  final DateTime expires;
  int tries = 0;
  _PendingLogin(this.userId, this.expires);
}
