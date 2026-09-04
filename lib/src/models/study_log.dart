import 'package:hive_ce/hive_ce.dart';

part 'study_log.g.dart';

/// One finished study session.
///
/// [subjectName] is denormalised on purpose: a log is a record of what
/// happened, and renaming or deleting a subject later must not rewrite
/// history or leave an entry that cannot say what it was for.
@HiveType(typeId: 9)
class StudyLog {
  StudyLog({
    required this.id,
    required this.subjectId,
    required this.subjectName,
    required this.durationMinutes,
    required this.timestamp,
  });

  @HiveField(0)
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

  @override
  String toString() =>
      'StudyLog($subjectName, ${durationMinutes}m, $timestamp)';
}
