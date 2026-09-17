import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/task.dart';
import '../models/task_view.dart';
import 'clock_providers.dart';
import 'task_providers.dart';

/// Today's open tasks, priority first — what the dashboard shortlists.
///
/// The only survivor of this file. The tasks screen used to drive a filter
/// tab, a sort toggle and a per-tab count badge from here; it groups by day
/// now and reads [taskListProvider] directly, so those four providers had no
/// caller left.
///
/// The "today" boundary comes from [currentMinuteProvider], so a task due at
/// 23:59 leaves this list on its own at midnight without a manual refresh.
/// Kept an [AsyncValue] so the card can show a real loading state on first
/// open rather than flashing an empty list, and can surface a Hive read
/// failure instead of silently rendering nothing.
final todayFocusTasksProvider =
    Provider.autoDispose<AsyncValue<List<Task>>>((ref) {
  final now = ref.watch(currentMinuteProvider);

  return ref.watch(taskListProvider).whenData(
        (tasks) => sortTasks(todayTasks(tasks, now), TaskSort.priority),
      );
});
