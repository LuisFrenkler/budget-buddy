// Small typed wrapper around the 'settings' Hive box for app preferences.
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

class Settings {
  static Box get _box => Hive.box('settings');

  // whether the biometric / PIN app lock is enabled
  static bool get appLockEnabled =>
      _box.get('appLockEnabled', defaultValue: false) as bool;

  static Future<void> setAppLockEnabled(bool value) =>
      _box.put('appLockEnabled', value);

  // whether the user has seen the onboarding intro
  static bool get onboardingDone =>
      _box.get('onboardingDone', defaultValue: false) as bool;

  static Future<void> setOnboardingDone(bool value) =>
      _box.put('onboardingDone', value);

  // privacy mode: balances show as dots, e.g. when others can see the screen.
  // A notifier so every amount on screen hides or shows at once.
  static final hideAmounts = ValueNotifier<bool>(false);

  static void loadHideAmounts() => hideAmounts.value = _box.get('hideAmounts', defaultValue: false) as bool;

  static Future<void> setHideAmounts(bool value) {
    hideAmounts.value = value;
    return _box.put('hideAmounts', value);
  }

  // dark vs light theme (defaults to dark)
  static bool get darkMode => _box.get('darkMode', defaultValue: true) as bool;

  static Future<void> setDarkMode(bool value) => _box.put('darkMode', value);

  // "try without an account": the app works fully offline, no bank link.
  // A notifier so the root can switch between welcome and app.
  static final guest = ValueNotifier<bool>(false);

  static void loadGuest() => guest.value = _box.get('guest', defaultValue: false) as bool;

  static Future<void> setGuest(bool value) {
    guest.value = value;
    return _box.put('guest', value);
  }

  // id of the account that linked the bank on this device
  static String get bankOwner => _box.get('bankOwner', defaultValue: '') as String;

  static Future<void> setBankOwner(String value) => _box.put('bankOwner', value);

  // token of the linked bank on the backend (empty = not linked)
  static String get bankState => _box.get('bankState', defaultValue: '') as String;

  static Future<void> setBankState(String value) => _box.put('bankState', value);

  // name, IBAN and consent expiry of the linked bank, for display
  static String get bankName => _box.get('bankName', defaultValue: '') as String;
  static String get bankIban => _box.get('bankIban', defaultValue: '') as String;
  static DateTime? get bankValidUntil => _date('bankValidUntil');

  static Future<void> setBankInfo({required String name, String? iban, DateTime? validUntil}) async {
    await _box.put('bankName', name);
    await _box.put('bankIban', iban ?? '');
    await _box.put('bankValidUntil', validUntil?.millisecondsSinceEpoch);
  }

  // balance the bank reported at the last sync, in cents
  static int get bankBalanceCents => _box.get('bankBalanceCents', defaultValue: 0) as int;

  static Future<void> setBankBalanceCents(int value) => _box.put('bankBalanceCents', value);

  // balance before the first booking in the app, so the Kontostand matches
  // the bank although its history starts only a few months back
  static int get openingBalanceCents => _box.get('openingBalanceCents', defaultValue: 0) as int;

  static Future<void> setOpeningBalanceCents(int value) => _box.put('openingBalanceCents', value);

  static DateTime? get lastSync => _date('lastSync');

  static Future<void> setLastSync(DateTime? value) => _box.put('lastSync', value?.millisecondsSinceEpoch);

  // forgets the linked bank; the imported bookings stay
  static Future<void> clearBank() async {
    for (final k in ['bankState', 'bankOwner', 'bankName', 'bankIban', 'bankValidUntil', 'bankBalanceCents', 'lastSync']) {
      await _box.delete(k);
    }
  }

  // back to a fresh install: every setting except the theme
  static Future<void> resetApp() async {
    final dark = darkMode;
    await _box.clear();
    await setDarkMode(dark);
    guest.value = false;
    hideAmounts.value = false;
  }

  static DateTime? _date(String key) {
    final ms = _box.get(key) as int?;
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }
}
