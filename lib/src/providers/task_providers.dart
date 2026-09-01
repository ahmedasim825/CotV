import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../models/task.dart';
import '../repositories/task_repository.dart';
import '../storage/local_storage.dart';

final taskBoxProvider = Provider<Box<Task>>((ref) => Hive.box<Task>(HiveBoxes.tasks));

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  return HiveTaskRepository(ref.watch(taskBoxProvider));
});

/// The live task list plus CRUD actions. Every write goes through the
/// repository, which mutates the Hive box; the box's own change stream
/// (via [TaskRepository.watchAll]) flows straight back into this
/// provider's state, so the UI never needs manual invalidation.
class TaskListNotifier extends StreamNotifier<List<Task>> {
  TaskRepository get _repository => ref.read(taskRepositoryProvider);

  @override
  Stream<List<Task>> build() => _repository.watchAll();

  Future<void> addTask(Task task) => _repository.add(task);

  Future<void> updateTask(Task task) => _repository.update(task);

  Future<void> deleteTask(String id) => _repository.delete(id);

  Future<void> toggleCompleted(String id) => _repository.toggleCompleted(id);
}

final taskListProvider =
    StreamNotifierProvider<TaskListNotifier, List<Task>>(TaskListNotifier.new);
