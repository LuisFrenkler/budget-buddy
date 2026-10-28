// Keeps a signed-in user's data in their account, so it is there after a
// sign-in on any device.
//
// - The data is sealed on the device with AES-256-GCM. The key comes from
//   the password (PBKDF2), so the server stores text it cannot read, and a
//   forgotten password cannot be undone by anyone.
// - Every change is uploaded a few seconds later; on start a newer copy
//   from another device replaces the one here.
// shortcut: whole-copy, last writer wins. Two devices changing things at the
// same moment keep only the later upload; merge per record if that bites.
import 'dart:async';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'account_service.dart';
import 'backend_service.dart';
import 'backup_service.dart';
import 'bank_sync.dart';
import 'depot_sync.dart';

/// What [CloudSync.start] / a guarded push should do next.
enum VaultAction { push, apply, conflict, noop }

class CloudSync {
  static const _storage = FlutterSecureStorage();
  static const _keyName = 'bb_vault_key';
  static final _aes = AesGcm.with256bits();

  // what is saved besides the backup: the bank and depot links, so they
  // keep working on the next device, and which records are sample data
  static const _linkKeys = [
    'bankState', 'bankOwner', 'bankName', 'bankIban', 'bankValidUntil', 'bankBalanceCents', 'lastSync',
    'depotState', 'depotOwner', 'depotBroker', 'depotSync', 'depotHistory', 'bankLinks', 'depotLinks',
    // sample data stays removable on every device
    'demoKeys', 'demoOpeningBefore',
  ];
  static const _boxes = ['transactions', 'budgets', 'badges', 'holdings', 'recurring', 'goals', 'splits'];

  static SecretKey? _key;
  static bool _applying = false;
  static Timer? _debounce;
  static final _subs = <StreamSubscription>[];

  // remote vault waiting for the user to pick device vs cloud (dirty + newer)
  static final conflict = ValueNotifier<Map<String, dynamic>?>(null);

  static Box get _settings => Hive.box('settings');

  // the key for this account from its password
  static Future<SecretKey> deriveKey(String userId, String password, {int iterations = 210000}) =>
      Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256)
          .deriveKeyFromPassword(password: password, nonce: utf8.encode('budgetbuddy-vault:$userId'));

  static Future<String> seal(SecretKey key, String plain) async {
    final box = await _aes.encrypt(utf8.encode(plain), secretKey: key);
    return base64Encode(box.concatenation());
  }

  // throws when the key is wrong or the text was changed
  static Future<String> open(SecretKey key, String sealed) async {
    final box = SecretBox.fromConcatenation(base64Decode(sealed),
        nonceLength: _aes.nonceLength, macLength: _aes.macAlgorithm.macLength);
    return utf8.decode(await _aes.decrypt(box, secretKey: key));
  }

  // after sign-in, sign-up or a new password: remember the key and watch for changes
  static Future<void> unlock(String userId, String password) async {
    final key = await deriveKey(userId, password);
    _key = key;
    try {
      await _storage.write(key: _keyName, value: base64Encode(await key.extractBytes()));
    } catch (_) {}
    _watch();
  }

  // pure: dirty local edits must not silently overwrite a newer cloud copy
  @visibleForTesting
  static VaultAction decide({
    required bool dirty,
    required int localVersion,
    required int? remoteVersion,
  }) {
    if (remoteVersion == null) return VaultAction.push;
    final newer = remoteVersion > localVersion;
    if (dirty && newer) return VaultAction.conflict;
    if (dirty) return VaultAction.push;
    if (newer) return VaultAction.apply;
    return VaultAction.noop;
  }

  // on app start with a saved session
  static Future<void> start() async {
    if (AccountService.token == null) return;
    try {
      final saved = await _storage.read(key: _keyName);
      if (saved != null) _key = SecretKey(base64Decode(saved));
    } catch (_) {}
    if (_key == null) return; // signed in before sync existed: starts with the next sign-in
    _watch();
    try {
      final remote = await fetch();
      final local = _settings.get('vaultVersion') as int? ?? 0;
      final remoteVersion = remote == null ? null : (remote['version'] as int? ?? 0);
      final dirty = _settings.get('vaultDirty') == true;
      switch (decide(dirty: dirty, localVersion: local, remoteVersion: remoteVersion)) {
        case VaultAction.push:
          await push();
        case VaultAction.apply:
          await apply(remote!);
        case VaultAction.conflict:
          conflict.value = remote;
        case VaultAction.noop:
          break;
      }
    } catch (_) {
      // offline: the next change or start tries again
    }
  }

  // user chose to keep local edits over the newer cloud copy
  static Future<void> keepDevice() async {
    conflict.value = null;
    await push(force: true);
  }

  // user chose the cloud copy; local dirty edits are discarded
  static Future<void> keepCloud() async {
    final remote = conflict.value;
    conflict.value = null;
    if (remote != null) await apply(remote);
  }

  static Future<void> forget() async {
    _key = null;
    conflict.value = null;
    _debounce?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    try {
      await _storage.delete(key: _keyName);
    } catch (_) {}
  }

  // this device holds data of the signed-in account (or none at all)
  static bool ownsLocalData(String userId) => _settings.get('vaultOwner') == userId;

  // the account's sealed copy, or null when there is none yet
  static Future<Map<String, dynamic>?> fetch() async {
    final res = await http.get(Uri.parse('${BackendService.base}/vault'),
        headers: {'Authorization': 'Bearer ${AccountService.token}'}).timeout(const Duration(seconds: 20));
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) throw 'Sicherung nicht erreichbar (${res.statusCode})';
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  // replaces the data here with the account's copy
  static Future<void> apply(Map<String, dynamic> remote) async {
    final key = _key;
    if (key == null) return;
    final payload = jsonDecode(await open(key, remote['data'] as String)) as Map<String, dynamic>;
    _applying = true;
    try {
      await BackupService.restoreFromJson(payload['backup'] as String);
      final links = (payload['links'] as Map?) ?? const {};
      for (final k in _linkKeys) {
        links.containsKey(k) ? await _settings.put(k, links[k]) : await _settings.delete(k);
      }
      await _settings.put('vaultVersion', remote['version']);
      await _settings.put('vaultOwner', AccountService.current.value?.id);
      await _settings.delete('vaultDirty');
    } finally {
      _applying = false;
    }
    // the links came with the copy: bring their numbers up to date
    unawaited(BankSync.refreshIfStale());
    unawaited(DepotSync.refreshIfStale());
  }

  // uploads the data here as the account's copy
  // [required]: throw when the server refuses (password change, sign-up)
  // [force]: upload even if the cloud copy is newer (user chose "Gerät behalten")
  static Future<void> push({bool required = false, bool force = false}) async {
    final key = _key;
    if (key == null || AccountService.token == null) {
      if (required) throw 'Sicherung konnte nicht hochgeladen werden.';
      return;
    }
    await _settings.put('vaultDirty', true);
    if (!force) {
      try {
        final remote = await fetch();
        if (remote != null) {
          final remoteVersion = remote['version'] as int? ?? 0;
          final local = _settings.get('vaultVersion') as int? ?? 0;
          if (remoteVersion > local) {
            conflict.value = remote;
            if (required) {
              throw 'Auf einem anderen Gerät gibt es neuere Daten. Bitte wähle, welche Kopie gelten soll.';
            }
            return;
          }
        }
      } catch (e) {
        if (required && e is String) rethrow;
        // offline: still try the upload below
      }
    }
    final payload = jsonEncode({
      'backup': BackupService.toBackupJson(),
      'links': {for (final k in _linkKeys) if (_settings.containsKey(k)) k: _settings.get(k)},
    });
    final res = await http
        .post(Uri.parse('${BackendService.base}/vault'),
            headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${AccountService.token}'},
            body: jsonEncode({'data': await seal(key, payload)}))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      if (required) throw 'Sicherung konnte nicht hochgeladen werden (${res.statusCode}). Bitte bleib online und versuch es noch einmal.';
      return; // stays dirty: the next change or start tries again
    }
    await _settings.put('vaultVersion', (jsonDecode(res.body) as Map)['version']);
    await _settings.put('vaultOwner', AccountService.current.value?.id);
    await _settings.delete('vaultDirty');
  }

  static void _watch() {
    if (_subs.isNotEmpty) return;
    final watched = {...BackupService.settingKeys, ..._linkKeys};
    for (final name in _boxes) {
      if (Hive.isBoxOpen(name)) _subs.add(Hive.box(name).watch().listen((_) => _changed()));
    }
    _subs.add(_settings.watch().listen((e) {
      if (watched.contains(e.key)) _changed();
    }));
  }

  static void _changed() {
    if (_applying || _key == null) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 4), () => push().catchError((_) {}));
  }
}
