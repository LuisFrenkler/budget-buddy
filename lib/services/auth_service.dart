import 'package:flutter/foundation.dart';
// Thin wrapper around local_auth for the app lock.
//
// Everything is defensive: on platforms or devices without biometrics/PIN
// (web, desktop, a bare simulator) the methods fail safe so the user can
// never get locked out of their own data.
import 'package:local_auth/local_auth.dart';

class AuthService {
  static final LocalAuthentication _auth = LocalAuthentication();

  // tests replace the device check and the prompt
  @visibleForTesting
  static Future<bool> Function()? debugAvailable;
  @visibleForTesting
  static Future<bool> Function()? debugAuthenticate;
  @visibleForTesting
  static Future<List<BiometricType>> Function()? debugBiometrics;

  // true if the device can do biometrics or a device passcode
  static Future<bool> isAvailable() async {
    if (debugAvailable != null) return debugAvailable!();
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  // subtitle under "App-Sperre": Face ID, fingerprint or a generic device lock
  static Future<String> lockSubtitle() async {
    try {
      final types = debugBiometrics != null ? await debugBiometrics!() : await _auth.getAvailableBiometrics();
      if (types.contains(BiometricType.face) || types.contains(BiometricType.iris)) {
        return 'Face ID oder Code beim Öffnen';
      }
      if (types.contains(BiometricType.fingerprint) ||
          types.contains(BiometricType.strong) ||
          types.contains(BiometricType.weak)) {
        return 'Fingerabdruck oder PIN beim Öffnen';
      }
    } catch (_) {}
    return defaultTargetPlatform == TargetPlatform.iOS
        ? 'Face ID oder Code beim Öffnen'
        : 'Gerätecode beim Öffnen';
  }

  // prompts the user to authenticate. returns true on success.
  // biometricOnly is false so a device PIN/passcode works as a fallback.
  static Future<bool> authenticate(String reason) async {
    if (debugAuthenticate != null) return debugAuthenticate!();
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
