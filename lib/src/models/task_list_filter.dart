import 'day_groups.dart';
import 'task_list_entry.dart';

/// What the tasks screen's menu is currently narrowing the list to.
///
/// Single-select: one entry is active and carries the tick, and the button
/// shows its label. The five are not two axes — picking `tasks` does not also
/// let you pick `past` — because the design draws one checkmark, and a menu
/// whose button has to describe a combination stops being a one-word button.
enum TaskListFilter { all, upcoming, past, tasks, reminders }

extension TaskListFilterX on TaskListFilter {
  /// The menu entry, and the button's label while this one is active.
  String get label {
    switch (this) {
      case TaskListFilter.all:
        return 'All';
      case TaskListFilter.upcoming:
        return 'Upcoming';
      case TaskListFilter.past:
        return 'Past';
      case TaskListFilter.tasks:
        return 'Tasks';
      case TaskListFilter.reminders:
        return 'Reminders';
    }
  }

  /// Which half of the calendar this filter shows.
  ///
  /// Only [TaskListFilter.upcoming] looks forward. The two kind filters sit on
  /// the default range rather than spanning everything: they answer "which of
  /// these two things am I looking at", not "how far out".
  DayRange get range => this == TaskListFilter.upcoming
      ? DayRange.upcoming
      : DayRange.pastAndToday;

  /// Whether [TaskListFilter.past] should suppress the Today section.
  ///
  /// [groupByDay] always emits Today so the inline add row has somewhere to
  /// live. Under this one filter that is wrong — "Past" that opens on today is
  /// not past — so the screen drops it afterwards rather than teaching the
  /// grouping about filters.
  bool get hidesToday => this == TaskListFilter.past;

  /// Null when the filter does not narrow by kind.
  TaskListKind? get kind {
    switch (this) {
      case TaskListFilter.tasks:
        return TaskListKind.task;
      case TaskListFilter.reminders:
        return TaskListKind.reminder;
      case TaskListFilter.all:
      case TaskListFilter.upcoming:
      case TaskListFilter.past:
        return null;
    }
  }

  /// The SF Symbol beside the entry, or null for the three that carry none.
  ///
  /// Only the two kind filters are illustrated, which is what separates them
  /// from the time filters above the divider without needing a heading.
  String? get sfSymbol {
    switch (this) {
      case TaskListFilter.tasks:
        return 'list.bullet';
      case TaskListFilter.reminders:
        return 'clock';
      case TaskListFilter.all:
      case TaskListFilter.upcoming:
      case TaskListFilter.past:
        return null;
    }
  }
}
