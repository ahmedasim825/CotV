import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../models/habit.dart';
import 'hive_repository_utils.dart';

/// CRUD access to [Habit]s, plus completion toggling that keeps
/// [Habit.streakCount] correct.
abstract class HabitRepository {
  Stream<List<Habit>> watchAll();

  List<Habit> getAll();

  Habit? getById(String id);

  Future<void> add(Habit habit);

  Future<void> update(Habit habit);

  Future<void> delete(String id);

  /// Adds or removes [date] from [Habit.completedDates] (toggle) and
  /// recomputes [Habit.streakCount] to match. Throws [StateError] if [id]
  /// doesn't exist.
  Future<void> toggleCompletedOn(String id, DateTime date);
}

class HiveHabitRepository implements HabitRepository {
  HiveHabitRepository(this._box);

  final Box<Habit> _box;

  @override
  Stream<List<Habit>> watchAll() => watchBoxValues(_box);

  @override
  List<Habit> getAll() => _box.values.toList(growable: false);

  @override
  Habit? getById(String id) => _box.get(id);

  @override
  Future<void> add(Habit habit) => _box.put(habit.id, habit);

  @override
  Future<void> update(Habit habit) => _box.put(habit.id, habit);

  @override
  Future<void> delete(String id) => _box.delete(id);

  @override
  Future<void> toggleCompletedOn(String id, DateTime date) async {
    final habit = _box.get(id);
    if (habit == null) {
      throw StateError('Habit "$id" not found.');
    }

    final normalizedDate = _normalizeDate(date);
    final dates = habit.completedDates.map(_normalizeDate).toSet();
    if (!dates.remove(normalizedDate)) {
      dates.add(normalizedDate);
    }

    final sortedDates = dates.toList()..sort();
    await _box.put(
      id,
      habit.copyWith(
        completedDates: sortedDates,
        streakCount: _computeStreak(dates, habit.frequency),
      ),
    );
  }
}

DateTime _normalizeDate(DateTime date) => DateTime(date.year, date.month, date.day);

/// Consecutive-period streak ending at "now", counting backward.
///
/// A grace period of one period is allowed: for a daily habit, the streak
/// still counts as active if yesterday (not just today) was completed, so
/// a user isn't shown a broken streak before they've had a chance to
/// complete today's instance. Same idea for weekly habits, one week back.
int _computeStreak(Set<DateTime> normalizedDates, HabitFrequency frequency) {
  if (normalizedDates.isEmpty) return 0;

  final step = frequency == HabitFrequency.daily
      ? const Duration(days: 1)
      : const Duration(days: 7);

  final periods = frequency == HabitFrequency.daily
      ? normalizedDates
      : normalizedDates.map(_weekStart).toSet();

  final currentPeriod = frequency == HabitFrequency.daily
      ? _normalizeDate(DateTime.now())
      : _weekStart(DateTime.now());

  var cursor =
      periods.contains(currentPeriod) ? currentPeriod : currentPeriod.subtract(step);
  if (!periods.contains(cursor)) return 0;

  var streak = 0;
  while (periods.contains(cursor)) {
    streak++;
    cursor = cursor.subtract(step);
  }
  return streak;
}

/// Monday-start week bucket for [date].
DateTime _weekStart(DateTime date) {
  final normalized = _normalizeDate(date);
  return normalized.subtract(Duration(days: normalized.weekday - 1));
}
