// The second notification a task can hold, and the lead time that decides
// when it fires.
//
// The due reminder and the early one are filed under different keys on
// purpose: `NotificationService` derives an id by hashing the key and cancels
// that key before scheduling it, so one key would mean the early warning
// silently replaced the reminder at the due moment.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cotv/src/models/task.dart';
import 'package:cotv/src/providers/notification_providers.dart';
import 'package:cotv/src/providers/task_reminder_providers.dart';
import 'package:cotv/src/services/notification_service.dart';

/// Records what was scheduled and cancelled instead of touching the platform
/// channel, which never answers under `flutter_test`.
class _SpyNotifications extends NotificationService {
  final List<({String key, DateTime when})> scheduled = [];
  final List<String> cancelled = [];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> requestPermissions() async {}

  @override
  Future<bool> scheduleReminder({
    required String key,
    required DateTime when,
    required String title,
    required String body,
  }) async {
    // Mirrors the real service, which refuses a moment that has passed.
    if (!when.isAfter(DateTime.now())) return false;
    scheduled.add((key: key, when: when));
    return true;
  }

  @override
  Future<void> cancelReminder(String key) async => cancelled.add(key);
}

({TaskReminderController controller, _SpyNotifications spy}) _build() {
  final spy = _SpyNotifications();
  final container = ProviderContainer(
    overrides: [notificationServiceProvider.overrideWithValue(spy)],
  );
  addTearDown(container.dispose);
  return (controller: container.read(taskReminderControllerProvider), spy: spy);
}

Task _task({
  TaskEarlyReminder early = TaskEarlyReminder.never,
  Duration until = const Duration(days: 30),
}) {
  return Task(
    id: 't1',
    title: 'Read chapter 4',
    dueDate: DateTime.now().add(until),
    hasReminder: true,
    earlyReminder: early,
  );
}

void main() {
  group('lead time', () {
    test('never has no moment to fire at', () {
      expect(
        TaskEarlyReminder.never.leadFrom(DateTime(2026, 9, 18, 14)),
        isNull,
      );
    });

    test('days count back from the due moment, keeping the time of day', () {
      expect(
        TaskEarlyReminder.twoDays.leadFrom(DateTime(2026, 9, 18, 14, 30)),
        DateTime(2026, 9, 16, 14, 30),
      );
      expect(
        TaskEarlyReminder.twoWeeks.leadFrom(DateTime(2026, 9, 18, 14, 30)),
        DateTime(2026, 9, 4, 14, 30),
      );
    });

    test('months are calendar months, not 30 days', () {
      expect(
        TaskEarlyReminder.oneMonth.leadFrom(DateTime(2026, 9, 18, 9)),
        DateTime(2026, 8, 18, 9),
      );
      expect(
        TaskEarlyReminder.sixMonths.leadFrom(DateTime(2026, 9, 18, 9)),
        DateTime(2026, 3, 18, 9),
      );
    });

    test('a month before the 31st clamps to the end of a shorter month', () {
      // Not the 1st of March, which is what DateTime's own rollover gives and
      // which reads as a day late rather than a month early.
      expect(
        TaskEarlyReminder.oneMonth.leadFrom(DateTime(2026, 3, 31, 9)),
        DateTime(2026, 2, 28, 9),
      );
    });
  });

  group('scheduling', () {
    test('a task with no early reminder schedules one notification', () async {
      final (:controller, :spy) = _build();

      await controller.sync(_task());

      expect(spy.scheduled.map((s) => s.key), ['t1']);
      // The early key is still cancelled, so turning the option off clears
      // whatever an earlier save left behind.
      expect(spy.cancelled, contains('t1#early'));
    });

    test('an early reminder adds a second under its own key', () async {
      final (:controller, :spy) = _build();
      final task = _task(early: TaskEarlyReminder.oneDay);

      await controller.sync(task);

      expect(spy.scheduled.map((s) => s.key), containsAll(['t1', 't1#early']));
      final early = spy.scheduled.firstWhere((s) => s.key == 't1#early');
      expect(early.when, task.dueDate!.subtract(const Duration(days: 1)));
    });

    test('an early moment already past is simply not scheduled', () async {
      final (:controller, :spy) = _build();

      // Due in an hour, warning a day ahead: that moment is yesterday.
      await controller.sync(
        _task(early: TaskEarlyReminder.oneDay, until: const Duration(hours: 1)),
      );

      expect(spy.scheduled.map((s) => s.key), ['t1']);
    });

    test('a task that no longer wants a reminder clears both', () async {
      final (:controller, :spy) = _build();

      await controller.sync(
        Task(id: 't1', title: 'Read chapter 4', hasReminder: false),
      );

      expect(spy.scheduled, isEmpty);
      expect(spy.cancelled, containsAll(['t1', 't1#early']));
    });

    test('cancelling a deleted task drops both keys', () async {
      final (:controller, :spy) = _build();

      await controller.cancel('t1');

      expect(spy.cancelled, containsAll(['t1', 't1#early']));
    });
  });
}
