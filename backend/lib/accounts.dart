// User accounts: sign-up, sign-in, sessions and deletion.
//
// - Passwords are stored only as bcrypt hashes.
// - Session tokens are 256-bit random values; the server keeps only their
//   SHA-256, so a leaked store does not leak usable tokens.
// - Five wrong passwords lock an email for five minutes.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:bcrypt/bcrypt.dart';
import 'package:crypto/crypto.dart';

import 'json_store.dart';

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
  final _tokens = <String, Map<String, dynamic>>{}; // sha256(token) -> {user, expires}
  final _failures = <String, ({int count, DateTime until})>{};

  Accounts(this._store);

  Future<void> load() async {
    if (!await _store.exists()) return;
    final map = jsonDecode(await _store.readAsString()) as Map<String, dynamic>;
    (map['users'] as Map? ?? {}).forEach((k, v) => _users[k as String] = (v as Map).cast<String, dynamic>());
    (map['tokens'] as Map? ?? {}).forEach((k, v) => _tokens[k as String] = (v as Map).cast<String, dynamic>());
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

  // public view of a user, never the hash
  static Map<String, dynamic> public(Map<String, dynamic> u) =>
      {'id': u['id'], 'email': u['email'], 'name': u['name'], 'createdAt': u['createdAt']};

  Map<String, dynamic>? _byEmail(String email) {
    for (final u in _users.values) {
      if (u['email'] == email) return u;
    }
    return null;
  }

  Future<String> _issueToken(String userId) async {
    final token = _random(32);
    _tokens[_digest(token)] = {
      'user': userId,
      'expires': DateTime.now().add(_tokenLifetime).toIso8601String(),
    };
    await _save();
    return token;
  }

  // returns {token, user}
  Future<Map<String, dynamic>> register({required String email, required String password, required String name}) async {
    final mail = email.trim().toLowerCase();
    if (!_emailPattern.hasMatch(mail)) throw const AuthError(400, 'Bitte gib eine gültige E-Mail-Adresse ein.');
    if (password.length < 8) throw const AuthError(400, 'Das Passwort braucht mindestens 8 Zeichen.');
    if (_byEmail(mail) != null) throw const AuthError(409, 'Für diese E-Mail gibt es schon ein Konto.');

    final id = _random(12);
    _users[id] = {
      'id': id,
      'email': mail,
      'name': name.trim().isEmpty ? mail.split('@').first : name.trim(),
      'hash': BCrypt.hashpw(password, BCrypt.gensalt(logRounds: 11)),
      'createdAt': DateTime.now().toIso8601String(),
    };
    return {'token': await _issueToken(id), 'user': public(_users[id]!)};
  }

  Future<Map<String, dynamic>> login({required String email, required String password}) async {
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
    return {'token': await _issueToken(user['id'] as String), 'user': public(user)};
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
    final keep = _digest(keepToken);
    _tokens.removeWhere((digest, t) => t['user'] == userId && digest != keep);
    await _save();
  }

  // removes the user and every session of theirs
  Future<void> delete(String userId) async {
    _users.remove(userId);
    _tokens.removeWhere((_, t) => t['user'] == userId);
    await _save();
  }
}
