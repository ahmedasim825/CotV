import 'package:flutter/foundation.dart';

import 'reminder.dart';
import 'task.dart';

/// Which of the two lists a row came from.
///
/// The iOS dashboard shows tasks and reminders interleaved under one title,
/// with no headings between them, so this is what the row's ring colour
/// encodes — and it is the only thing telling the two apart on screen.
enum AgendaKind { task, reminder }

/// One row of the merged dashboard agenda.
///
/// A flattening of [Task] and [Reminder] down to what a row actually draws,
/// so the widget never branches on which box a row came from — it reads
/// [kind] for the colour and [isCompleted] for the tick, and nothing else.
@immutable
class AgendaEntry {
  const AgendaEntry({
    required this.id,
    required this.sourceId,
    required this.title,
    required this.due,
    required this.kind,
    this.isCompleted = false,
  });

  /// Unique across both kinds, so a widget key built from it cannot collide.
  ///
  /// Tasks and reminders are stored in separate boxes and neither knows about
  /// the other's ids, so nothing stops the same string appearing in both. The
  /// `task-` / `reminder-` prefix is what makes this safe to key rows on.
  final String id;

  /// The bare id in the originating box — what `toggleCompleted` and the edit
  /// sheet need, neither of which knows about the prefix above.
  final String sourceId;

  final String title;

  /// Never null. Both sides of the merge are dated: `TaskFilter.today` selects
  /// on `dueDate != null`, and a [Reminder] cannot exist without a `dueAt`.
  final DateTime due;

  final AgendaKind kind;

  /// Always false for a reminder — there is nothing to tick.
  final bool isCompleted;

  /// Strictly before [now], matching [Reminder.isOverdue]. A row landing on
  /// the current instant has not been missed.
  bool isOverdue(DateTime now) => due.isBefore(now);
}

/// Merges today's [tasks] and all [reminders] into one list, soonest first.
///
/// The ordering is total — due instant, then kind, then id — because the card
/// draws no headings and no separators, so two rows that swapped places
/// between rebuilds would look like the list had reordered itself for no
/// reason. [sortTasks] takes the same care for the same reason.
///
/// A task with no due date cannot reach here: the dashboard reads
/// `todayFocusTasksProvider`, which is `TaskFilter.today`, which selects on
/// `dueDate != null`. The skip below is that invariant made explicit — not a
/// fallback position for undated tasks, which have no defensible place in a
/// list whose only ordering is time.
///
/// Note this discards the priority ordering `todayFocusTasksProvider` applies.
/// That is the point of the merge: a task and a reminder can only be ranked
/// against each other by when they are due, so time has to win.
List<AgendaEntry> mergeAgenda(List<Task> tasks, List<Reminder> reminders) {
  final entries = <AgendaEntry>[
    for (final task in tasks)
      if (task.dueDate != null)
        AgendaEntry(
          id: 'task-${task.id}',
          sourceId: task.id,
          title: task.title,
          due: task.dueDate!,
          kind: AgendaKind.task,
          isCompleted: task.isCompleted,
        ),
    for (final reminder in reminders)
      AgendaEntry(
        id: 'reminder-${reminder.id}',
        sourceId: reminder.id,
        title: reminder.title,
        due: reminder.dueAt,
        kind: AgendaKind.reminder,
      ),
  ];

  entries.sort((a, b) {
    final byDue = a.due.compareTo(b.due);
    if (byDue != 0) return byDue;

    // A task and a reminder falling on the same minute is common — a task due
    // at 13:00 and the reminder that tells you about it. Tasks first, so the
    // thing to do outranks the nudge about it.
    final byKind = a.kind.index.compareTo(b.kind.index);
    if (byKind != 0) return byKind;

    return a.id.compareTo(b.id);
  });

  return List.unmodifiable(entries);
}
