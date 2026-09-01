import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../models/user_settings.dart';

/// Access to the single persisted [UserSettings] record.
abstract class UserSettingsRepository {
  /// Emits the current settings immediately and again on every change.
  /// Never empty — falls back to [UserSettings]'s defaults if nothing has
  /// been saved yet.
  Stream<UserSettings> watch();

  UserSettings get();

  Future<void> update(UserSettings settings);
}

class HiveUserSettingsRepository implements UserSettingsRepository {
  HiveUserSettingsRepository(this._box);

  final Box<UserSettings> _box;

  @override
  UserSettings get() => _box.get(UserSettings.defaultId) ?? UserSettings();

  @override
  Stream<UserSettings> watch() async* {
    yield get();
    yield* _box.watch(key: UserSettings.defaultId).map((_) => get());
  }

  @override
  Future<void> update(UserSettings settings) =>
      _box.put(UserSettings.defaultId, settings);
}
