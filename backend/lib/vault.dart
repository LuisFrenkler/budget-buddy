// Each account's data, encrypted on the device with a key from the user's
// password. The server only keeps the sealed text and cannot read it.
import 'dart:convert';
import 'dart:io';

import 'accounts.dart';
import 'json_store.dart';

class Vault {
  final String dir;
  Vault(this.dir);

  // user ids are server-made hex strings, so they are safe as file names
  File _file(String userId) => File('$dir/$userId.json');

  Future<Map<String, dynamic>?> get(String userId) async {
    final f = _file(userId);
    if (!await f.exists()) return null;
    return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
  }

  // stores a new sealed copy and returns its version
  Future<int> put(String userId, Object? data) async {
    if (data is! String || data.isEmpty || data.length > 12 << 20) {
      throw const AuthError(400, 'Die Sicherung ist ungültig oder zu groß.');
    }
    final version = ((await get(userId))?['version'] as int? ?? 0) + 1;
    await writeJsonAtomic(_file(userId), {
      'version': version,
      'updatedAt': DateTime.now().toIso8601String(),
      'data': data,
    });
    return version;
  }

  Future<void> delete(String userId) async {
    final f = _file(userId);
    if (await f.exists()) await f.delete();
  }
}
