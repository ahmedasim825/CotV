import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Thrown when biometric authentication fails for a reason the user can
/// act on (no biometrics enrolled, hardware unavailable, temporarily
/// locked out, etc) — as opposed to a plain cancel, which just returns
/// `false` from [SecurityService.authenticate].
class SecurityException implements Exception {
  SecurityException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => 'SecurityException: $message';
}

/// Biometric authentication (Face ID / Touch ID / device passcode
/// fallback) via `local_auth`, plus a securely-persisted on/off preference
/// via `flutter_secure_storage`.
///
/// This service only performs the authentication challenge and stores the
/// user's preference — it doesn't decide *when* to lock the app. That's
/// [AppLockController] (see `providers/security_providers.dart`), which
/// reacts to cold start and `AppLifecycleState` transitions and calls back
/// into this service.
class SecurityService {
  SecurityService({
    LocalAuthentication? localAuthentication,
    FlutterSecureStorage? secureStorage,
  })  : _localAuth = localAuthentication ?? LocalAuthentication(),
        _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const String _biometricEnabledKey = 'security.biometric_enabled';

  final LocalAuthentication _localAuth;
  final FlutterSecureStorage _secureStorage;

  /// Whether this device can authenticate at all — biometrics, or a
  /// passcode/PIN/pattern fallback.
  Future<bool> isDeviceSupported() => _localAuth.isDeviceSupported();

  /// Whether biometric hardware with at least one enrolled credential is
  /// available right now.
  Future<bool> canCheckBiometrics() => _localAuth.canCheckBiometrics;

  Future<List<BiometricType>> availableBiometrics() =>
      _localAuth.getAvailableBiometrics();

  /// The user's saved preference. Defaults to `false` (disabled) until the
  /// user explicitly opts in, since enabling a device lock unprompted
  /// would be surprising.
  Future<bool> isBiometricEnabled() async {
    final value = await _secureStorage.read(key: _biometricEnabledKey);
    return value == 'true';
  }

  Future<void> setBiometricEnabled(bool enabled) => _secureStorage.write(
        key: _biometricEnabledKey,
        value: enabled.toString(),
      );

  /// Prompts Face ID / Touch ID, falling back to the device passcode.
  ///
  /// Returns `true` on success and `false` if the user cancelled, backed
  /// out to the fallback and cancelled that too, or simply failed the
  /// challenge — all of which the caller should treat as "still locked,"
  /// not an error. Throws [SecurityException] for failures the user needs
  /// to be told about (no biometrics enrolled, hardware unavailable,
  /// lockout, etc).
  Future<bool> authenticate({
    String reason = 'Authenticate to unlock Prayer Lockout',
  }) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        sensitiveTransaction: true,
      );
    } on LocalAuthException catch (e) {
      switch (e.code) {
        case LocalAuthExceptionCode.userCanceled:
        case LocalAuthExceptionCode.systemCanceled:
        case LocalAuthExceptionCode.userRequestedFallback:
        case LocalAuthExceptionCode.timeout:
          return false;
        default:
          throw SecurityException(_messageFor(e.code), e);
      }
    }
  }

  String _messageFor(LocalAuthExceptionCode code) {
    switch (code) {
      case LocalAuthExceptionCode.noBiometricHardware:
        return 'This device has no biometric hardware.';
      case LocalAuthExceptionCode.noBiometricsEnrolled:
        return 'No Face ID or Touch ID is enrolled on this device.';
      case LocalAuthExceptionCode.noCredentialsSet:
        return 'No passcode or biometrics are set up on this device. '
            'Set one up in Settings to use app lock.';
      case LocalAuthExceptionCode.biometricLockout:
      case LocalAuthExceptionCode.temporaryLockout:
        return 'Biometric authentication is temporarily locked. Try '
            'again later or use your passcode.';
      case LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable:
        return 'Biometric hardware is temporarily unavailable.';
      case LocalAuthExceptionCode.uiUnavailable:
        return 'Could not display the authentication prompt.';
      case LocalAuthExceptionCode.authInProgress:
        return 'An authentication attempt is already in progress.';
      case LocalAuthExceptionCode.deviceError:
      case LocalAuthExceptionCode.unknownError:
      default:
        return 'Authentication failed. Please try again.';
    }
  }
}
