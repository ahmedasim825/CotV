// The sync engine, driven as two devices against one shared remote.
//
// Two independent local stacks — separate Hive boxes, separate metadata,
// separate clocks — talking to one fake server. That is what makes a
// conflict reproducible: the alternative is two machines and a stopwatch.
//
// The property asserted throughout is **convergence**: after a bounded
// exchange the two devices hold the same record. Which one wins is a
// weaker claim and a less useful one — a rule that picked a consistent
// winner but left the pair disagreeing would still be broken.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import 'package:cotv/hive_registrar.g.dart';
import 'package:cotv/src/models/chat_message.dart';
import 'package:cotv/src/models/reminder.dart';
import 'package:cotv/src/models/study_log.dart';
import 'package:cotv/src/models/subject.dart';
import 'package:cotv/src/models/sync_stamped.dart';
import 'package:cotv/src/models/task.dart';
import 'package:cotv/src/models/user_settings.dart';
import 'package:cotv/src/providers/auth_providers.dart';
import 'package:cotv/src/providers/chat_session_providers.dart';
import 'package:cotv/src/providers/reminder_providers.dart';
import 'package:cotv/src/providers/notification_providers.dart';
import 'package:cotv/src/providers/nutrition_providers.dart'
    show syncErrorProvider;
import 'package:cotv/src/providers/study_providers.dart';
import 'package:cotv/src/providers/sync_providers.dart';
import 'package:cotv/src/providers/task_providers.dart';
import 'package:cotv/src/providers/user_settings_providers.dart';
import 'package:cotv/src/repositories/chat_session_repository.dart';
import 'package:cotv/src/repositories/reminder_repository.dart';
import 'package:cotv/src/repositories/study_log_repository.dart';
import 'package:cotv/src/repositories/subject_repository.dart';
import 'package:cotv/src/repositories/task_repository.dart';
import 'package:cotv/src/repositories/user_settings_repository.dart';
import 'package:cotv/src/services/milo_sync_service.dart';
import 'package:cotv/src/services/notification_service.dart';
import 'package:cotv/src/services/sync_merge.dart';
import 'package:cotv/src/storage/app_database.dart';
import 'package:cotv/src/storage/sync_metadata.dart';

/// A stand-in server that stores rows, not models.
///
/// Going through the real `*ToRow` / `*FromRow` functions means a mapping
/// bug fails these tests too, which is the point — a fake that traded
/// model objects would prove only that the merge maths works.
class _FakeRemote implements MiloSyncService {
  final Map<String, Map<String, Map<String, dynamic>>> _tables = {};

  /// Stands in for `now()` in the touch_updated_at trigger. Monotonic, and
  /// entirely unrelated to either device's clock — which is the point of
  /// having a server cursor at all.
  int _tick = 0;

  int pushedRows = 0;
  int fetchCalls = 0;

  String _stamp() {
    _tick++;
    return DateTime.utc(2026, 1, 1).add(Duration(seconds: _tick))
        .toIso8601String();
  }

  List<RemoteRecord<T>> _fetch<T>(
    String table,
    String? since,
    T Function(Map<String, dynamic>) fromRow,
  ) {
    fetchCalls++;
    final rows = (_tables[table] ?? const {}).values.toList()
      ..sort((a, b) =>
          (a['updated_at'] as String).compareTo(b['updated_at'] as String));
    return [
      for (final row in rows)
        if (since == null || (row['updated_at'] as String).compareTo(since) > 0)
          RemoteRecord(fromRow(row), row['updated_at'] as String),
    ];
  }

  void _push(String table, Iterable<Map<String, Object?>> rows) {
    final stored = _tables.putIfAbsent(table, () => {});
    for (final row in rows) {
      pushedRows++;
      // The trigger overwrites whatever the client sent.
      stored[row['id'] as String] = {...row, 'updated_at': _stamp()};
    }
  }

  @override
  Future<List<RemoteRecord<Subject>>> fetchSubjects(String? since) async =>
      _fetch('subjects', since, subjectFromRow);

  @override
  Future<void> pushSubjects(Iterable<Subject> subjects) async =>
      _push('subjects', subjects.map(subjectToRow));

  @override
  Future<List<RemoteRecord<StudyLog>>> fetchStudyLogs(String? since) async =>
      _fetch('study_logs', since, studyLogFromRow);

  @override
  Future<void> pushStudyLogs(Iterable<StudyLog> logs) async =>
      _push('study_logs', logs.map(studyLogToRow));

  @override
  Future<List<RemoteRecord<Task>>> fetchTasks(String? since) async =>
      _fetch('tasks', since, taskFromRow);

  @override
  Future<void> pushTasks(Iterable<Task> tasks) async =>
      _push('tasks', tasks.map(taskToRow));

  @override
  Future<List<RemoteRecord<Reminder>>> fetchReminders(String? since) async =>
      _fetch('reminders', since, reminderFromRow);

  @override
  Future<void> pushReminders(Iterable<Reminder> reminders) async =>
      _push('reminders', reminders.map(reminderToRow));

  /// Settings live in their own shape: one row per key, not per record.
  final Map<String, ({Object? value, int millis, String cursor})> settings = {};

  @override
  Future<(Map<String, RemoteSetting>, String?)> fetchSettings(
    String? since,
  ) async {
    fetchCalls++;
    final out = <String, RemoteSetting>{};
    String? cursor;
    final ordered = settings.entries.toList()
      ..sort((a, b) => a.value.cursor.compareTo(b.value.cursor));
    for (final entry in ordered) {
      if (since != null && entry.value.cursor.compareTo(since) <= 0) continue;
      cursor = entry.value.cursor;
      out[entry.key] = RemoteSetting(entry.value.value, entry.value.millis);
    }
    return (out, cursor);
  }

  @override
  Future<List<RemoteRecord<Map<String, Object?>>>> fetchChatSessions(
    String? since,
  ) async =>
      _fetch('chat_sessions', since, chatSessionFromRow);

  @override
  Future<void> pushChatSessions(Iterable<Map<String, Object?>> rows) async =>
      _push('chat_sessions', rows.map(chatSessionToRow));

  @override
  Future<List<RemoteRecord<Map<String, Object?>>>> fetchChatMessages(
    String? since,
  ) async =>
      _fetch('chat_messages', since, chatMessageFromRow);

  @override
  Future<void> pushChatMessages(Iterable<Map<String, Object?>> rows) async =>
      _push('chat_messages', rows.map(chatMessageToRow));

  @override
  Future<void> pushSettings(
    Map<String, Object?> values,
    int clientUpdatedAtMillis,
  ) async {
    for (final entry in values.entries) {
      pushedRows++;
      settings[entry.key] = (
        value: entry.value,
        millis: clientUpdatedAtMillis,
        cursor: _stamp(),
      );
    }
  }
}

/// Notifications are a device-local side effect, so the reminder test
/// watches what was asked for rather than what fired.
class _RecordingNotifications extends NotificationService {
  final List<String> scheduled = [];
  final List<String> cancelled = [];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> requestPermissions() async {}

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

/// A remote that refuses every push, to prove a failed cycle leaves local
/// records dirty rather than marking them clean.
class _OfflineRemote extends _FakeRemote {
  @override
  Future<void> pushSubjects(Iterable<Subject> subjects) async =>
      throw const MiloSyncException('No connection.');
}

/// One device: its own boxes, its own metadata, its own clock.
class _Device {
  _Device(this.name, this.remote, this.boxes, this.container, this.metadata);

  final String name;
  final _FakeRemote remote;
  final ({
    Box<Subject> subjects,
    Box<StudyLog> logs,
    Box<Task> tasks,
    Box<Reminder> reminders,
    Box<UserSettings> settings,
    Box<dynamic> meta,
  }) boxes;
  final ProviderContainer container;
  final SyncMetadata metadata;
  late final AppDatabase database;
  late final SqliteChatSessionRepository chat;

  /// Advanced by hand so "A wrote before B" is a fact of the test rather
  /// than a race between two real clocks.
  ///
  /// Real epoch milliseconds, not small integers: the tombstone purge
  /// measures against the actual wall clock, and a record stamped `2000`
  /// is fifty-six years old to it and gets swept the moment it is pushed.
  int clock = _now;

  late final _RecordingNotifications notifications;

  SyncController get sync => container.read(syncControllerProvider.notifier);
  SubjectRepository get subjects =>
      container.read(subjectRepositoryProvider);
  StudyLogRepository get logs => container.read(studyLogRepositoryProvider);
  TaskRepository get tasks => container.read(taskRepositoryProvider);
  ReminderRepository get reminders =>
      container.read(reminderRepositoryProvider);
  UserSettingsRepository get settings =>
      container.read(userSettingsRepositoryProvider);

  Future<void> syncNow() => sync.syncAll();

  void dispose() {
    container.dispose();
    chat.dispose();
    database.dispose();
  }
}

void main() {
  late Directory tempDir;
  late _FakeRemote remote;
  late List<_Device> devices;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cotv_sync_engine_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(8)) {
      Hive.registerAdapters();
    }
    remote = _FakeRemote();
    devices = [];
  });

  tearDown(() async {
    for (final device in devices) {
      device.dispose();
    }
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  /// Two devices share one Hive directory but never one box: the boxes are
  /// named per device, which is the cheapest way to get two independent
  /// stacks without a second Hive instance.
  Future<_Device> device(String name, {_FakeRemote? using}) async {
    final server = using ?? remote;
    final boxes = (
      subjects: await Hive.openBox<Subject>('${name}_subjects'),
      logs: await Hive.openBox<StudyLog>('${name}_logs'),
      tasks: await Hive.openBox<Task>('${name}_tasks'),
      reminders: await Hive.openBox<Reminder>('${name}_reminders'),
      settings: await Hive.openBox<UserSettings>('${name}_settings'),
      meta: await Hive.openBox<dynamic>('${name}_meta'),
    );
    final metadata = SyncMetadata(boxes.meta);
    final notifications = _RecordingNotifications();
    // Chat is SQL, so each device gets its own in-memory database rather
    // than another differently-named box.
    final database = AppDatabase.openAt(':memory:');
    final chat = SqliteChatSessionRepository(database);

    late _Device built;
    final container = ProviderContainer(
      overrides: [
        isSignedInProvider.overrideWithValue(true),
        syncUserIdProvider.overrideWithValue('user-1'),
        miloSyncServiceProvider.overrideWithValue(server),
        syncMetadataProvider.overrideWithValue(metadata),
        notificationServiceProvider.overrideWithValue(notifications),
        subjectRepositoryProvider.overrideWithValue(
          HiveSubjectRepository(boxes.subjects, () => built.clock),
        ),
        studyLogRepositoryProvider.overrideWithValue(
          HiveStudyLogRepository(boxes.logs, () => built.clock),
        ),
        taskRepositoryProvider.overrideWithValue(
          HiveTaskRepository(boxes.tasks, () => built.clock),
        ),
        reminderRepositoryProvider.overrideWithValue(
          HiveReminderRepository(boxes.reminders, () => built.clock),
        ),
        userSettingsRepositoryProvider.overrideWithValue(
          HiveUserSettingsRepository(boxes.settings, () => built.clock),
        ),
        appDatabaseProvider.overrideWithValue(database),
        chatSessionRepositoryProvider.overrideWithValue(chat),
      ],
    );

    built = _Device(name, server, boxes, container, metadata)
      ..notifications = notifications
      ..database = database
      ..chat = chat;
    devices.add(built);
    return built;
  }

  group('one device', () {
    test('a first sync pushes everything and pulls nothing', () async {
      final a = await device('a');
      await a.subjects.add(_subject('s1', 'Physiology'));

      await a.syncNow();

      expect(remote.pushedRows, 1);
      expect(a.boxes.subjects.get('s1')!.isDirty, isFalse,
          reason: 'a pushed record is clean until it is edited again');
    });

    test('a second sync with no local change writes nothing', () async {
      final a = await device('a');
      await a.subjects.add(_subject('s1', 'Physiology'));
      await a.syncNow();
      final after = remote.pushedRows;

      await a.syncNow();

      // Idempotence. A cycle that re-pushed unchanged rows would rewrite
      // every server row on every tick, and the other device would see
      // every record change every five minutes.
      expect(remote.pushedRows, after);
    });

    test('a failed push leaves the record dirty for the next attempt',
        () async {
      final offline = _OfflineRemote();
      final a = await device('a', using: offline);
      await a.subjects.add(_subject('s1', 'Physiology'));

      await a.syncNow();

      expect(a.boxes.subjects.get('s1')!.isDirty, isTrue);
      expect(a.container.read(syncErrorProvider), isNotNull);
    });
  });

  group('two devices', () {
    test('a record made on one appears on the other', () async {
      final a = await device('a');
      final b = await device('b');

      await a.subjects.add(_subject('s1', 'Physiology'));
      await a.syncNow();
      await b.syncNow();

      expect(b.subjects.getAll().map((s) => s.name), ['Physiology']);
      expect(b.boxes.subjects.get('s1')!.isDirty, isFalse,
          reason: 'a pulled record must not read as a local edit');
    });

    test('a pulled record is not pushed straight back', () async {
      final a = await device('a');
      final b = await device('b');
      await a.subjects.add(_subject('s1', 'Physiology'));
      await a.syncNow();

      await b.syncNow();
      final after = remote.pushedRows;
      await b.syncNow();

      // The ping-pong this guards against: B stamps what it pulled with its
      // own clock, pushes it, A pulls it back, and the row churns forever.
      expect(remote.pushedRows, after);
    });

    test('simultaneous edits converge, and the later write wins', () async {
      final a = await device('a');
      final b = await device('b');
      await a.subjects.add(_subject('s1', 'Physiology'));
      await a.syncNow();
      await b.syncNow();

      // Both offline, both editing the same record.
      a.clock = _now + 2000;
      b.clock = _now + 3000;
      await a.subjects.update(_subject('s1', 'Physio (A)'));
      await b.subjects.update(_subject('s1', 'Physio (B)'));

      await a.syncNow();
      await b.syncNow();
      await a.syncNow();

      expect(a.subjects.getAll().single.name, b.subjects.getAll().single.name);
      expect(a.subjects.getAll().single.name, 'Physio (B)');
    });

    test('they converge whichever order they sync in', () async {
      final a = await device('a');
      final b = await device('b');
      await a.subjects.add(_subject('s1', 'Physiology'));
      await a.syncNow();
      await b.syncNow();

      a.clock = _now + 3000;
      b.clock = _now + 2000;
      await a.subjects.update(_subject('s1', 'Physio (A)'));
      await b.subjects.update(_subject('s1', 'Physio (B)'));

      // B first this time; A still holds the newer write.
      await b.syncNow();
      await a.syncNow();
      await b.syncNow();

      expect(a.subjects.getAll().single.name, b.subjects.getAll().single.name);
      expect(a.subjects.getAll().single.name, 'Physio (A)');
    });
  });

  group('deletes', () {
    test('a delete on one device removes it from the other', () async {
      final a = await device('a');
      final b = await device('b');
      await a.subjects.add(_subject('s1', 'Physiology'));
      await a.syncNow();
      await b.syncNow();
      expect(b.subjects.getAll(), hasLength(1));

      a.clock = _now + 2000;
      await a.subjects.delete('s1');
      await a.syncNow();
      await b.syncNow();

      expect(b.subjects.getAll(), isEmpty);
      expect(b.boxes.subjects.get('s1')!.isDeleted, isTrue,
          reason: 'B keeps the tombstone, or it would resurrect the row');
    });

    test('a device that stayed offline does not resurrect a deleted record',
        () async {
      final a = await device('a');
      final b = await device('b');
      await a.subjects.add(_subject('s1', 'Physiology'));
      await a.syncNow();
      await b.syncNow();

      // A deletes and syncs while B is away.
      a.clock = _now + 5000;
      await a.subjects.delete('s1');
      await a.syncNow();

      // B comes back holding its stale, un-edited copy.
      await b.syncNow();
      await a.syncNow();

      expect(b.subjects.getAll(), isEmpty);
      expect(a.subjects.getAll(), isEmpty,
          reason: 'B must not have pushed its live copy back over the delete');
    });

    test('a fresh tombstone survives the purge at the end of a cycle',
        () async {
      final a = await device('a');
      await a.subjects.add(_subject('s1', 'Physiology'));
      await a.syncNow();

      a.clock = _now + 2000;
      await a.subjects.delete('s1');
      await a.syncNow();

      // The purge only sweeps tombstones the server has acknowledged *and*
      // that are older than the retention window. Sweeping a fresh one
      // would drop the record locally while the other device still holds
      // it live — and the next pull would hand it straight back.
      expect(a.boxes.subjects.get('s1'), isNotNull);
      expect(a.boxes.subjects.get('s1')!.isDeleted, isTrue);
    });

    test('a fresh install cannot push its emptiness over the other device',
        () async {
      final a = await device('a');
      await a.subjects.add(_subject('s1', 'Physiology'));
      await a.syncNow();

      // B has never held this record, so it has no tombstone for it —
      // absence is not a deletion.
      final b = await device('b');
      await b.syncNow();
      await a.syncNow();

      expect(a.subjects.getAll(), hasLength(1));
      expect(b.subjects.getAll(), hasLength(1));
    });
  });

  group('study logs', () {
    test('logs from both devices union rather than compete', () async {
      final a = await device('a');
      final b = await device('b');

      await a.logs.append(_log('study-s1-1', 'Physiology', 45));
      await b.logs.append(_log('study-s1-2', 'Anatomy', 30));

      await a.syncNow();
      await b.syncNow();
      await a.syncNow();

      // Deterministic ids and two devices that cannot run the same session
      // mean there is no conflict to resolve here, only a union.
      expect(a.logs.getAll().map((l) => l.id).toSet(),
          {'study-s1-1', 'study-s1-2'});
      expect(b.logs.getAll().map((l) => l.id).toSet(),
          {'study-s1-1', 'study-s1-2'});
    });
  });

  group('tasks', () {
    test('a task with a reminder schedules one on the other device too',
        () async {
      final a = await device('a');
      final b = await device('b');

      await a.tasks.add(Task(
        id: 't1',
        title: 'Read chapter 4',
        dueDate: DateTime.now().add(const Duration(days: 1)),
        hasReminder: true,
      ));
      await a.syncNow();
      await b.syncNow();

      // A notification is local to the device that scheduled it. Without
      // reconciling on pull, a reminder set on the phone never fires on
      // the laptop.
      expect(b.notifications.scheduled, ['t1']);
    });

    test('a task deleted elsewhere drops its reminder here', () async {
      final a = await device('a');
      final b = await device('b');
      await a.tasks.add(Task(
        id: 't1',
        title: 'Read chapter 4',
        dueDate: DateTime.now().add(const Duration(days: 1)),
        hasReminder: true,
      ));
      await a.syncNow();
      await b.syncNow();

      a.clock = _now + 2000;
      await a.tasks.delete('t1');
      await a.syncNow();
      await b.syncNow();

      expect(b.notifications.cancelled, contains('t1'));
      expect(b.tasks.getAll(), isEmpty);
    });

    test('completing on one device clears the reminder on the other',
        () async {
      final a = await device('a');
      final b = await device('b');
      await a.tasks.add(Task(
        id: 't1',
        title: 'Read chapter 4',
        dueDate: DateTime.now().add(const Duration(days: 1)),
        hasReminder: true,
      ));
      await a.syncNow();
      await b.syncNow();
      b.notifications.scheduled.clear();

      a.clock = _now + 2000;
      await a.tasks.toggleCompleted('t1');
      await a.syncNow();
      await b.syncNow();

      // A finished task must not still buzz, on either device.
      expect(b.tasks.getById('t1')!.isCompleted, isTrue);
      expect(b.notifications.cancelled, contains('t1'));
    });
  });

  group('reminders', () {
    test('an edit on each device settles on the later one', () async {
      final a = await device('a');
      final b = await device('b');

      await a.reminders.add(Reminder(
        id: 'r1',
        title: 'Workout',
        dueAt: DateTime(2026, 9, 17, 18),
      ));
      await a.syncNow();
      await b.syncNow();

      // Both offline, each editing the same reminder.
      a.clock = _now + 2000;
      b.clock = _now + 3000;
      await a.reminders.toggleCompleted('r1');
      await b.reminders.update(
        b.reminders.getById('r1')!.copyWith(title: 'Workout, longer'),
      );

      await a.syncNow();
      await b.syncNow();
      await a.syncNow();

      // Plain record-level last-write-wins, unlike the habit check-ins this
      // group replaced: a reminder has no set-valued field, so there is
      // nothing to union and the later whole record is the right answer.
      final onA = a.reminders.getById('r1')!;
      final onB = b.reminders.getById('r1')!;
      expect(onA.title, 'Workout, longer');
      expect(onB.title, 'Workout, longer');
      expect(onA.isCompleted, onB.isCompleted);
    });

    test('a deletion propagates', () async {
      final a = await device('a');
      final b = await device('b');

      await a.reminders.add(Reminder(
        id: 'r1',
        title: 'Workout',
        dueAt: DateTime(2026, 9, 17, 18),
      ));
      await a.syncNow();
      await b.syncNow();
      expect(b.reminders.getById('r1'), isNotNull);

      a.clock = _now + 2000;
      await a.reminders.delete('r1');
      await a.syncNow();
      await b.syncNow();

      expect(b.reminders.getById('r1'), isNull);
    });
  });

  group('settings', () {
    test('a preference set on one device reaches the other', () async {
      final a = await device('a');
      final b = await device('b');

      await a.settings.update(a.settings.get().copyWith(voiceName: 'Zoe'));
      await a.syncNow();
      await b.syncNow();

      expect(b.settings.get().voiceName, 'Zoe');
    });

    test('two devices changing different preferences both keep theirs',
        () async {
      final a = await device('a');
      final b = await device('b');

      a.clock = _now + 2000;
      b.clock = _now + 3000;
      await a.settings.update(a.settings.get().copyWith(voiceName: 'Zoe'));
      await b.settings
          .update(b.settings.get().copyWith(preAdhanNotificationMinutes: 25));

      await a.syncNow();
      await b.syncNow();
      await a.syncNow();

      // The case per-key sync exists for: under record-level LWW one of
      // these two unrelated preferences would be lost.
      expect(b.settings.get().voiceName, 'Zoe');
      expect(b.settings.get().preAdhanNotificationMinutes, 25);
      expect(a.settings.get().preAdhanNotificationMinutes, 25);
    });

    test('the biometric flag never leaves the device', () async {
      final a = await device('a');
      final b = await device('b');

      await a.settings.update(
        a.settings.get().copyWith(isBiometricEnabled: true, voiceName: 'Zoe'),
      );
      await a.syncNow();
      await b.syncNow();

      // The Keychain holds the authoritative copy, and the other device may
      // not even have the sensor.
      expect(remote.settings.keys, isNot(contains('isBiometricEnabled')));
      expect(b.settings.get().isBiometricEnabled, isFalse);
      expect(b.settings.get().voiceName, 'Zoe',
          reason: 'the rest of the record still synced');
    });

    test('untouched settings are not pushed', () async {
      final a = await device('a');
      await a.syncNow();

      // A fresh record is synthesised on read with no timestamp, so it is
      // not dirty — pushing it would overwrite the other device's real
      // preferences with this one's defaults.
      expect(remote.settings, isEmpty);
    });
  });

  group('chat', () {
    test('a thread started on one device arrives whole on the other',
        () async {
      final a = await device('a');
      final b = await device('b');

      final session = await a.chat.createSession(title: 'Cardiology');
      await a.chat.append(_chatMessage('m1', session.id, 'what about ACE-Is'));
      await a.chat.append(_chatMessage('m2', session.id, 'they lower BP', 1));

      await a.syncNow();
      await b.syncNow();

      expect(b.chat.listSessions().map((s) => s.title), ['Cardiology']);
      expect(
        b.chat.messages(session.id).map((m) => m.text),
        ['what about ACE-Is', 'they lower BP'],
      );
    });

    test('a message added on each device leaves one merged transcript',
        () async {
      final a = await device('a');
      final b = await device('b');
      final session = await a.chat.createSession(title: 'Cardiology');
      await a.syncNow();
      await b.syncNow();

      await a.chat.append(_chatMessage('m-a', session.id, 'from the laptop'));
      await b.chat.append(_chatMessage('m-b', session.id, 'from the phone', 1));

      await a.syncNow();
      await b.syncNow();
      await a.syncNow();

      // Messages are immutable and uniquely identified, so there is nothing
      // to resolve — only a union.
      expect(a.chat.messages(session.id).map((m) => m.text),
          ['from the laptop', 'from the phone']);
      expect(b.chat.messages(session.id).map((m) => m.text),
          ['from the laptop', 'from the phone']);
    });

    test('a rename propagates', () async {
      final a = await device('a');
      final b = await device('b');
      final session = await a.chat.createSession(title: 'Untitled thread');
      await a.syncNow();
      await b.syncNow();

      await a.chat.rename(session.id, 'Cardiology');
      await a.syncNow();
      await b.syncNow();

      expect(b.chat.findById(session.id)!.title, 'Cardiology');
    });

    test('a deleted thread stays deleted on both devices', () async {
      final a = await device('a');
      final b = await device('b');
      final session = await a.chat.createSession(title: 'Cardiology');
      await a.chat.append(_chatMessage('m1', session.id, 'hello'));
      await a.syncNow();
      await b.syncNow();
      expect(b.chat.listSessions(), hasLength(1));

      await a.chat.deleteSession(session.id);
      await a.syncNow();
      await b.syncNow();
      // And once more, to prove B does not push its stale live copy back.
      await a.syncNow();

      expect(b.chat.listSessions(), isEmpty);
      expect(b.chat.search('cardiology'), isEmpty);
      expect(a.chat.listSessions(), isEmpty);
    });

    test('forgetting on one device does not un-forget from the other',
        () async {
      final a = await device('a');
      final b = await device('b');
      final session = await a.chat.createSession(title: 'Cardiology');
      await a.chat.append(_chatMessage('m1', session.id, 'private'));
      await a.syncNow();
      await b.syncNow();

      // What MiloConversation.forget() calls. With a hard delete here the
      // rows would simply be absent locally and present remotely, and the
      // next pull would hand the whole transcript back.
      await a.chat.clear();
      await a.syncNow();
      await b.syncNow();
      await a.syncNow();

      expect(a.chat.listSessions(), isEmpty);
      expect(b.chat.listSessions(), isEmpty);
      expect(b.chat.messages(session.id), isEmpty);
    });

    test('a steady-state cycle pushes nothing', () async {
      final a = await device('a');
      final session = await a.chat.createSession(title: 'Cardiology');
      await a.chat.append(_chatMessage('m1', session.id, 'hello'));
      await a.syncNow();
      final after = remote.pushedRows;

      await a.syncNow();

      expect(remote.pushedRows, after);
    });
  });

  group('account switching', () {
    test('sync refuses when the device belongs to another account', () async {
      final a = await device('a');
      await a.metadata.setLastSyncedUserId('someone-else');
      await a.subjects.add(_subject('s1', 'Physiology'));

      await a.syncNow();

      expect(remote.pushedRows, 0,
          reason: 'one account\'s tasks must not land in another');
      expect(a.container.read(syncControllerProvider).blockedByAccountSwitch,
          isTrue);
    });

    test('adopting the account resumes sync', () async {
      final a = await device('a');
      await a.metadata.setLastSyncedUserId('someone-else');
      await a.subjects.add(_subject('s1', 'Physiology'));
      await a.syncNow();

      await a.sync.adoptCurrentAccount();

      expect(remote.pushedRows, 1);
      expect(a.container.read(syncControllerProvider).blockedByAccountSwitch,
          isFalse);
    });
  });
}

Subject _subject(String id, String name) =>
    Subject(id: id, name: name, colorValue: 0xFFD8A657,
        createdAt: DateTime(2026, 3, 2));

/// A plausible "now" for the device clocks, fixed so a run is repeatable.
final int _now = DateTime(2026, 9, 17, 12).millisecondsSinceEpoch;

ChatMessage _chatMessage(
  String id,
  String sessionId,
  String text, [
  int minute = 0,
]) =>
    ChatMessage(
      id: id,
      sessionId: sessionId,
      isUser: true,
      text: text,
      timestamp: DateTime.utc(2026, 9, 14, 20, minute),
    );

StudyLog _log(String id, String subject, int minutes) => StudyLog(
      id: id,
      subjectId: 's1',
      subjectName: subject,
      durationMinutes: minutes,
      timestamp: DateTime(2026, 9, 14, 20),
    );
