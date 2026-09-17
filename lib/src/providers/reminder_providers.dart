import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../models/reminder.dart';
import '../repositories/reminder_repository.dart';
import '../storage/local_storage.dart';

final reminderBoxProvider =
    Provider<Box<Reminder>>((ref) => Hive.box<Reminder>(HiveBoxes.reminders));

final reminderRepositoryProvider = Provider<ReminderRepository>((ref) {
  return HiveReminderRepository(ref.watch(reminderBoxProvider));
});

/// The live reminder list plus CRUD actions.
///
/// Reminders used to be a plain in-memory [Notifier] seeded with two samples,
/// because there was no box, adapter or repository behind them. Giving the
/// rows checkboxes is what forced the change: a tick that vanishes on the next
/// launch is worse than no tick at all.
///
/// Every write goes through the repository, which mutates the Hive box; the
/// box's own change stream flows back into this provider's state, so the UI
/// never needs manual invalidation. Same shape as [TaskListNotifier], minus
/// the notification reconciliation — a reminder schedules nothing yet.
class ReminderListNotifier extends StreamNotifier<List<Reminder>> {
  ReminderRepository get _repository => ref.read(reminderRepositoryProvider);

  @override
  Stream<List<Reminder>> build() => _repository.watchAll();

  /// Named for the entity rather than the verb alone, matching
  /// [TaskListNotifier] — and because a bare `update` collides with
  /// `StreamNotifier`'s own state-updating method.
  Future<void> addReminder(Reminder reminder) => _repository.add(reminder);

  Future<void> updateReminder(Reminder reminder) =>
      _repository.update(reminder);

  Future<void> deleteReminder(String id) => _repository.delete(id);

  Future<void> toggleCompleted(String id) => _repository.toggleCompleted(id);
}

final reminderListProvider =
    StreamNotifierProvider<ReminderListNotifier, List<Reminder>>(
  ReminderListNotifier.new,
);
