import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../models/habit.dart';
import '../models/habit_view.dart';
import '../models/sync_stamped.dart';
import 'hive_repository_utils.dart';
import 'syncable_repository.dart';

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

class HiveHabitRepository
    implements HabitRepository, SyncableRepository<Habit> {
  HiveHabitRepository(this._box, [this._clock = systemSyncClock]);

  final Box<Habit> _box;
  final SyncClock _clock;

  @override
  Stream<List<Habit>> watchAll() => watchLiveBoxValues(_box);

  @override
  List<Habit> getAll() => liveValues(_box.values);

  @override
  Habit? getById(String id) {
    final habit = _box.get(id);
    return habit == null || habit.isDeleted ? null : habit;
  }

  @override
  Future<void> add(Habit habit) =>
      _box.put(habit.id, habit.stampUpdated(_clock()));

  @override
  Future<void> update(Habit habit) =>
      _box.put(habit.id, habit.stampUpdated(_clock()));

  /// Tombstones [id] rather than removing it — see [HiveTaskRepository.delete].
  @override
  Future<void> delete(String id) async {
    final habit = _box.get(id);
    if (habit == null) return;
    await _box.put(id, habit.markDeleted(_clock()));
  }

  @override
  Future<void> toggleCompletedOn(String id, DateTime date) async {
    final habit = getById(id);
    if (habit == null) {
      throw StateError('Habit "$id" not found.');
    }

    final normalizedDate = normalizeDay(date);
    final dates = habit.completedDates.map(normalizeDay).toSet();
    if (!dates.remove(normalizedDate)) {
      dates.add(normalizedDate);
    }

    final sortedDates = dates.toList()..sort();
    await _box.put(
      id,
      habit
          .copyWith(
            completedDates: sortedDates,
            streakCount: computeStreak(dates, habit.frequency, DateTime.now()),
          )
          .stampUpdated(_clock()),
    );
  }

  @override
  List<Habit> allIncludingDeleted() => _box.values.toList(growable: false);

  @override
  Future<void> applyRemote(Habit record) => _box.put(record.id, record);

  @override
  Future<void> markSynced(String id, int millis) async {
    final habit = _box.get(id);
    if (habit == null || habit.updatedAtMillis != millis) return;
    await _box.put(id, habit.markSynced(millis));
  }

  @override
  Future<int> purgeTombstonesBefore(int millis) async {
    final stale = _box.values
        .where((habit) =>
            habit.isDeleted &&
            !habit.isDirty &&
            (habit.updatedAtMillis ?? 0) < millis)
        .map((habit) => habit.id)
        .toList(growable: false);
    await _box.deleteAll(stale);
    return stale.length;
  }
}
