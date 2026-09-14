import 'habit.dart';

/// Midnight-normalized copy of [date] — the form every completion is stored
/// in, so two DateTimes on the same day compare equal.
DateTime normalizeDay(DateTime date) =>
    DateTime(date.year, date.month, date.day);

/// Monday-start week bucket for [date].
DateTime weekStartOf(DateTime date) {
  final day = normalizeDay(date);
  return day.subtract(Duration(days: day.weekday - 1));
}

/// How many days [date]'s month has.
///
/// Day zero of the following month is the last day of this one, which is how
/// you get 28 / 29 / 30 / 31 out of [DateTime]'s own normalisation rather than
/// out of a table with a leap-year rule in it.
int daysInMonth(DateTime date) => DateTime(date.year, date.month + 1, 0).day;

extension HabitFrequencyX on HabitFrequency {
  String get label {
    switch (this) {
      case HabitFrequency.daily:
        return 'Daily';
      case HabitFrequency.weekly:
        return 'Weekly';
    }
  }

  /// How the cadence reads in a sentence, under a habit's title.
  String get cadenceNote {
    switch (this) {
      case HabitFrequency.daily:
        return 'Every day';
      case HabitFrequency.weekly:
        return 'Once a week';
    }
  }

  /// One step backward through the streak.
  Duration get period {
    switch (this) {
      case HabitFrequency.daily:
        return const Duration(days: 1);
      case HabitFrequency.weekly:
        return const Duration(days: 7);
    }
  }

  /// What a completed period is called in the UI.
  String get periodNoun {
    switch (this) {
      case HabitFrequency.daily:
        return 'day';
      case HabitFrequency.weekly:
        return 'week';
    }
  }
}

extension HabitX on Habit {
  /// The bucket [date] falls into for this habit's cadence: the day itself
  /// for a daily habit, the containing week for a weekly one.
  DateTime periodOf(DateTime date) {
    switch (frequency) {
      case HabitFrequency.daily:
        return normalizeDay(date);
      case HabitFrequency.weekly:
        return weekStartOf(date);
    }
  }

  /// The stored completion date that falls in the same period as [date], if
  /// any.
  ///
  /// Toggling a weekly habit off has to remove the date that was actually
  /// recorded — which may be an earlier day in the same week — rather than
  /// today's, or the repository would add a second completion to a week
  /// that is already marked done.
  DateTime? completionDateIn(DateTime date) {
    final target = periodOf(date);
    for (final completed in completedDates) {
      if (periodOf(completed) == target) return completed;
    }
    return null;
  }

  bool isCompletedOn(DateTime date) => completionDateIn(date) != null;

  /// Whether the current period (today, or this week) is already done.
  bool isCompletedNow(DateTime now) => isCompletedOn(now);

  /// Completion flags for the [count] most recent periods, oldest first —
  /// the row of dots on a habit tile. The last entry is the current period.
  List<bool> recentHistory(DateTime now, {int count = 7}) {
    final step = frequency.period;
    var cursor = periodOf(now).subtract(step * (count - 1));
    final history = <bool>[];
    for (var i = 0; i < count; i++) {
      history.add(isCompletedOn(cursor));
      cursor = cursor.add(step);
    }
    return List.unmodifiable(history);
  }
}

/// Aggregate figures for the strip above the habit grid.
class HabitSummary {
  const HabitSummary({
    required this.total,
    required this.completedThisPeriod,
    required this.bestStreak,
    required this.activeStreaks,
  });

  final int total;

  /// How many habits are done for their current period — today for daily
  /// habits, this week for weekly ones.
  final int completedThisPeriod;

  final int bestStreak;

  /// Habits with a streak of at least one period running.
  final int activeStreaks;

  /// 0..1, or 0 when there are no habits at all.
  double get completionRate =>
      total == 0 ? 0 : completedThisPeriod / total;

  bool get isEmpty => total == 0;
}

HabitSummary summarizeHabits(List<Habit> habits, DateTime now) {
  var completed = 0;
  var best = 0;
  var active = 0;

  for (final habit in habits) {
    if (habit.isCompletedNow(now)) completed++;
    if (habit.streakCount > best) best = habit.streakCount;
    if (habit.streakCount > 0) active++;
  }

  return HabitSummary(
    total: habits.length,
    completedThisPeriod: completed,
    bestStreak: best,
    activeStreaks: active,
  );
}

/// Orders the grid: everything still outstanding first (that is what the
/// screen is for), then by longest streak, then alphabetically so the
/// order is total and never reshuffles between rebuilds.
List<Habit> sortHabits(List<Habit> habits, DateTime now) {
  final ordered = [...habits];
  ordered.sort((a, b) {
    final aDone = a.isCompletedNow(now);
    final bDone = b.isCompletedNow(now);
    if (aDone != bDone) return aDone ? 1 : -1;

    final byStreak = b.streakCount.compareTo(a.streakCount);
    if (byStreak != 0) return byStreak;

    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });
  return List.unmodifiable(ordered);
}
