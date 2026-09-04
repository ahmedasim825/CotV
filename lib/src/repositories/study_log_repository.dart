import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../models/study_log.dart';
import 'hive_repository_utils.dart';

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

class HiveStudyLogRepository implements StudyLogRepository {
  HiveStudyLogRepository(this._box);

  final Box<StudyLog> _box;

  @override
  Stream<List<StudyLog>> watchAll() => watchBoxValues(_box);

  @override
  List<StudyLog> getAll() => _box.values.toList(growable: false);

  @override
  Future<void> append(StudyLog log) => _box.put(log.id, log);

  @override
  Future<void> delete(String id) => _box.delete(id);
}
