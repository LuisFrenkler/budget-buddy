// Profile picture: stored locally and synced through the vault (same box as
// other settings). Any photo is scaled down on the device to [side] pixels on
// its short edge, so the vault stays small. Other users never see it, only
// the signed-in device(s).
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../l10n/l10n.dart';

class AvatarService {
  static const key = 'avatarBytes';
  static const maxBytes = 400 * 1024; // ~400 KB keeps vault push cheap
  static const side = 256; // sharp at 80 pt on a 3x screen

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

  // a small PNG of the photo, short edge [side] px; small images stay as they are
  static Future<Uint8List> shrink(Uint8List data) async {
    final ui.ImageDescriptor desc;
    try {
      desc = await ui.ImageDescriptor.encoded(await ui.ImmutableBuffer.fromUint8List(data));
    } catch (_) {
      throw tr('Das ist kein gültiges Foto.');
    }
    final scale = side / math.min(desc.width, desc.height);
    if (scale >= 1 && data.length <= maxBytes && _looksLikeImage(data)) return data;
    final codec = await desc.instantiateCodec(
      targetWidth: math.max(1, (desc.width * math.min(scale, 1)).round()),
      targetHeight: math.max(1, (desc.height * math.min(scale, 1)).round()),
    );
    final image = (await codec.getNextFrame()).image;
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (png == null) throw tr('Das Foto konnte nicht gelesen werden.');
    return png.buffer.asUint8List();
  }

  static Future<void> set(Uint8List data) async {
    if (data.isEmpty) throw tr('Das Bild ist leer.');
    data = await shrink(data);
    await _box.put(key, base64Encode(data));
    changed.value++;
  }

  static Future<void> clear() async {
    await _box.delete(key);
    changed.value++;
  }
}
