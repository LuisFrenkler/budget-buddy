// The signed-in user. The session token lives in the platform's secure
// storage (Keychain on iOS, Keystore on Android); name and email are cached
// in the settings box so the app starts instantly, also offline.
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'account_isolation.dart';
import 'backend_service.dart';
import 'cloud_sync.dart';
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
    if (_token != null && cached != null) {
      final account = Account.fromJson(cached);
      current.value = account;
      await _ensureLinksBelongTo(account.id);
    }
    if (_token != null) _verify();
  }

  // after a crash or an old build: never leave another account's bank/depot visible
  static Future<void> _ensureLinksBelongTo(String accountId) async {
    final vault = '${_box.get('vaultOwner') ?? ''}';
    Future<void> fix({
      required bool linked,
      required String owner,
      required Future<void> Function() clear,
      required Future<void> Function() claim,
    }) async {
      if (!linked) return;
      if (owner == accountId) return;
      // old builds stored the link without an owner: keep only if the vault is ours
      if (owner.isEmpty && vault == accountId) {
        await claim();
        return;
      }
      await clear();
    }

    await fix(
      linked: Settings.bankState.isNotEmpty || Settings.extraBanks.isNotEmpty,
      owner: Settings.bankOwner,
      clear: Settings.clearBank,
      claim: () => Settings.setBankOwner(accountId),
    );
    await fix(
      linked: Settings.depotState.isNotEmpty || Settings.extraDepots.isNotEmpty,
      owner: Settings.depotOwner,
      clear: Settings.clearDepot,
      claim: () => Settings.setDepotOwner(accountId),
    );
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
    final Map<String, dynamic> map;
    try {
      map = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      // e.g. a proxy's error page instead of the server's answer
      throw 'Der Server antwortet gerade nicht richtig. Bitte versuch es gleich noch einmal.';
    }
    if (res.statusCode != 200) throw map['error'] ?? 'Anmelden hat nicht geklappt. Bitte versuch es noch einmal.';

    final account = Account.fromJson(map['user'] as Map);
    // capture before we flip guest off — guest upgrades may keep their own entries
    final wasGuest = Settings.guest.value;
    final keep = AccountIsolation.mayKeepLocal(
      accountId: account.id,
      vaultOwner: '${_box.get('vaultOwner') ?? ''}',
      bankOwner: Settings.bankOwner,
      depotOwner: Settings.depotOwner,
      hasBankOrDepotLinks: AccountIsolation.hasBankOrDepotLinks,
      hasFinanceData: AccountIsolation.hasFinanceData,
      wasGuest: wasGuest,
    );
    if (!keep) await AccountIsolation.wipeLocalFinance();

    _token = map['token'] as String;
    await _storage.write(key: _tokenKey, value: _token);
    await _box.put('account', account.toJson());
    await Settings.setGuest(false);
    await Settings.setSignedOutEmail('');
    await AccountIsolation.claimLocalFor(account.id);
    current.value = account; // PlusService.watchAccount reloads entitlement for this user
    return account;
  }

  // the data stays on the device for the next sign-in; until then it is
  // closed to guests (see WelcomeScreen)
  static Future<void> logout() async {
    final token = _token;
    final email = current.value?.email ?? '';
    await _forget();
    await Settings.setSignedOutEmail(email);
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
      await _forget();
      throw 'Deine Sitzung ist abgelaufen. Bitte melde dich neu an.';
    }
    if (res.statusCode != 200) throw map['error'] ?? 'Fehler ${res.statusCode}';
    return map;
  }

  static Future<void> changeName(String name) async => _update(await _authedPost('/auth/profile', {'name': name}));

  static Future<void> changeEmail(String email, String password) async =>
      _update(await _authedPost('/auth/email', {'email': email, 'password': password}));

  // other devices are signed out by the server, this one stays signed in
  // the account's data is sealed with the new password from now on —
  // the upload must succeed, or a new device with the new password cannot open it
  static Future<void> changePassword(String current, String next) async {
    await _authedPost('/auth/password', {'current': current, 'next': next});
    final id = AccountService.current.value?.id;
    if (id == null) return;
    await CloudSync.unlock(id, next);
    await CloudSync.push(required: true, force: true);
  }

  // deletes the account on the server (with all bank links), then locally
  static Future<void> deleteAccount() async {
    final res = await http.delete(Uri.parse('${BackendService.base}/auth/account'),
        headers: {'Authorization': 'Bearer $_token'}).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200 && res.statusCode != 401) throw 'Löschen fehlgeschlagen (${res.statusCode})';
    await Settings.clearBank();
    await Settings.clearDepot();
    await _forget();
  }

  static Future<void> _forget() async {
    await CloudSync.forget();
    _token = null;
    try {
      await _storage.delete(key: _tokenKey);
    } catch (_) {}
    await _box.delete('account');
    current.value = null;
  }
}
