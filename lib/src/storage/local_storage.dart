import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../../hive_registrar.g.dart';
import '../models/habit.dart';
import '../models/journal_entry.dart';
import '../models/schedule_item.dart';
import '../models/task.dart';
import '../models/user_settings.dart';

/// Box names — kept in one place so repositories and tests agree on them.
class HiveBoxes {
  const HiveBoxes._();

  static const String tasks = 'tasks';
  static const String habits = 'habits';
  static const String scheduleItems = 'schedule_items';
  static const String journalEntries = 'journal_entries';
  static const String userSettings = 'user_settings';
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
    Hive.openBox<ScheduleItem>(HiveBoxes.scheduleItems),
    Hive.openBox<JournalEntry>(HiveBoxes.journalEntries),
    Hive.openBox<UserSettings>(HiveBoxes.userSettings),
  ]);

  _initialized = true;
}
