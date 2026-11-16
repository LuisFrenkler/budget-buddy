// Talk to Buddy: speech to text on the device (iOS/macOS speech framework,
// Android's recognizer, the browser's Web Speech API). The words land in
// the input field; nothing is sent until the person taps send.
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

class VoiceInput {
  static final _speech = SpeechToText();
  static bool? _ready;

  // true while the microphone is open
  static final listening = ValueNotifier<bool>(false);

  static Future<bool> available() async {
    if (_ready != null) return _ready!;
    try {
      _ready = await _speech.initialize(
        onStatus: (s) => listening.value = s == SpeechToText.listeningStatus,
        onError: (_) => listening.value = false,
      );
    } catch (_) {
      _ready = false;
    }
    return _ready!;
  }

  // [onText] gets the words so far, [done] true with the final result
  static Future<bool> start(void Function(String text, bool done) onText) async {
    if (!await available()) return false;
    listening.value = true;
    await _speech.listen(
      onResult: (r) => onText(r.recognizedWords, r.finalResult),
      localeId: 'de_DE',
      listenOptions: SpeechListenOptions(partialResults: true, cancelOnError: true, listenMode: ListenMode.dictation),
      pauseFor: const Duration(seconds: 3),
      listenFor: const Duration(seconds: 45),
    );
    return true;
  }

  static Future<void> stop() async {
    listening.value = false;
    try {
      await _speech.stop();
    } catch (_) {}
  }
}
