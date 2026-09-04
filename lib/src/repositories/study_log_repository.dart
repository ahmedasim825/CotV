import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../models/study_log.dart';
import 'hive_repository_utils.dart';

/// Append-only access to [StudyLog]s, plus the two aggregations the app
/// asks for by name.
///
/// A log is a record of something that happened, so there is no `update`:
/// the only correction available is deleting the entry.
abstract class StudyLogRepository {
  Stream<List<StudyLog>> watchAll();

  List<StudyLog> getAll();

  Future<void> append(StudyLog log);

  Future<void> delete(String id);

  /// Every session logged on the calendar day containing [day].
  List<StudyLog> logsOn(DateTime day);

  /// Minutes studied per subject id on the calendar day containing [day].
  ///
  /// Aggregated here rather than in the prompt builder because the builder
  /// runs on every conversational turn, and this has to be computed once
  /// per shape of the data rather than once per question asked.
  Map<String, int> minutesBySubject(DateTime day);
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

  @override
  List<StudyLog> logsOn(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return [
      for (final log in _box.values)
        if (!log.timestamp.isBefore(start) && log.timestamp.isBefore(end)) log,
    ];
  }

  @override
  Map<String, int> minutesBySubject(DateTime day) {
    final totals = <String, int>{};
    for (final log in logsOn(day)) {
      totals[log.subjectId] = (totals[log.subjectId] ?? 0) + log.durationMinutes;
    }
    return totals;
  }
}
