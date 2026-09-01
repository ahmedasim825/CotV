import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/task.dart';
import '../models/task_view.dart';
import 'clock_providers.dart';
import 'task_providers.dart';

/// Which category tab the task list is showing.
class TaskFilterNotifier extends Notifier<TaskFilter> {
  @override
  TaskFilter build() => TaskFilter.today;

  void select(TaskFilter filter) => state = filter;
}

final taskFilterProvider =
    NotifierProvider<TaskFilterNotifier, TaskFilter>(TaskFilterNotifier.new);

/// How the visible tasks are ordered.
class TaskSortNotifier extends Notifier<TaskSort> {
  @override
  TaskSort build() => TaskSort.priority;

  void select(TaskSort sort) => state = sort;

  void toggle() => state =
      state == TaskSort.priority ? TaskSort.dueTime : TaskSort.priority;
}

final taskSortProvider =
    NotifierProvider<TaskSortNotifier, TaskSort>(TaskSortNotifier.new);

/// The filtered, sorted task list the UI renders.
///
/// Stays an [AsyncValue] so the list can show a real loading state on first
/// open rather than flashing an empty list, and surfaces a Hive read failure
/// instead of silently rendering nothing.
///
/// The "today" boundary comes from [currentMinuteProvider], so a task due at
/// 23:59 moves out of Today on its own at midnight without a manual refresh.
final visibleTasksProvider = Provider.autoDispose<AsyncValue<List<Task>>>((ref) {
  final filter = ref.watch(taskFilterProvider);
  final sort = ref.watch(taskSortProvider);
  final now = ref.watch(currentMinuteProvider);

  return ref.watch(taskListProvider).whenData(
        (tasks) => buildTaskView(tasks, filter: filter, sort: sort, now: now),
      );
});

/// Per-tab counts for the filter chips. Uses the same [filterTasks] the list
/// itself does, so a badge can never disagree with what the tab opens to.
final taskFilterCountsProvider =
    Provider.autoDispose<Map<TaskFilter, int>>((ref) {
  final now = ref.watch(currentMinuteProvider);
  final tasks = ref.watch(taskListProvider).value ?? const <Task>[];
  return {
    for (final filter in TaskFilter.values)
      filter: filterTasks(tasks, filter, now).length,
  };
});
