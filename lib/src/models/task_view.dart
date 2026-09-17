import 'task.dart';

/// How the visible tasks are ordered.
enum TaskSort { priority, dueTime }

extension TaskSortX on TaskSort {
  String get label {
    switch (this) {
      case TaskSort.priority:
        return 'Priority';
      case TaskSort.dueTime:
        return 'Due time';
    }
  }
}

extension TaskPriorityX on TaskPriority {
  String get label {
    switch (this) {
      case TaskPriority.low:
        return 'Low';
      case TaskPriority.medium:
        return 'Medium';
      case TaskPriority.high:
        return 'High';
    }
  }

  /// High sorts before Medium before Low, which is the reverse of the
  /// enum's own `index`.
  int get rank {
    switch (this) {
      case TaskPriority.high:
        return 0;
      case TaskPriority.medium:
        return 1;
      case TaskPriority.low:
        return 2;
    }
  }
}

/// Today's outstanding tasks: anything incomplete and dated no later than
/// the end of today, overdue included.
///
/// This is the dashboard's shortlist, and all that survives of the four
/// filter tabs the task list used to carry. The tabs went with the redesign —
/// the list groups by day now — but the dashboard still wants exactly this
/// slice, so the rule moved here rather than being inlined at the one call
/// site that needs it.
///
/// Overdue tasks stay in rather than falling off: a task that was due
/// yesterday is more today's problem, not less.
List<Task> todayTasks(List<Task> tasks, DateTime now) {
  final endOfToday =
      DateTime(now.year, now.month, now.day).add(const Duration(days: 1));

  return tasks
      .where((t) =>
          !t.isCompleted &&
          t.dueDate != null &&
          t.dueDate!.isBefore(endOfToday))
      .toList(growable: false);
}

/// Orders [tasks] by [sort]. Both orderings are total — ties fall through to
/// the remaining key and finally to [Task.createdAt] — so the list never
/// reshuffles between rebuilds for reasons the user can't see.
List<Task> sortTasks(List<Task> tasks, TaskSort sort) {
  int byDue(Task a, Task b) {
    // Undated tasks sink below dated ones under either ordering.
    if (a.dueDate == null && b.dueDate == null) return 0;
    if (a.dueDate == null) return 1;
    if (b.dueDate == null) return -1;
    return a.dueDate!.compareTo(b.dueDate!);
  }

  int byPriority(Task a, Task b) => a.priority.rank.compareTo(b.priority.rank);

  final ordered = [...tasks];
  ordered.sort((a, b) {
    final primary =
        sort == TaskSort.priority ? byPriority(a, b) : byDue(a, b);
    if (primary != 0) return primary;

    final secondary =
        sort == TaskSort.priority ? byDue(a, b) : byPriority(a, b);
    if (secondary != 0) return secondary;

    return a.createdAt.compareTo(b.createdAt);
  });
  return List.unmodifiable(ordered);
}
