import 'package:flutter_riverpod/flutter_riverpod.dart';

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
