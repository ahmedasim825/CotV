import 'task.dart';

/// The category tabs above the task list.
enum TaskFilter { today, upcoming, completed, priority }

/// How the visible tasks are ordered.
enum TaskSort { priority, dueTime }

extension TaskFilterX on TaskFilter {
  String get label {
    switch (this) {
      case TaskFilter.today:
        return 'Today';
      case TaskFilter.upcoming:
        return 'Upcoming';
      case TaskFilter.completed:
        return 'Completed';
      case TaskFilter.priority:
        return 'Priority';
    }
  }

  /// Shown when the filter matches nothing.
  String get emptyMessage {
    switch (this) {
      case TaskFilter.today:
        return 'Nothing due today. Enjoy the clear run.';
      case TaskFilter.upcoming:
        return 'No upcoming tasks yet.';
      case TaskFilter.completed:
        return 'Completed tasks will collect here.';
      case TaskFilter.priority:
        return 'No high-priority tasks outstanding.';
    }
  }
}

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

/// Selects the tasks a [TaskFilter] should show, relative to [now].
///
/// The four filters are deliberately not a partition: a high-priority task
/// due today appears under both Today and Priority. What matters is that no
/// incomplete task is invisible under *every* tab — tasks with no due date
/// fall to Upcoming rather than vanishing.
List<Task> filterTasks(
  List<Task> tasks,
  TaskFilter filter,
  DateTime now,
) {
  final endOfToday = DateTime(now.year, now.month, now.day)
      .add(const Duration(days: 1));

  switch (filter) {
    case TaskFilter.today:
      // Overdue tasks stay in Today rather than falling off the list.
      return tasks
          .where((t) =>
              !t.isCompleted && t.dueDate != null && t.dueDate!.isBefore(endOfToday))
          .toList(growable: false);
    case TaskFilter.upcoming:
      return tasks
          .where((t) =>
              !t.isCompleted &&
              (t.dueDate == null || !t.dueDate!.isBefore(endOfToday)))
          .toList(growable: false);
    case TaskFilter.completed:
      return tasks.where((t) => t.isCompleted).toList(growable: false);
    case TaskFilter.priority:
      return tasks
          .where((t) => !t.isCompleted && t.priority == TaskPriority.high)
          .toList(growable: false);
  }
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

/// [filterTasks] then [sortTasks] — the single transform the task list UI
/// applies to the raw repository stream.
List<Task> buildTaskView(
  List<Task> tasks, {
  required TaskFilter filter,
  required TaskSort sort,
  required DateTime now,
}) {
  return sortTasks(filterTasks(tasks, filter, now), sort);
}
