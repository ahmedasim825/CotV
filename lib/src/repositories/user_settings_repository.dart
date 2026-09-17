import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../models/user_settings.dart';
import 'hive_repository_utils.dart';
import 'syncable_repository.dart';

/// Access to the single persisted [UserSettings] record.
abstract class UserSettingsRepository {
  /// Emits the current settings immediately and again on every change.
  /// Never empty — falls back to [UserSettings]'s defaults if nothing has
  /// been saved yet.
  Stream<UserSettings> watch();

  UserSettings get();

  Future<void> update(UserSettings settings);
}

class HiveUserSettingsRepository
    implements UserSettingsRepository, SyncableRepository<UserSettings> {
  HiveUserSettingsRepository(this._box, [this._clock = systemSyncClock]);

  final Box<UserSettings> _box;
  final SyncClock _clock;

  @override
  UserSettings get() => _box.get(UserSettings.defaultId) ?? UserSettings();

  @override
  Stream<UserSettings> watch() async* {
    yield get();
    yield* _box.watch(key: UserSettings.defaultId).map((_) => get());
  }

  @override
  Future<void> update(UserSettings settings) =>
      _box.put(UserSettings.defaultId, settings.stampUpdated(_clock()));

  /// The one record, in a list, because the engine reads every entity the
  /// same way. There is nothing to delete here and so no tombstone.
  @override
  List<UserSettings> allIncludingDeleted() => [get()];

  @override
  Future<void> applyRemote(UserSettings record) =>
      _box.put(UserSettings.defaultId, record);

  @override
  Future<void> markSynced(String id, int millis) async {
    final settings = _box.get(UserSettings.defaultId);
    if (settings == null || settings.updatedAtMillis != millis) return;
    await _box.put(UserSettings.defaultId, settings.markSynced(millis));
  }

  /// Always zero — settings are never deleted, so there is nothing to purge.
  @override
  Future<int> purgeTombstonesBefore(int millis) async => 0;
}
