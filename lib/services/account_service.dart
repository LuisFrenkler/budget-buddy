// The signed-in user. The session token lives in the platform's secure
// storage (Keychain on iOS, Keystore on Android); name and email are cached
// in the settings box so the app starts instantly, also offline.
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'backend_service.dart';
import 'settings_service.dart';

class Account {
  final String id;
  final String email;
  final String name;
  const Account(this.id, this.email, this.name);

  factory Account.fromJson(Map j) => Account('${j['id']}', '${j['email']}', '${j['name']}');
  Map<String, String> toJson() => {'id': id, 'email': email, 'name': name};

  String get firstName => name.trim().split(' ').first;
}

class AccountService {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'bb_session_token';

  // null = not signed in; the root of the app listens to this
  static final current = ValueNotifier<Account?>(null);
  static String? _token;
  static String? get token => _token;

  static Box get _box => Hive.box('settings');

  // restores the session on app start; checks it with the server in the background
  static Future<void> restore() async {
    try {
      _token = await _storage.read(key: _tokenKey);
    } catch (_) {
      _token = null;
    }
    final cached = _box.get('account') as Map?;
    if (_token != null && cached != null) current.value = Account.fromJson(cached);
    if (_token != null) _verify();
  }

  // the server may have ended the session (deleted, expired); sign out then.
  // Offline is fine: the cached account stays.
  static Future<void> _verify() async {
    try {
      final res = await http
          .get(Uri.parse('${BackendService.base}/auth/me'), headers: {'Authorization': 'Bearer $_token'})
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 401) await _forget();
    } catch (_) {}
  }

  static Future<Account> register({required String name, required String email, required String password}) =>
      _signIn('/auth/register', {'name': name, 'email': email, 'password': password});

  static Future<Account> login({required String email, required String password}) =>
      _signIn('/auth/login', {'email': email, 'password': password});

  static Future<Account> _signIn(String path, Map<String, String> body) async {
    final http.Response res;
    try {
      res = await http
          .post(Uri.parse('${BackendService.base}$path'),
              headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw 'Keine Verbindung zum Server. Bitte versuche es gleich noch einmal.';
    }
    final map = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (res.statusCode != 200) throw map['error'] ?? 'Fehler ${res.statusCode}';

    final account = Account.fromJson(map['user'] as Map);
    _token = map['token'] as String;
    await _storage.write(key: _tokenKey, value: _token);
    await _box.put('account', account.toJson());
    await Settings.setGuest(false);
    // a bank linked by someone else on this device is not theirs to see
    if (Settings.bankOwner.isNotEmpty && Settings.bankOwner != account.id) await Settings.clearBank();
    current.value = account;
    return account;
  }

  static Future<void> logout() async {
    final token = _token;
    await _forget();
    if (token == null) return;
    try {
      await http.post(Uri.parse('${BackendService.base}/auth/logout'), headers: {'Authorization': 'Bearer $token'});
    } catch (_) {}
  }

  // a signed-in request; throws the server's German message on failure
  static Future<Map<String, dynamic>> _authedPost(String path, Map<String, String> body) async {
    final http.Response res;
    try {
      res = await http
          .post(Uri.parse('${BackendService.base}$path'),
              headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_token'},
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw 'Keine Verbindung zum Server. Bitte versuche es gleich noch einmal.';
    }
    final map = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (res.statusCode == 401) {
      await _forget();
      throw 'Deine Sitzung ist abgelaufen. Bitte melde dich neu an.';
    }
    if (res.statusCode != 200) throw map['error'] ?? 'Fehler ${res.statusCode}';
    return map;
  }

  static Future<void> _update(Map<String, dynamic> map) async {
    final account = Account.fromJson(map['user'] as Map);
    await _box.put('account', account.toJson());
    current.value = account;
  }

  static Future<void> changeName(String name) async => _update(await _authedPost('/auth/profile', {'name': name}));

  static Future<void> changeEmail(String email, String password) async =>
      _update(await _authedPost('/auth/email', {'email': email, 'password': password}));

  // other devices are signed out by the server, this one stays signed in
  static Future<void> changePassword(String current, String next) =>
      _authedPost('/auth/password', {'current': current, 'next': next});

  // deletes the account on the server (with all bank links), then locally
  static Future<void> deleteAccount() async {
    final res = await http.delete(Uri.parse('${BackendService.base}/auth/account'),
        headers: {'Authorization': 'Bearer $_token'}).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200 && res.statusCode != 401) throw 'Löschen fehlgeschlagen (${res.statusCode})';
    await Settings.clearBank();
    await _forget();
  }

  static Future<void> _forget() async {
    _token = null;
    try {
      await _storage.delete(key: _tokenKey);
    } catch (_) {}
    await _box.delete('account');
    current.value = null;
  }
}
