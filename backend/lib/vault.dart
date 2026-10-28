// Each account's data, encrypted on the device with a key from the user's
// password. The server only keeps the sealed text and cannot read it.
//
// Writes for one user are serialized and always optimistic-locked so two
// devices cannot both "win" and drop a sealed backup.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'accounts.dart';
import 'json_store.dart';

class Vault {
  final String dir;
  final _locks = <String, Future<void>>{};

  Vault(this.dir);

  // user ids are server-made hex strings, so they are safe as file names
  File _file(String userId) => File('$dir/$userId.json');

  Future<T> _withLock<T>(String userId, Future<T> Function() fn) async {
    final previous = _locks[userId] ?? Future<void>.value();
    final gate = Completer<void>();
    _locks[userId] = gate.future;
    await previous.catchError((_) {});
    try {
      return await fn();
    } finally {
      gate.complete();
      if (identical(_locks[userId], gate.future)) _locks.remove(userId);
    }
  }

  Future<Map<String, dynamic>?> get(String userId) async {
    final f = _file(userId);
    if (!await f.exists()) return null;
    return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
  }

  // stores a new sealed copy and returns its version.
  // [expectedVersion] must match the current version (0 = none yet) or the
  // write is rejected with 409 so two devices cannot silently overwrite.
  Future<int> put(String userId, Object? data, {required int expectedVersion}) async {
    if (data is! String || data.isEmpty || data.length > 12 << 20) {
      throw const AuthError(400, 'Die Sicherung ist ungültig oder zu groß.');
    }
    return _withLock(userId, () async {
      final current = (await get(userId))?['version'] as int? ?? 0;
      if (expectedVersion != current) {
        throw const AuthError(409, 'Auf einem anderen Gerät gibt es neuere Daten.');
      }
      final version = current + 1;
      await writeJsonAtomic(_file(userId), {
        'version': version,
        'updatedAt': DateTime.now().toIso8601String(),
        'data': data,
      });
      return version;
    });
  }

  Future<void> delete(String userId) => _withLock(userId, () async {
        final f = _file(userId);
        if (await f.exists()) await f.delete();
      });
}
