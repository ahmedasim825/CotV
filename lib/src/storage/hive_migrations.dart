import 'dart:io';

import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../models/habit.dart';
import '../models/study_log.dart';
import '../models/subject.dart';
import '../models/task.dart';
import '../models/user_settings.dart';
import 'app_database.dart';
import 'local_storage.dart';
import 'sync_metadata.dart';

/// Schema steps applied to the Hive boxes at startup.
///
/// Hive has no `user_version` of its own, so the marker lives in
/// [SyncMetadata]. Each step is guarded by the version it upgrades *from*,
/// the same shape [AppDatabase] uses for SQLite, so a device at any older
/// version walks forward through every step in order.
class HiveMigrations {
  const HiveMigrations._();

  /// Bumped whenever a step is added below.
  static const int currentVersion = 1;

  /// v1: every synced record gains [SyncStamped] metadata.
  static const int _syncMetadataVersion = 1;
}

/// Brings the open boxes up to [HiveMigrations.currentVersion].
///
/// Takes its boxes rather than reading them off [Hive] so a test can drive
/// it against temp-directory boxes without a plugin.
Future<void> runHiveMigrations({
  required SyncMetadata metadata,
  required Box<Task> tasks,
  required Box<Habit> habits,
  required Box<Subject> subjects,
  required Box<StudyLog> studyLogs,
  required Box<UserSettings> userSettings,
  int Function()? clock,
  Future<void> Function()? backup,
}) async {
  final from = metadata.schemaVersion;
  if (from >= HiveMigrations.currentVersion) return;

  // Before anything is rewritten, not after. This is the only step that
  // cannot be undone by fixing the code and running again.
  if (backup != null) await backup();

  final now = (clock ?? () => DateTime.now().millisecondsSinceEpoch)();

  if (from < HiveMigrations._syncMetadataVersion) {
    await backfillSyncMetadata(
      tasks: tasks,
      habits: habits,
      subjects: subjects,
      studyLogs: studyLogs,
      userSettings: userSettings,
      migratedAtMillis: now,
    );
  }

  // Written last, so a crash part-way through re-runs the step rather than
  // skipping it. Every step above is idempotent for that reason.
  await metadata.setSchemaVersion(HiveMigrations.currentVersion);
}

/// Gives every record written before sync existed an `updatedAtMillis`.
///
/// Where the record already carries a timestamp of its own that is used,
/// so a task created last March sorts as older than one created today.
/// Habits and settings carry none, and those fall back to
/// [migratedAtMillis] — **not** to zero. Zero means "older than anything",
/// which on the first sync would make the device holding all the real data
/// lose every habit to an empty remote.
///
/// `syncedAtMillis` is deliberately left null: every existing record is
/// then dirty, and the first sync pushes all of it, which is correct
/// because the server has nothing yet.
///
/// Idempotent — the null test skips records a previous run already stamped.
Future<void> backfillSyncMetadata({
  required Box<Task> tasks,
  required Box<Habit> habits,
  required Box<Subject> subjects,
  required Box<StudyLog> studyLogs,
  required Box<UserSettings> userSettings,
  required int migratedAtMillis,
}) async {
  Future<void> stamp<T>(
    Box<T> box,
    int? Function(T) existing,
    T Function(T) apply,
  ) async {
    final pending = <dynamic, T>{};
    for (final key in box.keys) {
      final record = box.get(key);
      if (record == null || existing(record) != null) continue;
      pending[key] = apply(record);
    }
    if (pending.isNotEmpty) await box.putAll(pending);
  }

  await stamp<Task>(
    tasks,
    (task) => task.updatedAtMillis,
    (task) => task.stampUpdated(task.createdAt.millisecondsSinceEpoch),
  );
  await stamp<Subject>(
    subjects,
    (subject) => subject.updatedAtMillis,
    (subject) => subject.stampUpdated(subject.createdAt.millisecondsSinceEpoch),
  );
  await stamp<StudyLog>(
    studyLogs,
    (log) => log.updatedAtMillis,
    (log) => log.stampUpdated(log.timestamp.millisecondsSinceEpoch),
  );
  await stamp<Habit>(
    habits,
    (habit) => habit.updatedAtMillis,
    (habit) => habit.stampUpdated(migratedAtMillis),
  );
  await stamp<UserSettings>(
    userSettings,
    (settings) => settings.updatedAtMillis,
    (settings) => settings.stampUpdated(migratedAtMillis),
  );
}

/// Copies the local stores somewhere safe, once, before the first sync
/// migration rewrites them.
///
/// Lives under application support rather than beside the boxes, which sit
/// directly in the user's Documents folder and do not need a backup
/// directory appearing next to them.
///
/// Best-effort: a device that cannot write the backup still gets the
/// migration. Losing the copy is worse than not having it, but refusing to
/// start the app over it would be worse still.
Future<void> backupLocalStores() async {
  try {
    final support = await getApplicationSupportDirectory();
    final destination = Directory('${support.path}/pre-sync-backup');
    if (destination.existsSync()) return;
    destination.createSync(recursive: true);

    final documents = await getApplicationDocumentsDirectory();
    final sources = <File>[
      for (final name in const [
        HiveBoxes.tasks,
        HiveBoxes.habits,
        HiveBoxes.userSettings,
        HiveBoxes.subjects,
        HiveBoxes.studyLogs,
        HiveBoxes.chatMessages,
        HiveBoxes.activeStudySession,
      ])
        File('${documents.path}/$name.hive'),
      File('${support.path}/${AppDatabase.fileName}'),
    ];

    for (final source in sources) {
      if (!source.existsSync()) continue;
      final name = source.uri.pathSegments.last;
      source.copySync('${destination.path}/$name');
    }
  } on FileSystemException {
    // Nothing to do about it here, and not a reason to refuse to launch.
  }
}
