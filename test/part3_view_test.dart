// Pure-Dart tests for the habit view models. No Hive, no widgets — these
// are the transforms the habit grid is built on.

import 'package:flutter_test/flutter_test.dart';

import 'package:cotv/src/models/habit.dart';
import 'package:cotv/src/models/habit_view.dart';

Habit _habit({
  String id = 'h1',
  String title = 'Dhikr',
  HabitFrequency frequency = HabitFrequency.daily,
  List<DateTime>? completed,
  int streak = 0,
}) {
  return Habit(
    id: id,
    title: title,
    frequency: frequency,
    completedDates: completed,
    streakCount: streak,
  );
}

void main() {
  group('HabitX periods', () {
    final now = DateTime(2026, 9, 2, 14, 30);

    test('a daily habit is complete only on the exact day', () {
      final habit = _habit(completed: [DateTime(2026, 9, 2)]);

      expect(habit.isCompletedNow(now), isTrue);
      expect(habit.isCompletedOn(DateTime(2026, 9, 1)), isFalse);
    });

    test('a weekly habit counts any day in the same Monday-start week', () {
      // 2026-08-31 is the Monday of the week containing 2026-09-02.
      final habit = _habit(
        frequency: HabitFrequency.weekly,
        completed: [DateTime(2026, 8, 31)],
      );

      expect(habit.isCompletedNow(now), isTrue);
      // The previous week is untouched.
      expect(habit.isCompletedOn(DateTime(2026, 8, 26)), isFalse);
    });

    test('completionDateIn returns the day actually recorded', () {
      // This is what lets the grid un-complete a weekly habit: it has to
      // remove Monday's entry, not add today's on top of it.
      final habit = _habit(
        frequency: HabitFrequency.weekly,
        completed: [DateTime(2026, 8, 31)],
      );

      expect(habit.completionDateIn(now), DateTime(2026, 8, 31));
      expect(habit.completionDateIn(DateTime(2026, 8, 20)), isNull);
    });

    test('recentHistory ends on the current period', () {
      final habit = _habit(completed: [
        DateTime(2026, 9, 2),
        DateTime(2026, 8, 31),
      ]);

      final history = habit.recentHistory(now, count: 4);

      // Oldest first: Aug 30, Aug 31, Sep 1, Sep 2.
      expect(history, [false, true, false, true]);
    });
  });

  group('summarizeHabits', () {
    final now = DateTime(2026, 9, 2, 9);

    test('counts completions, the best streak and running streaks', () {
      final summary = summarizeHabits([
        _habit(id: 'a', completed: [DateTime(2026, 9, 2)], streak: 5),
        _habit(id: 'b', streak: 0),
        _habit(id: 'c', completed: [DateTime(2026, 9, 2)], streak: 12),
      ], now);

      expect(summary.total, 3);
      expect(summary.completedThisPeriod, 2);
      expect(summary.bestStreak, 12);
      expect(summary.activeStreaks, 2);
      expect(summary.completionRate, closeTo(2 / 3, 1e-9));
    });

    test('an empty list has a zero rate rather than dividing by zero', () {
      final summary = summarizeHabits(const [], now);

      expect(summary.isEmpty, isTrue);
      expect(summary.completionRate, 0);
    });
  });

  group('sortHabits', () {
    final now = DateTime(2026, 9, 2, 9);

    test('outstanding first, then longest streak, then alphabetical', () {
      final sorted = sortHabits([
        _habit(id: 'done', title: 'Done one', completed: [DateTime(2026, 9, 2)]),
        _habit(id: 'b', title: 'Beta', streak: 1),
        _habit(id: 'a', title: 'Alpha', streak: 9),
        _habit(id: 'c', title: 'Alpha two', streak: 1),
      ], now);

      expect(sorted.map((h) => h.title), [
        'Alpha',
        'Alpha two',
        'Beta',
        'Done one',
      ]);
    });
  });
}
