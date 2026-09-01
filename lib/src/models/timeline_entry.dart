import 'calendar_sync_models.dart';
import 'daily_prayer_times.dart';
import 'schedule_item.dart';
import 'task.dart';

/// One placed block on the daily timeline.
///
/// Sealed so the rendering layer must handle every kind explicitly — adding
/// a new block type is a compile error at each `switch`, not a silently
/// missing case.
sealed class TimelineEntry {
  const TimelineEntry();

  /// Unique within a single day's timeline; used as the widget key so
  /// blocks keep their identity (and their animations) across rebuilds.
  String get id;

  String get title;

  DateTime get start;

  DateTime get end;

  /// Read-only entries can't be dragged, edited or deleted from the
  /// timeline — the prayer blocks are derived state, not user data.
  bool get isReadOnly;

  Duration get duration => end.difference(start);

  bool containsTime(DateTime time) =>
      !time.isBefore(start) && time.isBefore(end);
}

/// A prayer lockout block, derived from the day's calculated timings.
final class PrayerLockoutEntry extends TimelineEntry {
  const PrayerLockoutEntry(this.window);

  final PrayerLockoutWindow window;

  @override
  String get id => 'prayer:${window.prayer.key}';

  @override
  String get title => '${window.prayer.displayName} — Prayer Lockout';

  @override
  DateTime get start => window.start;

  @override
  DateTime get end => window.end;

  @override
  bool get isReadOnly => true;
}

/// A user-created block from the schedule repository.
final class ScheduleItemEntry extends TimelineEntry {
  const ScheduleItemEntry(this.item);

  final ScheduleItem item;

  @override
  String get id => 'schedule:${item.id}';

  @override
  String get title => item.title;

  @override
  DateTime get start => item.startTime;

  @override
  DateTime get end => item.endTime;

  @override
  bool get isReadOnly => item.isPrayerBlocked;
}

/// A task with a due time, shown at its deadline.
///
/// Tasks are instants rather than spans, so [end] is synthesised by adding
/// [taskBlockDuration] purely to give the block a legible height.
final class TaskEntry extends TimelineEntry {
  const TaskEntry(this.task, this.dueDate);

  /// Minimum on-timeline height for a task, expressed as time.
  static const Duration taskBlockDuration = Duration(minutes: 30);

  final Task task;

  /// [Task.dueDate] hoisted to a non-null field — a [TaskEntry] is only
  /// ever built for a task that has one.
  final DateTime dueDate;

  @override
  String get id => 'task:${task.id}';

  @override
  String get title => task.title;

  @override
  DateTime get start => dueDate;

  @override
  DateTime get end => dueDate.add(taskBlockDuration);

  @override
  bool get isReadOnly => false;
}

/// A [TimelineEntry] plus the horizontal slot it was assigned, so mutually
/// overlapping blocks sit side by side instead of on top of each other.
class PlacedTimelineEntry {
  const PlacedTimelineEntry({
    required this.entry,
    required this.column,
    required this.columnCount,
  });

  final TimelineEntry entry;

  /// Zero-based slot within the overlapping cluster.
  final int column;

  /// How many slots that cluster needed. Always at least 1, so
  /// `column / columnCount` is a safe horizontal fraction.
  final int columnCount;
}

/// Assigns each entry a column so that no two overlapping entries share
/// one, using the standard greedy sweep used by calendar UIs.
///
/// Entries are swept in start order and grouped into clusters of
/// transitively-overlapping blocks; every entry in a cluster is widened to
/// the same [PlacedTimelineEntry.columnCount] so a cluster reads as an
/// aligned grid rather than a ragged staircase.
List<PlacedTimelineEntry> layoutTimelineEntries(List<TimelineEntry> entries) {
  if (entries.isEmpty) return const [];

  final sorted = [...entries]..sort((a, b) {
      final byStart = a.start.compareTo(b.start);
      return byStart != 0 ? byStart : b.duration.compareTo(a.duration);
    });

  final placed = <PlacedTimelineEntry>[];
  var cluster = <TimelineEntry>[];
  var clusterColumns = <int>[];
  // Column index -> the end time of the last entry placed in it.
  var columnEnds = <DateTime>[];
  DateTime? clusterEnd;

  void flushCluster() {
    if (cluster.isEmpty) return;
    final columnCount = columnEnds.length;
    for (var i = 0; i < cluster.length; i++) {
      placed.add(
        PlacedTimelineEntry(
          entry: cluster[i],
          column: clusterColumns[i],
          columnCount: columnCount,
        ),
      );
    }
    cluster = [];
    clusterColumns = [];
    columnEnds = [];
    clusterEnd = null;
  }

  for (final entry in sorted) {
    // A gap with the whole cluster so far closes it out.
    if (clusterEnd != null && !entry.start.isBefore(clusterEnd!)) {
      flushCluster();
    }

    var column = columnEnds.indexWhere((end) => !entry.start.isBefore(end));
    if (column == -1) {
      columnEnds.add(entry.end);
      column = columnEnds.length - 1;
    } else {
      columnEnds[column] = entry.end;
    }

    cluster.add(entry);
    clusterColumns.add(column);
    clusterEnd =
        clusterEnd == null || entry.end.isAfter(clusterEnd!) ? entry.end : clusterEnd;
  }

  flushCluster();
  return placed;
}
