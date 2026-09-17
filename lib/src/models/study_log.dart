import 'package:hive_ce/hive_ce.dart';

import 'sync_stamped.dart';

part 'study_log.g.dart';

/// One finished study session.
///
/// [subjectName] is denormalised on purpose: a log is a record of what
/// happened, and renaming or deleting a subject later must not rewrite
/// history or leave an entry that cannot say what it was for.
@HiveType(typeId: 9)
class StudyLog implements SyncStamped {
  StudyLog({
    required this.id,
    required this.subjectId,
    required this.subjectName,
    required this.durationMinutes,
    required this.timestamp,
    this.updatedAtMillis,
    this.isDeleted = false,
    this.syncedAtMillis,
  });

  @HiveField(0)
  @override
  final String id;

  @HiveField(1)
  final String subjectId;

  @HiveField(2)
  final String subjectName;

  /// Minutes actually studied, not the length the timer was set to. A
  /// session ended early is worth recording as what it was.
  @HiveField(3)
  final int durationMinutes;

  /// When the session finished.
  @HiveField(4)
  final DateTime timestamp;

  /// See [SyncStamped]. A log's content never changes after it is written,
  /// so in practice this only ever moves for a delete — which is why study
  /// logs are the entity sync is proved on first.
  @HiveField(5)
  @override
  final int? updatedAtMillis;

  @HiveField(6)
  @override
  final bool isDeleted;

  @HiveField(7)
  @override
  final int? syncedAtMillis;

  /// This log marked as changed at [millis]. Called by the repository on
  /// the way to the box, never by UI code.
  StudyLog stampUpdated(int millis) => _sync(updatedAtMillis: millis);

  /// A tombstone: still in the box so the deletion can be pushed, filtered
  /// out of every read path.
  StudyLog markDeleted(int millis) =>
      _sync(updatedAtMillis: millis, isDeleted: true);

  /// Records that the server has seen this record's current state.
  StudyLog markSynced(int millis) => _sync(syncedAtMillis: millis);

  StudyLog _sync({
    int? updatedAtMillis,
    bool? isDeleted,
    int? syncedAtMillis,
  }) =>
      StudyLog(
        id: id,
        subjectId: subjectId,
        subjectName: subjectName,
        durationMinutes: durationMinutes,
        timestamp: timestamp,
        updatedAtMillis: updatedAtMillis ?? this.updatedAtMillis,
        isDeleted: isDeleted ?? this.isDeleted,
        syncedAtMillis: syncedAtMillis ?? this.syncedAtMillis,
      );

  @override
  String toString() =>
      'StudyLog($subjectName, ${durationMinutes}m, $timestamp)';
}
