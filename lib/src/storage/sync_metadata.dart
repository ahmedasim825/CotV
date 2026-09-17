import 'package:hive_ce_flutter/hive_ce_flutter.dart';

/// Small durable values the sync engine keeps between runs.
///
/// A box of primitives rather than a model, so it needs no adapter and no
/// typeId — which also means it can be read during the migration that
/// gives the other boxes their adapters' new fields.
class SyncMetadata {
  SyncMetadata(this._box);

  static const String boxName = 'sync_meta';

  static const String _schemaVersionKey = 'hive_schema_version';
  static const String _syncedUserKey = 'last_synced_user_id';
  static const String _pulledPrefix = 'last_pulled_';

  final Box<dynamic> _box;

  /// How far [HiveMigrations] has taken the Hive boxes. Zero before the
  /// first migration has run.
  int get schemaVersion => (_box.get(_schemaVersionKey) as num?)?.toInt() ?? 0;

  Future<void> setSchemaVersion(int version) =>
      _box.put(_schemaVersionKey, version);

  /// The server-side `updated_at` of the newest row pulled for [entity].
  ///
  /// Stored as the server's own string rather than parsed: it is only ever
  /// handed back to Postgres as a `.gt()` bound, and re-serialising a
  /// timestamptz through Dart is a chance to lose precision for nothing.
  String? lastPulled(String entity) =>
      _box.get('$_pulledPrefix$entity') as String?;

  Future<void> setLastPulled(String entity, String cursor) =>
      _box.put('$_pulledPrefix$entity', cursor);

  /// Which Supabase account this device's local data was last synced with.
  ///
  /// Read before any push: signing into a *different* account must not
  /// merge one account's tasks into another's.
  String? get lastSyncedUserId => _box.get(_syncedUserKey) as String?;

  Future<void> setLastSyncedUserId(String userId) =>
      _box.put(_syncedUserKey, userId);

  /// Forgets every pull cursor, so the next sync re-reads each entity from
  /// the beginning. Called on sign-out and on an account switch.
  Future<void> resetCursors() async {
    final cursors = _box.keys
        .whereType<String>()
        .where((key) => key.startsWith(_pulledPrefix))
        .toList(growable: false);
    await _box.deleteAll(cursors);
  }
}
