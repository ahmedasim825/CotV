import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../../hive_registrar.g.dart';
import '../models/active_study_session.dart';
import '../models/chat_message.dart';
import '../models/habit.dart';
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
  static const String habits = 'habits';
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
Future<void> initializeLocalStorage() async {
  if (_initialized) return;

  await Hive.initFlutter();
  Hive.registerAdapters();

  await Future.wait([
    Hive.openBox<Task>(HiveBoxes.tasks),
    Hive.openBox<Habit>(HiveBoxes.habits),
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
    habits: Hive.box<Habit>(HiveBoxes.habits),
    subjects: Hive.box<Subject>(HiveBoxes.subjects),
    studyLogs: Hive.box<StudyLog>(HiveBoxes.studyLogs),
    userSettings: Hive.box<UserSettings>(HiveBoxes.userSettings),
    backup: backupLocalStores,
  );

  _initialized = true;
}
