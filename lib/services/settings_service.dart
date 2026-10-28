// Small typed wrapper around the 'settings' Hive box for app preferences.
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../utils/money.dart';

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

  static void loadHideAmounts() {
    hideAmounts.value = _box.get('hideAmounts', defaultValue: false) as bool;
    Money.masked = hideAmounts.value;
  }

  static Future<void> setHideAmounts(bool value) {
    Money.masked = value;
    hideAmounts.value = value;
    return _box.put('hideAmounts', value);
  }

  // dark vs light theme (defaults to dark)
  static bool get darkMode => _box.get('darkMode', defaultValue: true) as bool;

  static Future<void> setDarkMode(bool value) => _box.put('darkMode', value);

  // legacy: older installs stored guest mode; always clear it (account required)
  static Future<void> setGuest(bool _) async {
    await _box.delete('guest');
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

  // token of the linked depot (Parqet Connect) on the backend, empty = none
  static String get depotState => _box.get('depotState', defaultValue: '') as String;
  static String get depotBroker => _box.get('depotBroker', defaultValue: '') as String;
  static DateTime? get depotSync => _date('depotSync');

  static Future<void> setDepot(String state, {String broker = ''}) async {
    await _box.put('depotState', state);
    await _box.put('depotBroker', broker);
  }

  static Future<void> setDepotSync(DateTime value) => _box.put('depotSync', value.millisecondsSinceEpoch);

  // the linked depot's value per day as Parqet reports it, oldest first
  static List<(DateTime, int)> get depotHistory => [
        for (final e in (_box.get('depotHistory') as List? ?? const []))
          (DateTime.fromMillisecondsSinceEpoch((e as List)[0] as int), e[1] as int),
      ];

  static Future<void> setDepotHistory(List<(DateTime, int)> points) =>
      _box.put('depotHistory', [for (final (d, c) in points) [d.millisecondsSinceEpoch, c]]);

  // depots linked after the first one (another Parqet login): [{state, broker}]
  static List<({String state, String broker})> get extraDepots => [
        for (final m in (_box.get('depotLinks') as List?) ?? const [])
          if (m is Map) (state: '${m['state']}', broker: '${m['broker'] ?? ''}'),
      ];

  static Future<void> setExtraDepots(List<({String state, String broker})> links) =>
      _box.put('depotLinks', [for (final l in links) {'state': l.state, 'broker': l.broker}]);

  static Future<void> clearDepot() async {
    for (final k in ['depotState', 'depotBroker', 'depotSync', 'depotHistory', 'depotLinks', 'depotOwner']) {
      await _box.delete(k);
    }
  }

  // forgets only the first depot link; extras (depotLinks) stay
  static Future<void> clearPrimaryDepot() async {
    for (final k in ['depotState', 'depotBroker', 'depotSync', 'depotHistory', 'depotOwner']) {
      await _box.delete(k);
    }
  }

  // id of the account that linked the depot on this device
  static String get depotOwner => _box.get('depotOwner', defaultValue: '') as String;

  static Future<void> setDepotOwner(String value) => _box.put('depotOwner', value);

  // banks linked after the first one: [{state, bank}]
  static List<({String state, String bank})> get extraBanks => [
        for (final m in (_box.get('bankLinks') as List?) ?? const [])
          if (m is Map) (state: '${m['state']}', bank: '${m['bank'] ?? ''}'),
      ];

  static Future<void> addExtraBank(String state, String bank) => _box.put('bankLinks', [
        for (final l in extraBanks) {'state': l.state, 'bank': l.bank},
        {'state': state, 'bank': bank},
      ]);

  static Future<void> removeExtraBank(String state) => _box.put('bankLinks', [
        for (final l in extraBanks)
          if (l.state != state) {'state': l.state, 'bank': l.bank},
      ]);

  // forgets the linked bank; the imported bookings stay
  static Future<void> clearBank() async {
    for (final k in ['bankState', 'bankOwner', 'bankName', 'bankIban', 'bankValidUntil', 'bankBalanceCents', 'lastSync', 'bankLinks']) {
      await _box.delete(k);
    }
  }

  // back to a fresh install: every setting except the theme
  static Future<void> resetApp() async {
    final dark = darkMode;
    await _box.clear();
    await setDarkMode(dark);
    hideAmounts.value = false;
    Money.masked = false;
  }

  static DateTime? _date(String key) {
    final ms = _box.get(key) as int?;
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }
}
