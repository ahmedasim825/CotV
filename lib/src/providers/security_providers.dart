import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../security/security_service.dart';
import 'user_settings_providers.dart';

enum AppLockStatus { locked, unlocked }

/// Current lock state plus the user's biometric-enabled preference, kept
/// together so the UI never has to reconcile two separate providers.
class AppLockState {
  const AppLockState({
    required this.status,
    required this.biometricEnabled,
    this.errorMessage,
  });

  final AppLockStatus status;
  final bool biometricEnabled;

  /// Set when the last [AppLockController.unlock] attempt hit a
  /// [SecurityException] (not a plain cancel) — e.g. no biometrics
  /// enrolled, hardware locked out. Cleared on the next attempt.
  final String? errorMessage;

  bool get isLocked => status == AppLockStatus.locked;

  AppLockState copyWith({
    AppLockStatus? status,
    bool? biometricEnabled,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AppLockState(
      status: status ?? this.status,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

final securityServiceProvider = Provider<SecurityService>((ref) => SecurityService());

/// What this device can actually authenticate with, so the settings screen
/// can name the real mechanism ("Face ID", "Touch ID") and explain itself
/// when app lock is unavailable, instead of offering a switch that would
/// only fail at the prompt.
class BiometricCapability {
  const BiometricCapability({
    required this.deviceSupported,
    required this.biometricsAvailable,
    required this.types,
  });

  /// The device can authenticate at all — biometrics, or a passcode / PIN /
  /// pattern fallback.
  final bool deviceSupported;

  /// Biometric hardware with at least one enrolled credential is ready now.
  final bool biometricsAvailable;

  final List<BiometricType> types;

  /// What to call the primary mechanism in the UI.
  String get label {
    if (!deviceSupported) return 'Unavailable';
    if (types.contains(BiometricType.face)) return 'Face ID';
    if (types.contains(BiometricType.fingerprint)) return 'Touch ID';
    if (types.contains(BiometricType.iris)) return 'Iris';
    if (biometricsAvailable) return 'Biometrics';
    return 'Device passcode';
  }

  /// The one-line explanation under the app-lock switch.
  String get description {
    if (!deviceSupported) {
      return 'This device has no passcode or biometrics set up, so app '
          'lock cannot be turned on.';
    }
    if (!biometricsAvailable) {
      return 'No biometrics are enrolled. App lock will fall back to your '
          'device passcode.';
    }
    return 'Require $label whenever the app is opened or resumed.';
  }
}

/// Queried once per app run and refreshed by invalidating this provider —
/// enrolment can change while the app is backgrounded (the user adds a
/// fingerprint in Settings), so the security screen invalidates it on
/// resume rather than trusting a value from launch.
final biometricCapabilityProvider =
    FutureProvider<BiometricCapability>((ref) async {
  final service = ref.watch(securityServiceProvider);
  final deviceSupported = await service.isDeviceSupported();
  final biometricsAvailable = await service.canCheckBiometrics();
  final types = deviceSupported
      ? await service.availableBiometrics()
      : const <BiometricType>[];

  return BiometricCapability(
    deviceSupported: deviceSupported,
    biometricsAvailable: biometricsAvailable,
    types: types,
  );
});

/// Owns whether the app is locked. [SecurityGate] is the only widget that
/// should call [lockIfEnabled]/[unlock] directly — everything else just
/// watches this provider to decide what to render.
class AppLockController extends AsyncNotifier<AppLockState> {
  @override
  Future<AppLockState> build() async {
    final service = ref.watch(securityServiceProvider);
    final enabled = await service.isBiometricEnabled();
    // Cold start: lock immediately if the user has opted in.
    return AppLockState(
      status: enabled ? AppLockStatus.locked : AppLockStatus.unlocked,
      biometricEnabled: enabled,
    );
  }

  /// Re-locks the app if biometrics are enabled. Called by [SecurityGate]
  /// on a `paused` -> `resumed` lifecycle transition. A no-op while the
  /// initial state is still loading, while already locked, or while
  /// biometrics are disabled.
  void lockIfEnabled() {
    final current = state.value;
    if (current == null) return;
    if (current.biometricEnabled && current.status == AppLockStatus.unlocked) {
      state = AsyncData(
        current.copyWith(status: AppLockStatus.locked, clearError: true),
      );
    }
  }

  /// Runs the Face ID/Touch ID/passcode challenge. On success, unlocks. On
  /// cancel, stays locked with no error. On a real failure, stays locked
  /// and populates [AppLockState.errorMessage].
  Future<void> unlock() async {
    final current = state.value;
    if (current == null || current.status == AppLockStatus.unlocked) return;

    final service = ref.read(securityServiceProvider);
    try {
      final success = await service.authenticate();
      state = AsyncData(
        current.copyWith(
          status: success ? AppLockStatus.unlocked : AppLockStatus.locked,
          clearError: true,
        ),
      );
    } on SecurityException catch (e) {
      state = AsyncData(current.copyWith(errorMessage: e.message));
    }
  }

  /// Persists the biometric-enabled preference and updates lock state to
  /// match — disabling it unlocks immediately rather than leaving the user
  /// stuck behind a lock screen for a feature they just turned off.
  ///
  /// This is the single place that toggle should be written from: it
  /// writes the authoritative copy to secure storage via [SecurityService]
  /// and mirrors the same value into the persisted [UserSettings] record,
  /// so the two never disagree.
  Future<void> setBiometricEnabled(bool enabled) async {
    final service = ref.read(securityServiceProvider);
    await service.setBiometricEnabled(enabled);

    final settingsRepository = ref.read(userSettingsRepositoryProvider);
    final settings = settingsRepository.get();
    await settingsRepository.update(settings.copyWith(isBiometricEnabled: enabled));

    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        biometricEnabled: enabled,
        status: enabled ? current.status : AppLockStatus.unlocked,
        clearError: true,
      ),
    );
  }
}

final appLockControllerProvider =
    AsyncNotifierProvider<AppLockController, AppLockState>(AppLockController.new);
