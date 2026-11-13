// App language. The German text is the key (like gettext): code stays
// readable, and a missing translation falls back to German instead of a
// blank. test/l10n_test.dart fails when a tr('…') text has no English entry.
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'en.dart';

class L10n {
  static const supported = ['de', 'en'];
  static const names = {'de': 'Deutsch', 'en': 'English'};

  // current language code; the app root rebuilds everything when it changes
  static final lang = ValueNotifier<String>('de');

  static bool get isDe => lang.value == 'de';

  // intl locale for numbers and currency
  static String get intlLocale => isDe ? 'de_DE' : 'en_IE';

  // saved choice, else the device language, else English
  static void load() {
    final saved = Hive.box('settings').get('lang') as String?;
    final device = PlatformDispatcher.instance.locale.languageCode;
    _apply(saved ?? (supported.contains(device) ? device : 'en'));
  }

  static Future<void> set(String code) async {
    _apply(code);
    await Hive.box('settings').put('lang', code);
  }

  static void _apply(String code) {
    Intl.defaultLocale = code == 'de' ? 'de_DE' : 'en_IE';
    lang.value = code;
  }
}

const _tables = <String, Map<String, String>>{'en': en};

// Translates a German text. Placeholders are written {name} and filled from
// args, so the translation can move them: tr('{n} im Jahr', {'n': x}).
String tr(String de, [Map<String, Object?> args = const {}]) {
  var s = L10n.isDe ? de : (_tables[L10n.lang.value]?[de] ?? de);
  args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  return s;
}
