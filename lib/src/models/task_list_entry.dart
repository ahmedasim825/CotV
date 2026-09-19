import 'package:flutter/foundation.dart';

import 'reminder.dart';
import 'task.dart';

/// Which box a row on the tasks screen came out of.
enum TaskListKind { task, reminder }

/// One row of the tasks screen, from either box.
///
/// The screen shows tasks and reminders in one list now, so it needs a single
/// row type to sort, group and render. The two models are nearly the same
/// shape — both carry a title, a completion flag and a priority — and differ
/// only in that a reminder's moment is required where a task's due date is
/// optional.
@immutable
class TaskListEntry {
  const TaskListEntry({
    required this.id,
    required this.sourceId,
    required this.title,
    required this.kind,
    required this.isCompleted,
    required this.priority,
    required this.dueAt,
    required this.bucketDate,
    this.subjectId,
  });

  /// Unique across both kinds, so a widget key built from it cannot collide.
  /// Tasks and reminders live in separate Hive boxes and could share a raw id.
  final String id;

  /// The bare id in the originating box — what the toggle and the edit sheet
  /// need, neither of which knows about the prefix above.
  final String sourceId;

  final String title;
  final TaskListKind kind;
  final bool isCompleted;
  final TaskPriority priority;

  /// The subject a study task is filed under, or null.
  ///
  /// Carried on the entry rather than looked up per row, so building the list
  /// stays a pure function of the two boxes. Always null for a reminder: a
  /// reminder is a moment, and a moment has no subject.
  final String? subjectId;

  /// When this is due, or null for a task that carries no due date.
  ///
  /// Null is what the row reads to decide whether to draw a due line, so it is
  /// kept distinct from [bucketDate] rather than collapsed into it — an
  /// undated task still has to land in a section, but it has nothing to say
  /// about when it is due.
  final DateTime? dueAt;

  /// The date the day-grouping files this under: [dueAt], or the task's
  /// creation date when it has none.
  final DateTime bucketDate;

  /// Strictly before [now], and never true once completed — matching
  /// [Reminder.isOverdue]. A row landing on the current instant has not been
  /// missed, and a finished one cannot be late.
  bool isOverdue(DateTime now) {
    final due = dueAt;
    return !isCompleted && due != null && due.isBefore(now);
  }
}

/// Merges [tasks] and [reminders] into one list for the tasks screen.
///
/// **Not [mergeAgenda].** That one exists for the dashboard card and differs in
/// three ways that each matter here, which is why this is a second function
/// rather than a parameter on the first:
///
///   * it drops undated tasks, because the card reads `todayFocusTasksProvider`
///     where `dueDate != null` already holds. This screen keeps them and files
///     them under [Task.createdAt].
///   * it hard-codes reminders to incomplete, from when a reminder had nothing
///     to tick. Both kinds carry completion now and the screen draws a checkbox
///     on every row.
///   * it discards priority, deliberately, because a card that ranks two kinds
///     against each other can only do it by time. Every row here has a priority
///     dot.
///
/// Collapsing the two would quietly change the dashboard. Twenty tests across
/// `agenda_view_test.dart` and `agenda_card_test.dart` pin those three
/// behaviours precisely so that cannot happen by accident.
///
/// The ordering is total — bucket date, then kind, then id — for the reason
/// [sortTasks] takes the same care: two rows that swapped places between
/// rebuilds would look like the list had reordered itself for no reason.
List<TaskListEntry> mergeTaskList(List<Task> tasks, List<Reminder> reminders) {
  final entries = <TaskListEntry>[
    for (final task in tasks)
      TaskListEntry(
        id: 'task-${task.id}',
        sourceId: task.id,
        title: task.title,
        kind: TaskListKind.task,
        isCompleted: task.isCompleted,
        priority: task.priority,
        subjectId: task.isStudy ? task.subjectId : null,
        dueAt: task.dueDate,
        bucketDate: task.dueDate ?? task.createdAt,
      ),
    for (final reminder in reminders)
      TaskListEntry(
        id: 'reminder-${reminder.id}',
        sourceId: reminder.id,
        title: reminder.title,
        kind: TaskListKind.reminder,
        isCompleted: reminder.isCompleted,
        priority: reminder.priority,
        dueAt: reminder.dueAt,
        bucketDate: reminder.dueAt,
      ),
  ];

  entries.sort((a, b) {
    final byDate = a.bucketDate.compareTo(b.bucketDate);
    if (byDate != 0) return byDate;

    // Tasks before reminders on a tie — the pairing this breaks is a task due
    // at 13:00 and the reminder that tells you about it, and the thing itself
    // reads better above the nudge about it.
    final byKind = a.kind.index.compareTo(b.kind.index);
    if (byKind != 0) return byKind;

    return a.id.compareTo(b.id);
  });

  return List.unmodifiable(entries);
}
