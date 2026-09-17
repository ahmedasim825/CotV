import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../models/study_log.dart';
import '../models/sync_stamped.dart';
import 'hive_repository_utils.dart';
import 'syncable_repository.dart';

/// Append-only access to [StudyLog]s.
///
/// A log is a record of something that happened, so there is no `update`:
/// the only correction available is deleting the entry.
///
/// No aggregation lives here. Everything that needs today's or this week's
/// totals goes through `summarizeStudy` in `study_view.dart`, which is
/// pure, unit-tested directly, and computed once per shape of the data by
/// `studySummaryProvider` rather than once per caller.
abstract class StudyLogRepository {
  Stream<List<StudyLog>> watchAll();

  List<StudyLog> getAll();

  Future<void> append(StudyLog log);

  Future<void> delete(String id);
}

class HiveStudyLogRepository
    implements StudyLogRepository, SyncableRepository<StudyLog> {
  HiveStudyLogRepository(this._box, [this._clock = systemSyncClock]);

  final Box<StudyLog> _box;
  final SyncClock _clock;

  @override
  Stream<List<StudyLog>> watchAll() => watchLiveBoxValues(_box);

  @override
  List<StudyLog> getAll() => liveValues(_box.values);

  @override
  Future<void> append(StudyLog log) =>
      _box.put(log.id, log.stampUpdated(_clock()));

  /// Tombstones [id] rather than removing it — see [HiveTaskRepository.delete].
  @override
  Future<void> delete(String id) async {
    final log = _box.get(id);
    if (log == null) return;
    await _box.put(id, log.markDeleted(_clock()));
  }

  @override
  List<StudyLog> allIncludingDeleted() => _box.values.toList(growable: false);

  @override
  Future<void> applyRemote(StudyLog record) => _box.put(record.id, record);

  @override
  Future<void> markSynced(String id, int millis) async {
    final log = _box.get(id);
    if (log == null || log.updatedAtMillis != millis) return;
    await _box.put(id, log.markSynced(millis));
  }

  @override
  Future<int> purgeTombstonesBefore(int millis) async {
    final stale = _box.values
        .where((log) =>
            log.isDeleted && !log.isDirty && (log.updatedAtMillis ?? 0) < millis)
        .map((log) => log.id)
        .toList(growable: false);
    await _box.deleteAll(stale);
    return stale.length;
  }
}
