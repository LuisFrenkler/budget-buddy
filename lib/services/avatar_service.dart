// Profile picture: stored locally and synced through the vault (same box as
// other settings). Kept as JPEG/PNG/WebP bytes under a size cap so the vault
// stays small. Other users never see it — only the signed-in device(s).
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

class AvatarService {
  static const key = 'avatarBytes';
  static const maxBytes = 400 * 1024; // ~400 KB keeps vault push cheap

  static final changed = ValueNotifier<int>(0);

  static Box get _box => Hive.box('settings');

  static bool _looksLikeImage(Uint8List data) {
    if (data.length < 12) return false;
    // JPEG
    if (data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF) return true;
    // PNG
    if (data[0] == 0x89 && data[1] == 0x50 && data[2] == 0x4E && data[3] == 0x47) return true;
    // GIF
    if (data[0] == 0x47 && data[1] == 0x49 && data[2] == 0x46) return true;
    // WebP: RIFF....WEBP
    if (data[0] == 0x52 && data[1] == 0x49 && data[2] == 0x46 && data[3] == 0x46 &&
        data[8] == 0x57 && data[9] == 0x45 && data[10] == 0x42 && data[11] == 0x50) {
      return true;
    }
    return false;
  }

  static Uint8List? bytes() {
    final raw = _box.get(key);
    if (raw is! String || raw.isEmpty) return null;
    try {
      final data = Uint8List.fromList(base64Decode(raw));
      return _looksLikeImage(data) ? data : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> set(Uint8List data) async {
    if (data.isEmpty) throw 'Das Bild ist leer.';
    if (!_looksLikeImage(data)) throw 'Das ist kein gültiges Foto (JPEG, PNG, WebP oder GIF).';
    if (data.length > maxBytes) {
      throw 'Das Bild ist zu groß (max. ${maxBytes ~/ 1024} KB). Bitte nimm ein kleineres.';
    }
    await _box.put(key, base64Encode(data));
    changed.value++;
  }

  static Future<void> clear() async {
    await _box.delete(key);
    changed.value++;
  }
}
