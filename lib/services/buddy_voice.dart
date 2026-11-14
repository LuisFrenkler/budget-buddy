// Buddy reads his answers aloud, with the device's own voice (nothing leaves
// the phone). After a spoken question he answers out loud by himself, so a
// conversation can happen without looking at the screen.
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../l10n/l10n.dart';
import 'buddy_markers.dart';

class BuddyVoice {
  static FlutterTts? _tts;
  // the text being read right now, so its button can show "Stopp"
  static final speaking = ValueNotifier<String?>(null);

  // what a voice should say: no markdown, no markers, numbers stay
  static String speakable(String text) {
    var t = BuddyMarkers.parse(text).text;
    t = t.replaceAll('**', '').replaceAll(RegExp(r'^\s*[-•*]\s+', multiLine: true), '');
    t = t.replaceAll(RegExp(r'^(Nächster Schritt|Next step):', multiLine: true, caseSensitive: false),
        L10n.isDe ? 'Nächster Schritt:' : 'Next step:');
    return t.replaceAll(RegExp(r'\n{2,}'), '. ').replaceAll('\n', ' ').trim();
  }

  static Future<FlutterTts> _ready() async {
    final tts = _tts ??= FlutterTts();
    await tts.setLanguage(L10n.isDe ? 'de-DE' : 'en-US');
    await tts.setSpeechRate(kIsWeb ? 1.0 : 0.5);
    tts.setCompletionHandler(() => speaking.value = null);
    tts.setCancelHandler(() => speaking.value = null);
    tts.setErrorHandler((_) => speaking.value = null);
    return tts;
  }

  static Future<void> speak(String text) async {
    try {
      final tts = await _ready();
      await tts.stop();
      speaking.value = text;
      await tts.speak(speakable(text));
    } catch (_) {
      speaking.value = null;
    }
  }

  static Future<void> stop() async {
    speaking.value = null;
    try {
      await _tts?.stop();
    } catch (_) {}
  }

  static Future<void> toggle(String text) => speaking.value == text ? stop() : speak(text);
}
