import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../../hive_registrar.g.dart';
import '../models/active_study_session.dart';
import '../models/chat_message.dart';
import '../models/reminder.dart';
import '../models/study_log.dart';
import '../models/subject.dart';
import '../models/task.dart';
import '../models/user_settings.dart';
import 'hive_migrations.dart';
import 'sync_metadata.dart';

/// Box names — kept in one place so repositories and tests agree on them.
class HiveBoxes {
  const HiveBoxes._();

  static const String tasks = 'tasks';
  static const String reminders = 'reminders';
  // No `habits` here any more. The box file is deliberately left on disk
  // rather than deleted: nothing opens it, its adapter is gone, and an
  // unopened box costs nothing — where erasing it would destroy data the
  // user may still have on another device.
  static const String userSettings = 'user_settings';
  static const String subjects = 'subjects';
  static const String studyLogs = 'study_logs';
  static const String chatMessages = 'chat_messages';
  static const String activeStudySession = 'active_study_session';
  static const String syncMeta = SyncMetadata.boxName;
}

bool _initialized = false;

/// Registers every model's generated [TypeAdapter] (via the build_runner-
/// generated `registerAdapters()`, which auto-discovers every `@HiveType`
/// in the project) and opens every box this app uses. Call once, before
/// `runApp`, and await it.
///
/// Idempotent: safe to call more than once (e.g. across tests in the same
/// isolate) — later calls are a no-op.
/// Opens the app's Hive boxes.
///
/// [subdirectory] puts them somewhere other than the default location, which
/// is what `tool/ios_preview.dart` uses. Hive takes a file lock per box, so a
/// second instance sharing the directory dies on startup with an unhandled
/// `FileSystemException` — and on this machine the installed build and a
/// `flutter run` are routinely open at the same time.
Future<void> initializeLocalStorage({String? subdirectory}) async {
  if (_initialized) return;

  await Hive.initFlutter(subdirectory);
  Hive.registerAdapters();

  await Future.wait([
    Hive.openBox<Task>(HiveBoxes.tasks),
    Hive.openBox<Reminder>(HiveBoxes.reminders),
    Hive.openBox<UserSettings>(HiveBoxes.userSettings),
    Hive.openBox<Subject>(HiveBoxes.subjects),
    Hive.openBox<StudyLog>(HiveBoxes.studyLogs),
    Hive.openBox<ChatMessage>(HiveBoxes.chatMessages),
    Hive.openBox<ActiveStudySession>(HiveBoxes.activeStudySession),
    Hive.openBox<dynamic>(HiveBoxes.syncMeta),
  ]);

  // After the boxes are open and before anything can read them, so no
  // provider ever sees a record without its sync metadata.
  await runHiveMigrations(
    metadata: SyncMetadata(Hive.box<dynamic>(HiveBoxes.syncMeta)),
    tasks: Hive.box<Task>(HiveBoxes.tasks),
    // No `reminders:` here on purpose. The migration exists to backfill
    // sync metadata onto rows written before those fields existed, and the
    // reminders box is new in this version — every row in it has been
    // stamped since the moment it was written.
    subjects: Hive.box<Subject>(HiveBoxes.subjects),
    studyLogs: Hive.box<StudyLog>(HiveBoxes.studyLogs),
    userSettings: Hive.box<UserSettings>(HiveBoxes.userSettings),
    backup: backupLocalStores,
  );

  _initialized = true;
}
