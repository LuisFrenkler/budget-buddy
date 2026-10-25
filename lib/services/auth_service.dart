// Thin wrapper around local_auth for the app lock.
//
// Everything is defensive: on platforms or devices without biometrics/PIN
// (web, desktop, a bare simulator) the methods fail safe so the user can
// never get locked out of their own data.
import 'package:local_auth/local_auth.dart';

class AuthService {
  static final LocalAuthentication _auth = LocalAuthentication();

  // true if the device can do biometrics or a device passcode
  static Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  // prompts the user to authenticate. returns true on success.
  // biometricOnly is false so a device PIN/passcode works as a fallback.
  static Future<bool> authenticate(String reason) async {
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
