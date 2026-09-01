import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/schedule_item.dart';
import '../models/task.dart';
import '../models/timeline_entry.dart';
import 'prayer_providers.dart' show startOfDay;
import 'prayer_window_providers.dart';
import 'schedule_providers.dart';
import 'selected_date_providers.dart';
import 'task_providers.dart';

/// Whether [instant] falls on the calendar day starting at [dayStart].
bool _isOnDay(DateTime instant, DateTime dayStart) {
  final dayEnd = dayStart.add(const Duration(days: 1));
  return !instant.isBefore(dayStart) && instant.isBefore(dayEnd);
}

/// Schedule items that intersect the given day at all, including ones that
/// started the day before and run into it.
List<ScheduleItem> _itemsIntersecting(
  List<ScheduleItem> items,
  DateTime dayStart,
) {
  final dayEnd = dayStart.add(const Duration(days: 1));
  return items
      .where((item) =>
          item.startTime.isBefore(dayEnd) && dayStart.isBefore(item.endTime))
      .toList(growable: false);
}

/// Every block to draw on the timeline for the selected day, already
/// assigned overlap columns.
///
/// Composes three independent sources — the calculated prayer lockouts, the
/// user's [ScheduleItem]s, and any [Task] due that day — so the timeline
/// updates reactively when a task is added, completed or deleted, without
/// the view needing to know where each block came from.
///
/// Completed tasks are dropped: the timeline is a plan for the day ahead,
/// and a finished task is no longer a claim on the user's time.
final timelineEntriesProvider =
    Provider.autoDispose.family<List<PlacedTimelineEntry>, DateTime>(
        (ref, date) {
  final dayStart = startOfDay(date);
  final schedule = ref.watch(dailyPrayerScheduleProvider(dayStart));
  final scheduleItems = ref.watch(scheduleListProvider).value ?? const [];
  final tasks = ref.watch(taskListProvider).value ?? const [];

  final entries = <TimelineEntry>[
    for (final window in schedule.lockoutWindows) PrayerLockoutEntry(window),
    for (final item in _itemsIntersecting(scheduleItems, dayStart))
      ScheduleItemEntry(item),
    for (final task in tasks)
      if (!task.isCompleted &&
          task.dueDate != null &&
          _isOnDay(task.dueDate!, dayStart))
        TaskEntry(task, task.dueDate!),
  ];

  return layoutTimelineEntries(entries);
});

/// The selected day's timeline blocks.
final selectedDayTimelineProvider =
    Provider.autoDispose<List<PlacedTimelineEntry>>((ref) {
  return ref.watch(timelineEntriesProvider(ref.watch(selectedDateProvider)));
});
