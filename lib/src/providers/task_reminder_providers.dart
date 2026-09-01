import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/task.dart';
import '../ui/format/time_format.dart';
import 'notification_providers.dart';

/// Keeps a task's local notification in step with the task itself.
///
/// Called from the task write paths rather than watching the task list,
/// because a reminder should only be (re)scheduled in response to a
/// deliberate edit — reacting to every stream emission would re-schedule
/// every reminder on every unrelated task change.
///
/// Every method is best-effort: a task must still save when notification
/// permission has been refused, so scheduling failures are swallowed rather
/// than propagated into the save path.
class TaskReminderController {
  const TaskReminderController(this._ref);

  final Ref _ref;

  /// Schedules, reschedules or cancels [task]'s reminder to match its
  /// current state. Returns whether a reminder is now pending.
  Future<bool> sync(Task task) async {
    final service = _ref.read(notificationServiceProvider);
    final dueDate = task.dueDate;

    try {
      if (!task.wantsReminder || dueDate == null) {
        await service.cancelReminder(task.id);
        return false;
      }

      return await service.scheduleReminder(
        key: task.id,
        when: dueDate,
        title: task.title,
        body: 'Due at ${formatClock(dueDate)}.',
      );
    } catch (_) {
      // Permission denied or the platform refused the slot. The task itself
      // is already saved; the reminder simply won't fire.
      return false;
    }
  }

  /// Drops any reminder held for [taskId] — used when a task is deleted.
  Future<void> cancel(String taskId) async {
    try {
      await _ref.read(notificationServiceProvider).cancelReminder(taskId);
    } catch (_) {
      // Nothing to recover: the task is gone either way.
    }
  }
}

final taskReminderControllerProvider = Provider<TaskReminderController>(
  TaskReminderController.new,
);
