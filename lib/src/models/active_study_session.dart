import 'package:hive_ce/hive_ce.dart';

part 'active_study_session.g.dart';

/// A study session that has started and not yet been logged.
///
/// Persisted rather than held in the notifier because of one case: the app
/// is killed while a timer runs. The OS notification still fires — it was
/// handed to the system when the session started — so the user is told the
/// session ended, and an in-memory session would leave no log to match
/// that. On launch this record is reconciled: one already past [endsAt] is
/// written to the log and cleared.
///
/// There is at most one of these, stored under [defaultId].
@HiveType(typeId: 11)
class ActiveStudySession {
  ActiveStudySession({
    required this.subjectId,
    required this.subjectName,
    required this.startedAt,
    required this.plannedSeconds,
    this.endsAt,
    this.remainingSeconds,
  });

  /// The single key this record is always stored under.
  static const String defaultId = 'active';

  @HiveField(0)
  final String subjectId;

  /// Denormalised for the same reason [StudyLog.subjectName] is: the log
  /// this session becomes must still say what it was for even if the
  /// subject is renamed or deleted while the timer runs.
  @HiveField(1)
  final String subjectName;

  @HiveField(2)
  final DateTime startedAt;

  /// The length the timer was set to. Kept because minutes actually
  /// studied is derived from it, and a session resumed after a pause no
  /// longer has any other record of what was asked for.
  @HiveField(3)
  final int plannedSeconds;

  /// The wall-clock instant the timer reaches zero, or null while paused.
  ///
  /// An instant rather than a remaining count, so time left is read off the
  /// clock. A decremented counter drifts, and stops advancing entirely
  /// while the app is backgrounded — which is exactly when a 25-minute
  /// timer is running.
  @HiveField(4)
  final DateTime? endsAt;

  /// Seconds left at the moment of pausing, or null while running.
  ///
  /// Pause and run are mutually exclusive and each stores the one thing the
  /// other cannot: a paused session has no meaningful end instant, and a
  /// running one has no fixed remainder.
  @HiveField(5)
  final int? remainingSeconds;

  bool get isPaused => endsAt == null;

  Duration get planned => Duration(seconds: plannedSeconds);

  /// Time left, floored at zero.
  Duration remainingAt(DateTime now) {
    final paused = remainingSeconds;
    if (paused != null) return Duration(seconds: paused);

    final left = endsAt!.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  /// Minutes actually studied so far — what a log records, rather than the
  /// length the timer was set to.
  ///
  /// Derived as planned minus remaining rather than from [startedAt], which
  /// would also count every minute the session spent paused. That makes
  /// tracking accumulated pause time unnecessary: the remainder already
  /// carries it.
  Duration elapsedAt(DateTime now) => planned - remainingAt(now);

  /// Whether the timer has reached zero. Always false while paused — a
  /// paused session cannot run out.
  bool isFinishedAt(DateTime now) =>
      !isPaused && !now.isBefore(endsAt!);

  /// Progress through the session, clamped to `0.0..1.0`.
  double progressAt(DateTime now) {
    if (plannedSeconds <= 0) return 1;
    return (elapsedAt(now).inSeconds / plannedSeconds).clamp(0.0, 1.0);
  }

  /// The same session paused at [now], holding the remainder it had.
  ActiveStudySession pausedAt(DateTime now) => ActiveStudySession(
        subjectId: subjectId,
        subjectName: subjectName,
        startedAt: startedAt,
        plannedSeconds: plannedSeconds,
        remainingSeconds: remainingAt(now).inSeconds,
      );

  /// The same session running again from [now], with a fresh end instant
  /// computed from the remainder it was holding.
  ActiveStudySession resumedAt(DateTime now) => ActiveStudySession(
        subjectId: subjectId,
        subjectName: subjectName,
        startedAt: startedAt,
        plannedSeconds: plannedSeconds,
        endsAt: now.add(remainingAt(now)),
      );

  @override
  String toString() => 'ActiveStudySession($subjectName, '
      '${isPaused ? 'paused' : 'ends $endsAt'})';
}
