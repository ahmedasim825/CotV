import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../models/user_settings.dart';
import '../repositories/user_settings_repository.dart';
import '../storage/local_storage.dart';

final userSettingsBoxProvider = Provider<Box<UserSettings>>(
  (ref) => Hive.box<UserSettings>(HiveBoxes.userSettings),
);

final userSettingsRepositoryProvider = Provider<UserSettingsRepository>((ref) {
  return HiveUserSettingsRepository(ref.watch(userSettingsBoxProvider));
});

/// The persisted settings record, reactively updated.
///
/// [UserSettings.isBiometricEnabled] here is a read-only mirror kept in
/// sync by [AppLockController.setBiometricEnabled] (see
/// `security_providers.dart`) — the actual toggle lives in secure storage
/// via [SecurityService], since that's the encrypted store appropriate for
/// a security-relevant flag. Don't write it directly through this
/// controller; go through `appLockControllerProvider` so the two stay in
/// sync.
class UserSettingsController extends StreamNotifier<UserSettings> {
  UserSettingsRepository get _repository => ref.read(userSettingsRepositoryProvider);

  @override
  Stream<UserSettings> build() => _repository.watch();

  Future<void> setPreAdhanMinutes(int minutes) async {
    final current = _repository.get();
    await _repository.update(
      current.copyWith(preAdhanNotificationMinutes: minutes),
    );
  }

  Future<void> setLocation({required double latitude, required double longitude}) async {
    final current = _repository.get();
    await _repository.update(
      current.copyWith(latitude: latitude, longitude: longitude),
    );
  }
}

final userSettingsControllerProvider =
    StreamNotifierProvider<UserSettingsController, UserSettings>(
  UserSettingsController.new,
);
