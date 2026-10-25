// Small typed wrapper around the 'settings' Hive box for app preferences.
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

  // dark vs light theme (defaults to dark)
  static bool get darkMode => _box.get('darkMode', defaultValue: true) as bool;

  static Future<void> setDarkMode(bool value) => _box.put('darkMode', value);

  // GoCardless requisition id of a linked bank (empty = not linked)
  static String get gcRequisitionId => _box.get('gcRequisitionId', defaultValue: '') as String;

  static Future<void> setGcRequisitionId(String value) => _box.put('gcRequisitionId', value);
}
