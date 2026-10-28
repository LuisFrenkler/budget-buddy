// RFC 6238 TOTP (SHA-1, 30 seconds, 6 digits) using the crypto package.
// One step of skew is accepted. The caller stores the last accepted step
// and rejects it, so a code cannot be reused inside that window.
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class Totp {
  static const _stepSeconds = 30;
  static const _digits = 6;
  static const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  static String randomSecret([int length = 32]) {
    final rnd = Random.secure();
    return List.generate(length, (_) => _alphabet[rnd.nextInt(_alphabet.length)]).join();
  }

  // the 6-digit code for [time], for tests and for checking a verifier
  static String code(String secret, DateTime time) => _hotp(_decode(secret), _counter(time));

  // the time-step that matched, or null. [window] is steps of clock skew.
  static int? matchingStep(String secret, String code, {DateTime? now, int window = 1}) {
    final cleaned = code.replaceAll(RegExp(r'\s'), '');
    if (!RegExp(r'^\d{6}$').hasMatch(cleaned)) return null;
    final List<int> key;
    try {
      key = _decode(secret);
    } catch (_) {
      return null;
    }
    if (key.isEmpty) return null;
    final counter = _counter(now ?? DateTime.now());
    for (var delta = -window; delta <= window; delta++) {
      final step = counter + delta;
      if (step < 0) continue;
      if (_eq(_hotp(key, step), cleaned)) return step;
    }
    return null;
  }

  static int _counter(DateTime time) => time.toUtc().millisecondsSinceEpoch ~/ 1000 ~/ _stepSeconds;

  static List<int> _decode(String input) {
    final cleaned = input.toUpperCase().replaceAll(RegExp(r'[\s=]'), '');
    var buffer = 0;
    var bits = 0;
    final out = <int>[];
    for (final unit in cleaned.codeUnits) {
      final value = _alphabet.indexOf(String.fromCharCode(unit));
      if (value < 0) throw FormatException('bad base32');
      buffer = (buffer << 5) | value;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out.add((buffer >> bits) & 0xff);
      }
    }
    return out;
  }

  static String _hotp(List<int> key, int counter) {
    final msg = Uint8List(8);
    ByteData.sublistView(msg).setUint64(0, counter);
    final mac = Hmac(sha1, key).convert(msg).bytes;
    final offset = mac.last & 0x0f;
    final bin = ((mac[offset] & 0x7f) << 24) |
        ((mac[offset + 1] & 0xff) << 16) |
        ((mac[offset + 2] & 0xff) << 8) |
        (mac[offset + 3] & 0xff);
    return (bin % 1000000).toString().padLeft(_digits, '0');
  }

  static bool _eq(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
