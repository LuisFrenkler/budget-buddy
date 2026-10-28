// The signed-in user. Session token in secure storage; profile cached in
// settings. Finance data follows the Trade Republic model: the device only
// caches the current session — logout wipes it, login loads this account's
// vault from the server.
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'account_isolation.dart';
import 'backend_service.dart';
import 'cloud_sync.dart';
import 'secure_store.dart';
import 'settings_service.dart';
import 'split_service.dart';

class Account {
  final String id;
  final String email;
  final String name;
  final bool totp;
  const Account(this.id, this.email, this.name, {this.totp = false});

  factory Account.fromJson(Map j) =>
      Account('${j['id']}', '${j['email']}', '${j['name']}', totp: j['totp'] == true);
  Map<String, dynamic> toJson() => {'id': id, 'email': email, 'name': name, 'totp': totp};

  String get firstName => name.trim().split(' ').first;
}

// password was right, the account still wants a code from the authenticator app
class TotpRequired implements Exception {
  final String challenge;
  const TotpRequired(this.challenge);
  @override
  String toString() => 'Bitte gib den Code aus deiner Authenticator-App ein.';
}

class DeviceSession {
  final String id;
  final String device;
  final String? createdAt;
  final bool current;
  const DeviceSession({required this.id, required this.device, required this.createdAt, required this.current});

  String get label {
    if (device.isNotEmpty) return device;
    return current ? 'Dieses Gerät' : 'Unbekanntes Gerät';
  }
}

class AccountService {
  static const _tokenKey = 'bb_session_token';

  // null = not signed in; the root of the app listens to this
  static final current = ValueNotifier<Account?>(null);
  static String? _token;
  static String? get token => _token;

  static Box get _box => Hive.box('settings');

  // restores the session on app start; checks it with the server in the background
  static Future<void> restore() async {
    try {
      _token = await SecureStore.read(_tokenKey);
    } catch (_) {
      _token = null;
    }
    final cached = _box.get('account') as Map?;
    if (_token != null && cached != null) {
      final account = Account.fromJson(cached);
      // empty or wrong owner → wipe before claim (never adopt leftovers)
      final vault = '${_box.get('vaultOwner') ?? ''}';
      if (vault != account.id) await AccountIsolation.wipeLocalFinance();
      current.value = account;
      await AccountIsolation.claimLocalFor(account.id);
      await AccountIsolation.reconcileLinksWithServer();
    }
    if (_token != null) _verify();
  }

  // the server may have ended the session (deleted, expired); sign out then.
  // Offline is fine: the cached account stays.
  static Future<void> _verify() async {
    try {
      final res = await http
          .get(Uri.parse('${BackendService.base}/auth/me'), headers: {'Authorization': 'Bearer $_token'})
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 401) {
        await logout();
      } else if (res.statusCode == 200) {
        final map = jsonDecode(utf8.decode(res.bodyBytes));
        if (map is Map && map['user'] is Map) {
          final account = Account.fromJson(map['user'] as Map);
          await _box.put('account', account.toJson());
          current.value = account;
        }
      }
    } catch (_) {}
  }

  static String get _deviceLabel => switch (defaultTargetPlatform) {
        TargetPlatform.iOS => 'iPhone oder iPad',
        TargetPlatform.android => 'Android',
        TargetPlatform.macOS => 'Mac',
        TargetPlatform.windows => 'Windows',
        TargetPlatform.linux => 'Linux',
        TargetPlatform.fuchsia => 'Gerät',
      };

  static Future<Account> register({required String name, required String email, required String password}) =>
      _signIn('/auth/register', {'name': name, 'email': email, 'password': password});

  static Future<Account> login({required String email, required String password}) =>
      _signIn('/auth/login', {'email': email, 'password': password});

  static Future<Account> loginTotp({required String challenge, required String code}) => _signIn('/auth/login/totp', {
        'challenge': challenge,
        'code': code.trim(),
      });

  // new bearer token only — no cache wipe (for vault retry on web)
  static Future<void> refreshSession(String password) async {
    final account = current.value;
    if (account == null) throw 'Nicht angemeldet.';
    final map = await _post('/auth/login', {'email': account.email, 'password': password});
    final token = map['token'];
    if (token is! String || token.isEmpty) {
      throw 'Anmeldung ohne Sitzung — bitte App neu laden und noch einmal anmelden.';
    }
    _token = token;
    await SecureStore.write(_tokenKey, token);
  }

  static Future<Map<String, dynamic>> _post(String path, Map<String, String> body) async {
    final http.Response res;
    try {
      res = await http
          .post(Uri.parse('${BackendService.base}$path'),
              headers: {'Content-Type': 'application/json'}, body: jsonEncode({...body, 'device': _deviceLabel}))
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw 'Keine Verbindung zum Server. Bitte versuche es gleich noch einmal.';
    }
    final Map<String, dynamic> map;
    try {
      map = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw 'Der Server antwortet gerade nicht richtig. Bitte versuch es gleich noch einmal.';
    }
    if (res.statusCode == 401 && map['needsTotp'] == true && '${map['challenge'] ?? ''}'.isNotEmpty) {
      throw TotpRequired('${map['challenge']}');
    }
    if (res.statusCode != 200) throw map['error'] ?? 'Anmelden hat nicht geklappt. Bitte versuch es noch einmal.';
    return map;
  }

  static Future<Account> _signIn(String path, Map<String, String> body) async {
    final map = await _post(path, body);
    final account = Account.fromJson(map['user'] as Map);
    // invite deep-link must survive wipe (stored in settings)
    final invite = SplitService.pendingJoin;
    // stop stale vault pushes / sync watches before touching the cache
    await CloudSync.forget();
    // Trade Republic model: device starts empty for this session, then vault loads
    await AccountIsolation.wipeLocalFinance();
    if (invite != null) await SplitService.setPendingJoin(invite);

    _token = map['token'] as String;
    await SecureStore.write(_tokenKey, _token!);
    await _box.put('account', account.toJson());
    await Settings.setGuest(false); // clear legacy guest flag if present
    await AccountIsolation.claimLocalFor(account.id);
    current.value = account;
    return account;
  }

  // wipe the finance cache — next login loads this account from the server again
  static Future<void> logout() async {
    final token = _token;
    // cancel vault debounce / sync watches before clearing, so nothing writes back
    await CloudSync.forget();
    await AccountIsolation.wipeLocalFinance();
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
      await logout();
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

  // a signed-in call to the backend: GET without a body, POST with one
  static Future<Map<String, dynamic>> api(String path, {Map<String, dynamic>? body}) async {
    final http.Response res;
    try {
      final uri = Uri.parse('${BackendService.base}$path');
      final headers = {'Content-Type': 'application/json', 'Authorization': 'Bearer $_token'};
      res = await (body == null
              ? http.get(uri, headers: headers)
              : http.post(uri, headers: headers, body: jsonEncode(body)))
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw 'Keine Verbindung zum Server. Bitte versuche es gleich noch einmal.';
    }
    final map = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (res.statusCode == 401) {
      await logout();
      throw 'Deine Sitzung ist abgelaufen. Bitte melde dich neu an.';
    }
    if (res.statusCode != 200) throw map['error'] ?? 'Fehler ${res.statusCode}';
    return map;
  }

  static Future<void> changeName(String name) async => _update(await _authedPost('/auth/profile', {'name': name}));

  static Future<void> changeEmail(String email, String password) async =>
      _update(await _authedPost('/auth/email', {'email': email, 'password': password}));

  static Future<({String secret, String uri})> beginTotp(String password) async {
    final map = await _authedPost('/auth/totp/setup', {'password': password});
    final secret = '${map['secret'] ?? ''}';
    if (secret.isEmpty) throw 'Der Server hat keinen Schlüssel geschickt.';
    return (secret: secret, uri: '${map['uri'] ?? ''}');
  }

  static Future<void> confirmTotp(String code) async =>
      _update(await _authedPost('/auth/totp/confirm', {'code': code.trim()}));

  static Future<void> disableTotp(String password, String code) async =>
      _update(await _authedPost('/auth/totp/disable', {'password': password, 'code': code.trim()}));

  static Future<List<DeviceSession>> sessions() async {
    final map = await api('/auth/sessions');
    final raw = map['sessions'];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map)
          DeviceSession(
            id: '${item['id']}',
            device: '${item['device'] ?? ''}',
            createdAt: item['createdAt'] as String?,
            current: item['current'] == true,
          ),
    ];
  }

  static Future<void> revokeSession(String id) async {
    await api('/auth/sessions/revoke', body: {'id': id});
  }

  // ends every server session, including this phone, then wipes the local cache
  static Future<void> logoutEverywhere() async {
    await _authedPost('/auth/logout-all', {});
    await CloudSync.forget();
    await AccountIsolation.wipeLocalFinance();
    await _forget();
  }

  // exact email → display name for split invites, or null when unknown/self
  static Future<String?> lookupUserName(String email) async {
    final map = await api('/users/lookup', body: {'email': email.trim()});
    if (map['found'] != true) return null;
    final name = '${map['name'] ?? ''}';
    return name.isEmpty ? null : name;
  }

  // re-seal the vault with the new password first — only then flip the server
  // password. If the upload fails, the old password still works and the cloud
  // blob stays readable; never leave a new-password login against an old seal.
  static Future<void> changePassword(String current, String next) async {
    final id = AccountService.current.value?.id;
    if (id == null) throw 'Bitte melde dich neu an und versuch es noch einmal.';
    await CloudSync.unlock(id, next);
    await CloudSync.push(required: true, force: true);
    await _authedPost('/auth/password', {'current': current, 'next': next});
  }

  // deletes the account on the server (with all bank links), then locally
  static Future<void> deleteAccount(String password) async {
    final http.Response res;
    try {
      res = await http
          .delete(Uri.parse('${BackendService.base}/auth/account'),
              headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $_token'},
              body: jsonEncode({'password': password}))
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw 'Keine Verbindung zum Server. Bitte versuche es gleich noch einmal.';
    }
    if (res.statusCode == 401) {
      await logout();
      throw 'Deine Sitzung ist abgelaufen. Bitte melde dich neu an.';
    }
    if (res.statusCode == 403) {
      try {
        final map = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
        throw map['error'] ?? 'Das Passwort stimmt nicht.';
      } catch (e) {
        if (e is String) rethrow;
        throw 'Das Passwort stimmt nicht.';
      }
    }
    if (res.statusCode != 200) throw 'Löschen fehlgeschlagen (${res.statusCode})';
    // stop vault watches before wipe — same order as logout
    await CloudSync.forget();
    await AccountIsolation.wipeLocalFinance();
    await _forget();
  }

  static Future<void> _forget() async {
    // logout already forgot; other paths (delete) still need it
    await CloudSync.forget();
    _token = null;
    try {
      await SecureStore.delete(_tokenKey);
    } catch (_) {}
    await _box.delete('account');
    current.value = null;
  }
}
