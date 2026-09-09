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

  /// Turns Milo's spoken replies on or off.
  Future<void> setSpeaksReplies(bool value) async {
    final current = _repository.get();
    await _repository.update(current.copyWith(speaksReplies: value));
  }

  /// Arms or disarms always-on listening for the wake word.
  Future<void> setListensForWakeWord(bool value) async {
    final current = _repository.get();
    await _repository.update(current.copyWith(listensForWakeWord: value));
  }

  /// Persists which platform voice Milo speaks with.
  Future<void> setVoiceName(String voiceName) async {
    final current = _repository.get();
    await _repository.update(current.copyWith(voiceName: voiceName));
  }

  /// Persists what Milo has learned about the user.
  ///
  /// An empty string clears it, which is how "forget me" is expressed —
  /// `copyWith` treats null as "leave unchanged", so null could not.
  Future<void> setAiMemorySummary(String summary) async {
    final current = _repository.get();
    await _repository.update(current.copyWith(aiMemorySummary: summary));
  }

  /// Persists the daily nutrition goals.
  ///
  /// Every field is written with a concrete number rather than a null,
  /// because `copyWith` reads null as "leave unchanged" and so cannot
  /// express a reset — the targets sheet writes the defaults back instead.
  Future<void> setNutritionTargets({
    required int calories,
    required int protein,
    required int carbs,
    required int fat,
  }) async {
    final current = _repository.get();
    await _repository.update(
      current.copyWith(
        dailyCalorieTarget: calories,
        proteinTargetGrams: protein,
        carbTargetGrams: carbs,
        fatTargetGrams: fat,
      ),
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
