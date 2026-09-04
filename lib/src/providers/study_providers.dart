import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../models/active_study_session.dart';
import '../models/study_log.dart';
import '../models/study_view.dart';
import '../models/subject.dart';
import '../repositories/study_log_repository.dart';
import '../repositories/subject_repository.dart';
import '../services/milo/milo_tools.dart';
import '../services/study_app_intents.dart';
import '../storage/local_storage.dart';
import 'clock_providers.dart';
import 'notification_providers.dart';

final subjectBoxProvider =
    Provider<Box<Subject>>((ref) => Hive.box<Subject>(HiveBoxes.subjects));

final studyLogBoxProvider =
    Provider<Box<StudyLog>>((ref) => Hive.box<StudyLog>(HiveBoxes.studyLogs));

final activeStudySessionBoxProvider = Provider<Box<ActiveStudySession>>(
  (ref) => Hive.box<ActiveStudySession>(HiveBoxes.activeStudySession),
);

final subjectRepositoryProvider = Provider<SubjectRepository>((ref) {
  return HiveSubjectRepository(ref.watch(subjectBoxProvider));
});

final studyLogRepositoryProvider = Provider<StudyLogRepository>((ref) {
  return HiveStudyLogRepository(ref.watch(studyLogBoxProvider));
});

class SubjectListNotifier extends StreamNotifier<List<Subject>> {
  SubjectRepository get _repository => ref.read(subjectRepositoryProvider);

  @override
  Stream<List<Subject>> build() => _repository.watchAll();

  Future<void> addSubject(Subject subject) => _repository.add(subject);

  Future<void> updateSubject(Subject subject) => _repository.update(subject);

  Future<void> deleteSubject(String id) => _repository.delete(id);
}

final subjectListProvider =
    StreamNotifierProvider<SubjectListNotifier, List<Subject>>(
  SubjectListNotifier.new,
);

class StudyLogListNotifier extends StreamNotifier<List<StudyLog>> {
  StudyLogRepository get _repository => ref.read(studyLogRepositoryProvider);

  @override
  Stream<List<StudyLog>> build() => _repository.watchAll();

  Future<void> deleteLog(String id) => _repository.delete(id);
}

final studyLogListProvider =
    StreamNotifierProvider<StudyLogListNotifier, List<StudyLog>>(
  StudyLogListNotifier.new,
);

/// Today's and this week's totals, recomputed when the logs change or the
/// minute rolls over.
///
/// Auto-disposed because it watches [currentMinuteProvider]: a provider
/// that outlives its listeners would hold the one-second ticker open for
/// the life of the app, which is exactly what that ticker is
/// auto-disposed to avoid.
final studySummaryProvider = Provider.autoDispose<StudySummary>((ref) {
  final logs = ref.watch(studyLogListProvider).value ?? const <StudyLog>[];
  final now = ref.watch(currentMinuteProvider);
  return summarizeStudy(logs, now);
});

/// Where a study session has got to.
enum StudyPhase {
  idle,

  /// The clock is running towards [ActiveStudySession.endsAt].
  running,

  /// Held, with the remainder stored. A paused session cannot run out.
  paused,

  /// Just finished, and the log has been written. Shows the result until
  /// the user dismisses it.
  completed,
}

/// What the study screen renders.
class StudyState {
  const StudyState({
    this.phase = StudyPhase.idle,
    this.session,
    this.completed,
  });

  final StudyPhase phase;

  /// The session in flight. Null in [StudyPhase.idle] and
  /// [StudyPhase.completed] — once logged, a session is history.
  final ActiveStudySession? session;

  /// The log just written, so the finished card can say what was recorded
  /// rather than what was asked for.
  final StudyLog? completed;

  bool get isActive =>
      phase == StudyPhase.running || phase == StudyPhase.paused;
}

/// Owns the study timer.
///
/// Two rules hold this together, and both exist because a timer is the one
/// piece of app state that keeps moving while nobody is looking at it:
///
///   * Time left is read off the clock, never decremented. [ActiveStudySession]
///     stores the instant the timer reaches zero, so backgrounding the app
///     for ten minutes costs ten minutes, exactly as it should.
///   * The session is persisted, not held here. A timer that outlives the
///     process has to be reconcilable on the next launch, because the OS
///     notification will have fired either way and a user told their
///     session ended must find it in the log.
class StudyNotifier extends Notifier<StudyState> {
  /// The notification key. One session at a time, so one key.
  static const String _notificationKey = 'study-session';

  /// Fires once, at the instant the running session ends.
  ///
  /// Not a tick: it is scheduled for the target instant and cancelled on
  /// every transition, so it cannot drift and cannot accumulate error. It
  /// covers only the case where the app is in the foreground when the timer
  /// runs out; [AppLifecycleListener] covers backgrounding, and
  /// [_reconcile] covers being killed.
  Timer? _completion;
  AppLifecycleListener? _lifecycle;

  Box<ActiveStudySession> get _box => ref.read(activeStudySessionBoxProvider);

  StudyLogRepository get _logs => ref.read(studyLogRepositoryProvider);

  @override
  StudyState build() {
    _lifecycle = AppLifecycleListener(onResume: _syncToClock);
    ref.onDispose(() {
      _completion?.cancel();
      _lifecycle?.dispose();
    });

    return _reconcile();
  }

  /// Picks up whatever was left on disk.
  ///
  /// A session already past its end is logged here and only here — this is
  /// the path that exists for the app being killed mid-session.
  StudyState _reconcile() {
    final stored = _box.get(ActiveStudySession.defaultId);
    if (stored == null) return const StudyState();

    final now = DateTime.now();
    if (stored.isFinishedAt(now)) {
      final log = _logFor(stored, stored.planned);
      unawaited(_finish(log));
      return StudyState(phase: StudyPhase.completed, completed: log);
    }

    if (stored.isPaused) {
      return StudyState(phase: StudyPhase.paused, session: stored);
    }

    // The notification was handed to the OS before the process died, but
    // there is no way to ask whether it survived, and rescheduling the same
    // key replaces rather than duplicates.
    unawaited(_schedule(stored));
    _armCompletion(stored, now);
    return StudyState(phase: StudyPhase.running, session: stored);
  }

  /// Starts a [minutes]-long session against [subject], replacing anything
  /// already running.
  Future<void> start(Subject subject, {required int minutes}) async {
    final safeMinutes = minutes.clamp(1, 24 * 60);
    final now = DateTime.now();
    final session = ActiveStudySession(
      subjectId: subject.id,
      subjectName: subject.name,
      startedAt: now,
      plannedSeconds: safeMinutes * 60,
      endsAt: now.add(Duration(minutes: safeMinutes)),
    );

    await _box.put(ActiveStudySession.defaultId, session);
    state = StudyState(phase: StudyPhase.running, session: session);
    _armCompletion(session, now);
    await _schedule(session);
  }

  /// Holds the session, keeping the remainder it had.
  Future<void> pause() async {
    final session = state.session;
    if (session == null || state.phase != StudyPhase.running) return;

    final paused = session.pausedAt(DateTime.now());
    _completion?.cancel();
    _completion = null;
    await _cancelNotification();
    await _box.put(ActiveStudySession.defaultId, paused);
    state = StudyState(phase: StudyPhase.paused, session: paused);
  }

  /// Runs again, recomputing the end instant from the stored remainder.
  Future<void> resume() async {
    final session = state.session;
    if (session == null || state.phase != StudyPhase.paused) return;

    final now = DateTime.now();
    final resumed = session.resumedAt(now);
    await _box.put(ActiveStudySession.defaultId, resumed);
    state = StudyState(phase: StudyPhase.running, session: resumed);
    _armCompletion(resumed, now);
    await _schedule(resumed);
  }

  /// Ends the session now and records the minutes actually studied.
  ///
  /// A session stopped before a whole minute has passed is discarded
  /// instead: a zero-minute log is not a record of anything.
  Future<void> stop() async {
    final session = state.session;
    if (session == null) return;

    final elapsed = session.elapsedAt(DateTime.now());
    if (elapsed.inMinutes < 1) {
      await reset();
      return;
    }

    final log = _logFor(session, elapsed);
    state = StudyState(phase: StudyPhase.completed, completed: log);
    await _finish(log);
  }

  /// Throws the session away without logging it.
  Future<void> reset() async {
    _completion?.cancel();
    _completion = null;
    await _cancelNotification();
    await _box.delete(ActiveStudySession.defaultId);
    state = const StudyState();
  }

  /// Clears the finished card, returning the screen to idle.
  void dismiss() {
    if (state.phase != StudyPhase.completed) return;
    state = const StudyState();
  }

  /// Starts a session against the subject called [name], creating nothing.
  ///
  /// Returns the subject started, or null if no subject matches — the
  /// caller (Milo's tool dispatch) reports that back rather than inventing
  /// a subject from a word the model produced.
  Future<Subject?> startByName(String name, {required int minutes}) async {
    final subject = ref.read(subjectRepositoryProvider).findByName(name);
    if (subject == null) return null;
    await start(subject, minutes: minutes);
    return subject;
  }

  /// Completes the session if its end has already passed.
  ///
  /// Runs on app resume, before the next frame, so a session that ended
  /// while the app was backgrounded is logged rather than rendered as a
  /// countdown sitting at zero.
  void _syncToClock() {
    final session = state.session;
    if (session == null || state.phase != StudyPhase.running) return;
    if (!session.isFinishedAt(DateTime.now())) return;
    _complete(session);
  }

  void _armCompletion(ActiveStudySession session, DateTime now) {
    _completion?.cancel();
    final left = session.endsAt!.difference(now);
    _completion = Timer(
      left.isNegative ? Duration.zero : left,
      () => _complete(session),
    );
  }

  void _complete(ActiveStudySession session) {
    if (state.phase != StudyPhase.running) return;
    final log = _logFor(session, session.planned);
    state = StudyState(phase: StudyPhase.completed, completed: log);
    unawaited(_finish(log));
  }

  /// Writes [log] and clears the in-flight record.
  Future<void> _finish(StudyLog log) async {
    _completion?.cancel();
    _completion = null;
    await _logs.append(log);
    await _box.delete(ActiveStudySession.defaultId);
    await _cancelNotification();
  }

  /// The log a session becomes.
  ///
  /// The id is derived from the session rather than generated, so writing
  /// it twice overwrites one entry instead of appending a second. That is
  /// what makes reconciliation exactly-once without needing the write and
  /// the clear to be atomic: a launch that reconciles the same stored
  /// session again produces the same key.
  StudyLog _logFor(ActiveStudySession session, Duration studied) => StudyLog(
        id: 'study-${session.subjectId}-'
            '${session.startedAt.microsecondsSinceEpoch}',
        subjectId: session.subjectId,
        subjectName: session.subjectName,
        durationMinutes: studied.inMinutes,
        timestamp: DateTime.now(),
      );

  /// Best-effort, following the task-reminder convention: a session must
  /// still start when notification permission has been refused.
  Future<void> _schedule(ActiveStudySession session) async {
    try {
      await ref.read(notificationServiceProvider).scheduleReminder(
            key: _notificationKey,
            when: session.endsAt!,
            title: '${session.subjectName} — session done',
            body: '${session.planned.inMinutes} minutes on '
                '${session.subjectName}.',
          );
    } catch (_) {
      // The timer itself is unaffected; only the alert is lost.
    }
  }

  Future<void> _cancelNotification() async {
    try {
      await ref.read(notificationServiceProvider).cancelReminder(
            _notificationKey,
          );
    } catch (_) {
      // Nothing to recover: the session is ending either way.
    }
  }
}

final studyProvider =
    NotifierProvider<StudyNotifier, StudyState>(StudyNotifier.new);

/// Carries out the study tools Milo offers.
///
/// The bridge between the model's request and the notifier that owns the
/// timer. Every return value is a sentence rather than a status code,
/// because the model gets it back as a tool result and has to answer from
/// it — including when the answer is that nothing happened.
class StudyToolController implements StudyToolTarget {
  const StudyToolController(this._ref);

  final Ref _ref;

  @override
  Future<String> startTimer({
    required String subject,
    required int minutes,
  }) async {
    final started = await _ref
        .read(studyProvider.notifier)
        .startByName(subject, minutes: minutes);

    if (started != null) {
      return 'Started a $minutes-minute timer on ${started.name}.';
    }

    // Naming the real subjects rather than just refusing: the model can
    // then ask the user which one they meant, instead of guessing again.
    final names = [
      for (final s in _ref.read(subjectRepositoryProvider).getAll()) s.name,
    ];
    return names.isEmpty
        ? 'No timer was started: the user has not set up any subjects yet. '
            'They can add one on the Study screen.'
        : 'No timer was started: there is no subject called "$subject". '
            'The subjects that exist are ${names.join(', ')}.';
  }

  @override
  Future<String> stopTimer() async {
    final session = _ref.read(studyProvider).session;
    if (session == null) {
      return 'No study timer is running, so nothing was stopped.';
    }

    // Read before stopping — the session is cleared by the time stop()
    // returns, and this is the figure that was actually logged.
    final minutes = session.elapsedAt(DateTime.now()).inMinutes;
    await _ref.read(studyProvider.notifier).stop();

    return minutes < 1
        ? 'Stopped the ${session.subjectName} timer. Under a minute had '
            'passed, so nothing was logged.'
        : 'Stopped the ${session.subjectName} timer and logged '
            '$minutes minutes.';
  }
}

final studyToolTargetProvider =
    Provider<StudyToolTarget>(StudyToolController.new);

/// Registers the study App Intents with iOS, once.
///
/// A [FutureProvider] rather than a call in `main()` so it runs inside the
/// container that owns [studyToolTargetProvider], and so the result — did
/// registration actually take — is inspectable rather than fire-and-forget.
/// Resolves to false on every platform that is not iOS.
final studyAppIntentsProvider = FutureProvider<bool>(
  (ref) => StudyAppIntents(ref.watch(studyToolTargetProvider)).register(),
);
