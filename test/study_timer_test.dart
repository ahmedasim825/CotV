// The study timer's state machine and its reconciliation on launch.
//
// Backed by a real (temp-directory) Hive box rather than a fake, because
// the behaviour under test *is* the persistence: a session survives the
// process, and the log written from it must appear exactly once.
//
// Time is controlled by seeding the stored session rather than by faking
// the clock. The notifier reads `DateTime.now()` on purpose — that is the
// whole design — so a session is placed at a known offset from now and the
// arithmetic is checked against it.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import 'package:cotv/hive_registrar.g.dart';
import 'package:cotv/src/models/active_study_session.dart';
import 'package:cotv/src/models/study_log.dart';
import 'package:cotv/src/models/subject.dart';
import 'package:cotv/src/providers/notification_providers.dart';
import 'package:cotv/src/providers/study_providers.dart';
import 'package:cotv/src/services/notification_service.dart';
import 'package:cotv/src/storage/local_storage.dart';

/// Records what was scheduled and cancelled, so the tests can assert that a
/// stale notification cannot outlive the session that asked for it.
class _FakeNotificationService extends NotificationService {
  final List<String> scheduled = [];
  final List<String> cancelled = [];

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> scheduleReminder({
    required String key,
    required DateTime when,
    required String title,
    required String body,
  }) async {
    scheduled.add(key);
    return true;
  }

  @override
  Future<void> cancelReminder(String key) async => cancelled.add(key);
}

void main() {
  // AppLifecycleListener, which StudyNotifier attaches in build(), needs a
  // binding to register with.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box<Subject> subjects;
  late Box<StudyLog> logs;
  late Box<ActiveStudySession> sessions;
  late _FakeNotificationService notifications;

  final physiology =
      Subject(id: 's1', name: 'Physiology', colorValue: 0xFF7B8FCB);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cotv_study_test_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(11)) {
      Hive.registerAdapters();
    }
    subjects = await Hive.openBox<Subject>(HiveBoxes.subjects);
    logs = await Hive.openBox<StudyLog>(HiveBoxes.studyLogs);
    sessions =
        await Hive.openBox<ActiveStudySession>(HiveBoxes.activeStudySession);
    await subjects.put(physiology.id, physiology);
    notifications = _FakeNotificationService();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// A fresh container, as a relaunch would build one.
  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        notificationServiceProvider.overrideWithValue(notifications),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Lets the notifier's un-awaited Hive writes land.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 30));

  group('ActiveStudySession arithmetic', () {
    test('remaining comes off the clock while running', () {
      final now = DateTime(2026, 9, 2, 14, 0);
      final session = ActiveStudySession(
        subjectId: 's1',
        subjectName: 'Physiology',
        startedAt: now,
        plannedSeconds: 45 * 60,
        endsAt: now.add(const Duration(minutes: 45)),
      );

      expect(session.remainingAt(now), const Duration(minutes: 45));
      expect(
        session.remainingAt(now.add(const Duration(minutes: 20))),
        const Duration(minutes: 25),
      );
      expect(session.elapsedAt(now.add(const Duration(minutes: 20))),
          const Duration(minutes: 20));
    });

    test('remaining floors at zero rather than going negative', () {
      final now = DateTime(2026, 9, 2, 14, 0);
      final session = ActiveStudySession(
        subjectId: 's1',
        subjectName: 'Physiology',
        startedAt: now,
        plannedSeconds: 45 * 60,
        endsAt: now.add(const Duration(minutes: 45)),
      );

      // Reopened an hour after it ended — the case that would otherwise
      // paint a negative countdown for one frame.
      final late = now.add(const Duration(minutes: 105));
      expect(session.remainingAt(late), Duration.zero);
      expect(session.elapsedAt(late), const Duration(minutes: 45));
      expect(session.isFinishedAt(late), isTrue);
      expect(session.progressAt(late), 1.0);
    });

    test('pause holds the remainder and resume rebuilds the end instant', () {
      final now = DateTime(2026, 9, 2, 14, 0);
      final running = ActiveStudySession(
        subjectId: 's1',
        subjectName: 'Physiology',
        startedAt: now,
        plannedSeconds: 45 * 60,
        endsAt: now.add(const Duration(minutes: 45)),
      );

      final paused = running.pausedAt(now.add(const Duration(minutes: 20)));
      expect(paused.isPaused, isTrue);
      expect(paused.remainingSeconds, 25 * 60);

      // Ten minutes pass while paused, and cost nothing.
      final resumedAt = now.add(const Duration(minutes: 30));
      final resumed = paused.resumedAt(resumedAt);
      expect(resumed.isPaused, isFalse);
      expect(resumed.endsAt, resumedAt.add(const Duration(minutes: 25)));
      expect(resumed.remainingAt(resumedAt), const Duration(minutes: 25));

      // Elapsed still reads 20, not 30: the pause is not study time.
      expect(resumed.elapsedAt(resumedAt), const Duration(minutes: 20));
    });

    test('a paused session never runs out', () {
      final now = DateTime(2026, 9, 2, 14, 0);
      final paused = ActiveStudySession(
        subjectId: 's1',
        subjectName: 'Physiology',
        startedAt: now,
        plannedSeconds: 45 * 60,
        remainingSeconds: 600,
      );

      expect(paused.isFinishedAt(now.add(const Duration(days: 1))), isFalse);
    });
  });

  group('StudyNotifier', () {
    test('start persists the session and schedules the notification',
        () async {
      final container = makeContainer();
      await container.read(studyProvider.notifier).start(physiology, minutes: 45);

      final state = container.read(studyProvider);
      expect(state.phase, StudyPhase.running);
      expect(state.session!.subjectName, 'Physiology');
      expect(state.session!.plannedSeconds, 45 * 60);

      expect(sessions.get(ActiveStudySession.defaultId), isNotNull);
      expect(notifications.scheduled, contains('study-session'));
    });

    test('pause cancels the notification, resume reschedules it', () async {
      final container = makeContainer();
      final notifier = container.read(studyProvider.notifier);
      await notifier.start(physiology, minutes: 45);

      await notifier.pause();
      expect(container.read(studyProvider).phase, StudyPhase.paused);
      expect(notifications.cancelled, contains('study-session'));
      expect(sessions.get(ActiveStudySession.defaultId)!.isPaused, isTrue);

      notifications.scheduled.clear();
      await notifier.resume();
      expect(container.read(studyProvider).phase, StudyPhase.running);
      expect(notifications.scheduled, contains('study-session'));
      expect(sessions.get(ActiveStudySession.defaultId)!.isPaused, isFalse);
    });

    test('stopping early logs the minutes elapsed, not the ones planned',
        () async {
      // Seeded 30 minutes into a 45-minute block.
      final now = DateTime.now();
      await sessions.put(
        ActiveStudySession.defaultId,
        ActiveStudySession(
          subjectId: physiology.id,
          subjectName: physiology.name,
          startedAt: now.subtract(const Duration(minutes: 30)),
          plannedSeconds: 45 * 60,
          endsAt: now.add(const Duration(minutes: 15)),
        ),
      );

      final container = makeContainer();
      expect(container.read(studyProvider).phase, StudyPhase.running);

      await container.read(studyProvider.notifier).stop();
      await settle();

      expect(logs.values.single.durationMinutes, 30);
      expect(logs.values.single.subjectName, 'Physiology');
      expect(container.read(studyProvider).phase, StudyPhase.completed);
      expect(sessions.get(ActiveStudySession.defaultId), isNull);
    });

    test('stopping under a minute in logs nothing', () async {
      final container = makeContainer();
      await container.read(studyProvider.notifier).start(physiology, minutes: 45);
      await container.read(studyProvider.notifier).stop();
      await settle();

      expect(logs.values, isEmpty);
      expect(container.read(studyProvider).phase, StudyPhase.idle);
      expect(sessions.get(ActiveStudySession.defaultId), isNull);
    });

    test('reset discards the session without logging it', () async {
      final container = makeContainer();
      await container.read(studyProvider.notifier).start(physiology, minutes: 45);
      await container.read(studyProvider.notifier).reset();
      await settle();

      expect(logs.values, isEmpty);
      expect(sessions.get(ActiveStudySession.defaultId), isNull);
      expect(notifications.cancelled, contains('study-session'));
    });
  });

  group('reconciliation on launch', () {
    /// A 45-minute session that ended five minutes ago — the app was killed
    /// before it could log itself.
    ///
    /// Built once and re-stored, never rebuilt: a session is identified by
    /// its subject and its start, so a second [ActiveStudySession] with a
    /// fresh `startedAt` is a different session and *should* log
    /// separately. The double-logging this guards against is the same
    /// record being reconciled twice.
    late final ActiveStudySession finished = () {
      final now = DateTime.now();
      return ActiveStudySession(
        subjectId: physiology.id,
        subjectName: physiology.name,
        startedAt: now.subtract(const Duration(minutes: 50)),
        plannedSeconds: 45 * 60,
        endsAt: now.subtract(const Duration(minutes: 5)),
      );
    }();

    Future<void> seedFinishedSession() =>
        sessions.put(ActiveStudySession.defaultId, finished);

    test('a session that ended while the app was gone is logged once',
        () async {
      await seedFinishedSession();

      final container = makeContainer();
      final state = container.read(studyProvider);
      await settle();

      expect(state.phase, StudyPhase.completed);
      expect(state.completed!.durationMinutes, 45);
      expect(logs.values.length, 1);
      expect(sessions.get(ActiveStudySession.defaultId), isNull);
    });

    test('launching twice does not log it twice', () async {
      await seedFinishedSession();

      // First launch.
      final first = ProviderContainer(
        overrides: [
          notificationServiceProvider.overrideWithValue(notifications),
        ],
      );
      first.read(studyProvider);
      await settle();
      expect(logs.values.length, 1);

      // Put the same session back, as a crash between the log write and the
      // clear would leave it — the case the deterministic log id exists for.
      await seedFinishedSession();
      first.dispose();

      final second = makeContainer();
      second.read(studyProvider);
      await settle();

      expect(logs.values.length, 1);
    });

    test('a still-running session is picked up and rescheduled', () async {
      final now = DateTime.now();
      await sessions.put(
        ActiveStudySession.defaultId,
        ActiveStudySession(
          subjectId: physiology.id,
          subjectName: physiology.name,
          startedAt: now.subtract(const Duration(minutes: 10)),
          plannedSeconds: 45 * 60,
          endsAt: now.add(const Duration(minutes: 35)),
        ),
      );

      final container = makeContainer();
      final state = container.read(studyProvider);
      await settle();

      expect(state.phase, StudyPhase.running);
      expect(state.session!.remainingAt(DateTime.now()).inMinutes, 34);
      expect(logs.values, isEmpty);
      expect(notifications.scheduled, contains('study-session'));
    });

    test('a paused session comes back paused, however long it sat', () async {
      await sessions.put(
        ActiveStudySession.defaultId,
        ActiveStudySession(
          subjectId: physiology.id,
          subjectName: physiology.name,
          startedAt: DateTime.now().subtract(const Duration(days: 2)),
          plannedSeconds: 45 * 60,
          remainingSeconds: 20 * 60,
        ),
      );

      final container = makeContainer();
      final state = container.read(studyProvider);
      await settle();

      expect(state.phase, StudyPhase.paused);
      expect(state.session!.remainingAt(DateTime.now()),
          const Duration(minutes: 20));
      expect(logs.values, isEmpty);
    });
  });

  group('startByName', () {
    test('matches a subject ignoring case and space', () async {
      final container = makeContainer();
      final started = await container
          .read(studyProvider.notifier)
          .startByName('  physiology ', minutes: 25);

      expect(started?.id, 's1');
      expect(container.read(studyProvider).phase, StudyPhase.running);
    });

    test('starts nothing when no subject matches', () async {
      final container = makeContainer();
      final started = await container
          .read(studyProvider.notifier)
          .startByName('Astrophysics', minutes: 25);

      expect(started, isNull);
      expect(container.read(studyProvider).phase, StudyPhase.idle);
      expect(sessions.get(ActiveStudySession.defaultId), isNull);
    });
  });
}
