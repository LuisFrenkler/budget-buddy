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
import 'package:cryptography/dart.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'account_isolation.dart';
import 'account_service.dart';
import 'backend_service.dart';
import 'backup_service.dart';
import 'bank_sync.dart';
import 'depot_sync.dart';
import 'secure_store.dart';

/// What [CloudSync.start] / a guarded push should do next.
enum VaultAction { push, apply, conflict, noop }

class CloudSync {
  static const _legacyKeyName = 'bb_vault_key';
  static String _keyNameFor(String userId) => 'bb_vault_key:$userId';
  // Always Dart (not Web Crypto): same vault bytes on HTTPS, HTTP LAN and native.
  static final _crypto = DartCryptography();
  static final _aes = _crypto.aesGcm(secretKeyLength: 32);

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
  static String? _keyUserId; // which account _key / secure-storage entry belongs to
  static bool _applying = false;
  static Timer? _debounce;
  static final _subs = <StreamSubscription>[];
  // bumped in forget() so in-flight apply/push abort after logout
  static int _generation = 0;

  // remote vault waiting for the user to pick device vs cloud (dirty + newer)
  static final conflict = ValueNotifier<Map<String, dynamic>?>(null);

  static Box get _settings => Hive.box('settings');

  static bool get isUnlocked =>
      _key != null && _keyUserId != null && _keyUserId == AccountService.current.value?.id;

  // the key for this account from its password
  static Future<SecretKey> deriveKey(String userId, String password, {int iterations = 210000}) =>
      _crypto
          .pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256)
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
    _keyUserId = userId;
    try {
      await SecureStore.write(_keyNameFor(userId), base64Encode(await key.extractBytes()));
      await SecureStore.delete(_legacyKeyName); // drop unbound legacy slot
    } catch (_) {}
    _watch();
  }

  // login / vault-banner retry: fresh session, unlock, then pull or seed vault
  static Future<void> loadAccountData(String password) async {
    final account = AccountService.current.value;
    if (account == null) throw 'Nicht angemeldet.';
    await AccountService.refreshSession(password);
    await unlock(account.id, password);
    final remote = await fetch();
    if (remote == null) {
      await push(required: true);
    } else {
      await apply(remote, required: true);
    }
    await _settings.delete('vaultLoadFailed');
  }

  // LAN / phone test: keep using the app without cloud until the next login
  static Future<void> skipCloudForNow() async {
    await _settings.delete('vaultLoadFailed');
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

  // true while this start/apply/push still belongs to the same cache + account + sync gen
  static bool _stillThisSession(int epoch, String? uid, int generation) =>
      _generation == generation &&
      AccountIsolation.sameEpoch(epoch) &&
      AccountService.current.value?.id == uid;

  // on app start with a saved session
  static Future<void> start() async {
    if (AccountService.token == null) return;
    final epoch = AccountIsolation.epoch;
    final uid = AccountService.current.value?.id;
    final generation = _generation;
    if (uid == null) return;
    try {
      // prefer per-user key; migrate legacy unbound slot once
      var saved = await SecureStore.read(_keyNameFor(uid));
      if (saved == null) {
        saved = await SecureStore.read(_legacyKeyName);
        if (saved != null) {
          await SecureStore.write(_keyNameFor(uid), saved);
          await SecureStore.delete(_legacyKeyName);
        }
      }
      if (saved != null) {
        _key = SecretKey(base64Decode(saved));
        _keyUserId = uid;
      }
    } catch (_) {}
    if (_key == null || _keyUserId != uid) return; // signed in before sync / wrong key
    if (!_stillThisSession(epoch, uid, generation)) return;
    _watch();
    try {
      final vaultOwner = '${_settings.get('vaultOwner') ?? ''}';
      // never upload another identity's leftovers into this account's vault
      final foreign = (vaultOwner.isNotEmpty && vaultOwner != uid) ||
          (vaultOwner.isEmpty && AccountIsolation.hasFinanceData);
      if (foreign) {
        await AccountIsolation.wipeLocalFinance();
        if (!_stillThisSession(epoch, uid, generation)) return;
        await AccountIsolation.claimLocalFor(uid);
      }
      final remote = await fetch();
      if (!_stillThisSession(epoch, uid, generation)) return;
      final local = _settings.get('vaultVersion') as int? ?? 0;
      final remoteVersion = remote == null ? null : (remote['version'] as int? ?? 0);
      final dirty = _settings.get('vaultDirty') == true;
      switch (decide(dirty: dirty, localVersion: local, remoteVersion: remoteVersion)) {
        case VaultAction.push:
          // no server vault yet: never invent one from device leftovers
          if (remote == null && AccountIsolation.hasFinanceData && !ownsLocalData(uid)) {
            await AccountIsolation.wipeLocalFinance();
            if (!_stillThisSession(epoch, uid, generation)) return;
            await AccountIsolation.claimLocalFor(uid);
          } else {
            await push();
          }
        case VaultAction.apply:
          await apply(remote!);
        case VaultAction.conflict:
          // never silently overwrite dirty local edits — HomeScreen asks Gerät vs Konto
          if (remote != null && _stillThisSession(epoch, uid, generation)) conflict.value = remote;
        case VaultAction.noop:
          break;
      }
      if (!_stillThisSession(epoch, uid, generation)) return;
      await _settings.delete('vaultLoadFailed');
      await AccountIsolation.reconcileLinksWithServer();
    } catch (_) {
      // offline: the next change or start tries again
    }
  }

  // user chose to keep local edits over the newer cloud copy
  static Future<void> keepDevice() async {
    final remote = conflict.value;
    conflict.value = null;
    // never force-overwrite cloud after a failed first load of this account
    if (_settings.get('vaultLoadFailed') == true) {
      throw 'Deine Kontodaten konnten noch nicht geladen werden. Bitte warte und versuch es noch einmal.';
    }
    // OCC: claim the remote version we are replacing, then push
    if (remote != null) {
      await _settings.put('vaultVersion', remote['version'] as int? ?? 0);
    }
    await push(force: true);
  }

  // user chose the cloud copy; local dirty edits are discarded
  static Future<void> keepCloud() async {
    final remote = conflict.value;
    conflict.value = null;
    if (remote != null) await apply(remote);
  }

  static Future<void> forget() async {
    _generation++; // abort in-flight apply/push at the next await
    final uid = _keyUserId;
    _key = null;
    _keyUserId = null;
    conflict.value = null;
    _debounce?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    try {
      if (uid != null) await SecureStore.delete(_keyNameFor(uid));
      await SecureStore.delete(_legacyKeyName);
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
  static Future<void> apply(Map<String, dynamic> remote, {bool required = false}) async {
    final key = _key;
    if (key == null) {
      if (required) throw 'Vault-Schlüssel fehlt. Bitte Passwort erneut eingeben.';
      return;
    }
    final epoch = AccountIsolation.epoch;
    final uid = AccountService.current.value?.id;
    final generation = _generation;
    final Map<String, dynamic> payload;
    try {
      payload = jsonDecode(await open(key, remote['data'] as String)) as Map<String, dynamic>;
    } catch (e) {
      if (required) {
        throw 'Sicherung lässt sich nicht öffnen. Stimmt das Passwort? ($e)';
      }
      rethrow;
    }
    if (!_stillThisSession(epoch, uid, generation)) {
      if (required) throw 'Sitzung hat gewechselt. Bitte noch einmal versuchen.';
      return;
    }
    _applying = true;
    try {
      final rawBackup = payload['backup'];
      final backupJson = rawBackup is String
          ? rawBackup
          : rawBackup == null
              ? null
              : jsonEncode(rawBackup);
      if (backupJson == null || backupJson.isEmpty) {
        throw 'Sicherung ist leer oder beschädigt.';
      }
      try {
        await BackupService.restoreFromJson(backupJson);
      } catch (e) {
        if (required) throw 'Daten konnten lokal nicht geschrieben werden ($e)';
        rethrow;
      }
      if (!_stillThisSession(epoch, uid, generation)) {
        if (required) throw 'Sitzung hat gewechselt. Bitte noch einmal versuchen.';
        return;
      }
      final links = (payload['links'] as Map?) ?? const {};
      for (final k in _linkKeys) {
        final v = BackupService.stripNulls(links[k]);
        if (v == null) {
          await _settings.delete(k);
        } else {
          await _settings.put(k, v);
        }
      }
      // vault is per-account on the server; stamp owners to this session so a
      // restored copy can never look like another user's leftovers
      if (uid != null && uid.isNotEmpty) {
        await _settings.put('vaultOwner', uid);
        if ((_settings.get('bankState') as String?)?.isNotEmpty == true ||
            (_settings.get('bankLinks') as List?)?.isNotEmpty == true) {
          await _settings.put('bankOwner', uid);
        }
        if ((_settings.get('depotState') as String?)?.isNotEmpty == true ||
            (_settings.get('depotLinks') as List?)?.isNotEmpty == true) {
          await _settings.put('depotOwner', uid);
        }
      }
      await _settings.put('vaultVersion', remote['version'] as int? ?? 0);
      await _settings.delete('vaultDirty');
      await _settings.delete('vaultLoadFailed');
    } finally {
      _applying = false;
    }
    if (!_stillThisSession(epoch, uid, generation)) return;
    // drop consents the server no longer has, then refresh what remains
    await AccountIsolation.reconcileLinksWithServer();
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
    final epoch = AccountIsolation.epoch;
    final uid = AccountService.current.value?.id;
    final generation = _generation;
    // never seed an empty vault over a good cloud copy after a failed first load
    if (_settings.get('vaultLoadFailed') == true) {
      if (required) throw 'Deine Kontodaten konnten noch nicht geladen werden. Bitte warte kurz und versuch es noch einmal.';
      return;
    }
    if (uid != null && !ownsLocalData(uid) && AccountIsolation.hasFinanceData) {
      if (required) throw 'Sicherung konnte nicht hochgeladen werden.';
      return;
    }
    await _settings.put('vaultDirty', true);
    if (!force) {
      try {
        final remote = await fetch();
        if (!_stillThisSession(epoch, uid, generation)) return;
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
    if (!_stillThisSession(epoch, uid, generation)) return;
    final payload = jsonEncode({
      'backup': BackupService.toBackupJson(),
      'links': {for (final k in _linkKeys) if (_settings.containsKey(k)) k: _settings.get(k)},
    });
    // always send OCC version (0 = first upload); force only skips the local newer-check
    final expected = _settings.get('vaultVersion') as int? ?? 0;
    final sealed = await seal(key, payload);
    if (!_stillThisSession(epoch, uid, generation)) return;
    final res = await http
        .post(Uri.parse('${BackendService.base}/vault'),
            headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${AccountService.token}'},
            body: jsonEncode({
              'data': sealed,
              'expectedVersion': expected,
            }))
        .timeout(const Duration(seconds: 30));
    if (!_stillThisSession(epoch, uid, generation)) return;
    if (res.statusCode == 409) {
      try {
        final remote = await fetch();
        if (remote != null && _stillThisSession(epoch, uid, generation)) conflict.value = remote;
      } catch (_) {}
      if (required) throw 'Auf einem anderen Gerät gibt es neuere Daten. Bitte wähle, welche Kopie gelten soll.';
      return;
    }
    if (res.statusCode != 200) {
      if (required) throw 'Sicherung konnte nicht hochgeladen werden (${res.statusCode}). Bitte bleib online und versuch es noch einmal.';
      return; // stays dirty: the next change or start tries again
    }
    await _settings.put('vaultVersion', (jsonDecode(res.body) as Map)['version']);
    await _settings.put('vaultOwner', uid);
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
