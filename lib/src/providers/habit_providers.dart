import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../models/habit.dart';
import '../repositories/habit_repository.dart';
import '../storage/local_storage.dart';

final habitBoxProvider = Provider<Box<Habit>>((ref) => Hive.box<Habit>(HiveBoxes.habits));

final habitRepositoryProvider = Provider<HabitRepository>((ref) {
  return HiveHabitRepository(ref.watch(habitBoxProvider));
});

class HabitListNotifier extends StreamNotifier<List<Habit>> {
  HabitRepository get _repository => ref.read(habitRepositoryProvider);

  @override
  Stream<List<Habit>> build() => _repository.watchAll();

  Future<void> addHabit(Habit habit) => _repository.add(habit);

  Future<void> updateHabit(Habit habit) => _repository.update(habit);

  Future<void> deleteHabit(String id) => _repository.delete(id);

  Future<void> toggleCompletedOn(String id, DateTime date) =>
      _repository.toggleCompletedOn(id, date);
}

final habitListProvider =
    StreamNotifierProvider<HabitListNotifier, List<Habit>>(HabitListNotifier.new);
