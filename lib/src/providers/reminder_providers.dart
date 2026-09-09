import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/reminder.dart';

/// The reminder list, held in memory and seeded with samples.
///
/// Frontend only for now: there is no reminder box, adapter or repository, so
/// edits live until the process exits. That limit is deliberate and the
/// alternative was worse — the card carries an edit affordance, and a pencil
/// that opens nothing is a lie. The three mutators below are the whole
/// surface a real store has to satisfy; making it persistent means turning
/// this into a `StreamNotifier` over a Hive box the way `taskListProvider`
/// already works, and no consumer changes.
class ReminderListController extends Notifier<List<Reminder>> {
  @override
  List<Reminder> build() {
    return [
      Reminder(
        id: 'sample-1',
        title: 'Workout',
        dueAt: DateTime(2026, 7, 27, 3, 0),
      ),
      Reminder(
        id: 'sample-2',
        title: "Watch Dr.Bassant's Lecture",
        dueAt: DateTime(2026, 7, 28, 20, 0),
      ),
    ];
  }

  void add(Reminder reminder) => state = [...state, reminder];

  void update(Reminder reminder) {
    state = [
      for (final existing in state)
        existing.id == reminder.id ? reminder : existing,
    ];
  }

  void remove(String id) =>
      state = state.where((reminder) => reminder.id != id).toList();
}

final reminderListProvider =
    NotifierProvider<ReminderListController, List<Reminder>>(
  ReminderListController.new,
);
