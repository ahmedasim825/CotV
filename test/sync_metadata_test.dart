// The Hive-side migration that gives pre-sync records their metadata.
//
// The backfill is the single most dangerous step in the sync project: it
// rewrites every local row once, and a wrong timestamp here is not visible
// until the first sync, by which point the losing device has already been
// overwritten. The cases that matter are which clock each entity falls back
// to, and that a half-finished run can be repeated safely.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import 'package:cotv/hive_registrar.g.dart';
import 'package:cotv/src/models/study_log.dart';
import 'package:cotv/src/models/subject.dart';
import 'package:cotv/src/models/task.dart';
import 'package:cotv/src/models/user_settings.dart';
import 'package:cotv/src/storage/hive_migrations.dart';
import 'package:cotv/src/storage/sync_metadata.dart';

void main() {
  late Directory tempDir;
  late Box<Task> tasks;
  late Box<Subject> subjects;
  late Box<StudyLog> studyLogs;
  late Box<UserSettings> userSettings;
  late Box<dynamic> meta;
  late SyncMetadata metadata;

  const migratedAt = 1_700_000_000_000;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cotv_migration_test_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapters();
    }
    tasks = await Hive.openBox<Task>('m_tasks');
    subjects = await Hive.openBox<Subject>('m_subjects');
    studyLogs = await Hive.openBox<StudyLog>('m_logs');
    userSettings = await Hive.openBox<UserSettings>('m_settings');
    meta = await Hive.openBox<dynamic>('m_meta');
    metadata = SyncMetadata(meta);
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  Future<void> migrate() => runHiveMigrations(
        metadata: metadata,
        tasks: tasks,
        subjects: subjects,
        studyLogs: studyLogs,
        userSettings: userSettings,
        clock: () => migratedAt,
      );

  group('backfill', () {
    test('records with their own timestamp keep it', () async {
      final march = DateTime(2026, 3, 2, 9, 30);
      // Written straight to the box, bypassing the repositories, which is
      // what a row from before the migration looks like.
      await tasks.put('t1', Task(id: 't1', title: 'Old', createdAt: march));
      await subjects.put(
        's1',
        Subject(
          id: 's1',
          name: 'Physiology',
          colorValue: 0xFF000000,
          createdAt: march,
        ),
      );
      await studyLogs.put(
        'study-s1-1',
        StudyLog(
          id: 'study-s1-1',
          subjectId: 's1',
          subjectName: 'Physiology',
          durationMinutes: 45,
          timestamp: march,
        ),
      );

      await migrate();

      final expected = march.millisecondsSinceEpoch;
      expect(tasks.get('t1')!.updatedAtMillis, expected);
      expect(subjects.get('s1')!.updatedAtMillis, expected);
      expect(studyLogs.get('study-s1-1')!.updatedAtMillis, expected);
    });

    test('records with no timestamp fall back to the migration instant',
        () async {
      await userSettings.put(UserSettings.defaultId, UserSettings());

      await migrate();

      // Not zero. Zero means "older than anything", which on the first sync
      // would lose the device holding the real data to an empty remote.
      expect(
        userSettings.get(UserSettings.defaultId)!.updatedAtMillis,
        migratedAt,
      );
    });

    test('syncedAtMillis is left null so everything gets pushed', () async {
      await tasks.put('t1', Task(id: 't1', title: 'Old'));
      await migrate();
      expect(tasks.get('t1')!.syncedAtMillis, isNull);
    });

    test('is idempotent — a second run changes nothing', () async {
      final march = DateTime(2026, 3, 2);
      await tasks.put('t1', Task(id: 't1', title: 'Old', createdAt: march));

      await migrate();
      final taskStamp = tasks.get('t1')!.updatedAtMillis;

      // A later run, with a later clock: already-stamped rows must not move.
      await backfillSyncMetadata(
        tasks: tasks,
        subjects: subjects,
        studyLogs: studyLogs,
        userSettings: userSettings,
        migratedAtMillis: migratedAt + 999_999,
      );

      expect(tasks.get('t1')!.updatedAtMillis, taskStamp);
    });

    test('an empty install migrates without inventing records', () async {
      await migrate();
      expect(tasks.isEmpty, isTrue);
      // The settings box stays empty too: get() synthesises defaults on
      // read, and writing them here would push a record the user never
      // touched over one the other device may have.
      expect(userSettings.isEmpty, isTrue);
    });
  });

  group('version marker', () {
    test('starts at zero and lands on the current version', () async {
      expect(metadata.schemaVersion, 0);
      await migrate();
      expect(metadata.schemaVersion, HiveMigrations.currentVersion);
    });

    test('an already-migrated box is not rewritten', () async {
      await metadata.setSchemaVersion(HiveMigrations.currentVersion);
      await tasks.put('t1', Task(id: 't1', title: 'Untouched'));

      await migrate();

      expect(tasks.get('t1')!.updatedAtMillis, isNull,
          reason: 'the step was already recorded as done');
    });

    test('the backup runs before anything is rewritten', () async {
      var backupRan = false;
      int? stampAtBackupTime;
      await tasks.put('t1', Task(id: 't1', title: 'Old'));

      await runHiveMigrations(
        metadata: metadata,
        tasks: tasks,
        subjects: subjects,
        studyLogs: studyLogs,
        userSettings: userSettings,
        clock: () => migratedAt,
        backup: () async {
          backupRan = true;
          stampAtBackupTime = tasks.get('t1')!.updatedAtMillis;
        },
      );

      expect(backupRan, isTrue);
      expect(stampAtBackupTime, isNull,
          reason: 'a backup taken after the rewrite would be worthless');
    });

    test('the backup is skipped when there is nothing to migrate', () async {
      await metadata.setSchemaVersion(HiveMigrations.currentVersion);
      var backupRan = false;

      await runHiveMigrations(
        metadata: metadata,
        tasks: tasks,
        subjects: subjects,
        studyLogs: studyLogs,
        userSettings: userSettings,
        backup: () async => backupRan = true,
      );

      expect(backupRan, isFalse);
    });
  });

  group('cursors', () {
    test('round-trip and reset', () async {
      await metadata.setSchemaVersion(HiveMigrations.currentVersion);
      await metadata.setLastPulled('tasks', '2026-09-17T05:00:00Z');
      await metadata.setLastPulled('reminders', '2026-09-17T05:01:00Z');
      await metadata.setLastSyncedUserId('user-1');

      expect(metadata.lastPulled('tasks'), '2026-09-17T05:00:00Z');

      await metadata.resetCursors();

      expect(metadata.lastPulled('tasks'), isNull);
      expect(metadata.lastPulled('reminders'), isNull);
      // The account survives a cursor reset: it is what detects the switch
      // that caused the reset in the first place.
      expect(metadata.lastSyncedUserId, 'user-1');
      // And the schema marker: dropping it would re-run the backfill over
      // records that already have their metadata.
      expect(metadata.schemaVersion, HiveMigrations.currentVersion);
    });
  });
}
