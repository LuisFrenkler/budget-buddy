// Session / vault keys. On native and HTTPS web → FlutterSecureStorage.
// On plain HTTP (LAN phone test) Web Crypto is blocked, so Hive is the fallback.
// shortcut: Hive is not OS-encrypted; switch to HTTPS before any public web deploy.
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

class SecureStore {
  static const _secure = FlutterSecureStorage();
  static const _prefix = 'sec_';

  static Box get _box => Hive.box('settings');

  // http://192.168… is not a secure context; localhost / https are
  static bool get _hiveFallback {
    if (!kIsWeb) return false;
    final u = Uri.base;
    if (u.isScheme('https')) return false;
    final h = u.host;
    return h != 'localhost' && h != '127.0.0.1';
  }

  static Future<String?> read(String key) async {
    if (_hiveFallback) return _box.get('$_prefix$key') as String?;
    try {
      return await _secure.read(key: key);
    } catch (_) {
      return _box.get('$_prefix$key') as String?;
    }
  }

  static Future<void> write(String key, String value) async {
    if (_hiveFallback) {
      await _box.put('$_prefix$key', value);
      return;
    }
    try {
      await _secure.write(key: key, value: value);
    } catch (_) {
      await _box.put('$_prefix$key', value);
    }
  }

  static Future<void> delete(String key) async {
    if (_hiveFallback) {
      await _box.delete('$_prefix$key');
      return;
    }
    try {
      await _secure.delete(key: key);
    } catch (_) {
      await _box.delete('$_prefix$key');
    }
  }
}
