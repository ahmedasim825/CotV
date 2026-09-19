import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/task.dart';
import '../ui/format/time_format.dart';
import 'notification_providers.dart';

/// Keeps a task's local notifications in step with the task itself.
///
/// Called from the task write paths rather than watching the task list,
/// because a reminder should only be (re)scheduled in response to a
/// deliberate edit — reacting to every stream emission would re-schedule
/// every reminder on every unrelated task change.
///
/// Every method is best-effort: a task must still save when notification
/// permission has been refused, so scheduling failures are swallowed rather
/// than propagated into the save path.
///
/// ## Two notifications, two keys
///
/// A task can hold both a reminder at its due moment and an earlier warning.
/// `NotificationService` derives a notification id by hashing the key it is
/// given and cancels that key before scheduling it, so a second reminder filed
/// under the task's own id would silently replace the first. The early one
/// therefore gets a suffixed key of its own, which hashes into a different
/// slot of the same reserved range — and every path that cancels has to cancel
/// both, or deleting a task strands the early warning to fire on its own.
class TaskReminderController {
  const TaskReminderController(this._ref);

  final Ref _ref;

  /// The key the early warning is filed under, derived from the task's own so
  /// no separate bookkeeping is needed to find it again.
  static String earlyKeyFor(String taskId) => '$taskId#early';

  /// Schedules, reschedules or cancels [task]'s reminders to match its
  /// current state. Returns whether a reminder is now pending at the due
  /// moment — the early one is reconciled either way, but it is not what
  /// callers mean by "does this task remind".
  Future<bool> sync(Task task) async {
    final service = _ref.read(notificationServiceProvider);
    final dueDate = task.dueDate;
    final earlyKey = earlyKeyFor(task.id);

    try {
      if (!task.wantsReminder || dueDate == null) {
        await service.cancelReminder(task.id);
        await service.cancelReminder(earlyKey);
        return false;
      }

      final early = task.earlyReminder.leadFrom(dueDate);
      if (early == null) {
        await service.cancelReminder(earlyKey);
      } else {
        // No guard on the moment having passed: `scheduleReminder` already
        // answers false rather than throwing for a time in the past, which is
        // the ordinary case for a task created close to its deadline.
        await service.scheduleReminder(
          key: earlyKey,
          when: early,
          title: task.title,
          body: 'Due ${formatReminderDueLine(dueDate, DateTime.now())}.',
        );
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

  /// Drops every reminder held for [taskId] — used when a task is deleted.
  Future<void> cancel(String taskId) async {
    try {
      final service = _ref.read(notificationServiceProvider);
      await service.cancelReminder(taskId);
      await service.cancelReminder(earlyKeyFor(taskId));
    } catch (_) {
      // Nothing to recover: the task is gone either way.
    }
  }
}

final taskReminderControllerProvider = Provider<TaskReminderController>(
  TaskReminderController.new,
);
