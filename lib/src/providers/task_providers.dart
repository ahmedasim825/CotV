import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../models/task.dart';
import '../repositories/task_repository.dart';
import '../storage/local_storage.dart';
import 'task_reminder_providers.dart';

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

  TaskReminderController get _reminders =>
      ref.read(taskReminderControllerProvider);

  @override
  Stream<List<Task>> build() => _repository.watchAll();

  /// Persists first, then reconciles the reminder — the task is the source
  /// of truth, and a refused notification permission must never block the
  /// write.
  Future<void> addTask(Task task) async {
    await _repository.add(task);
    await _reminders.sync(task);
  }

  Future<void> updateTask(Task task) async {
    await _repository.update(task);
    await _reminders.sync(task);
  }

  Future<void> deleteTask(String id) async {
    await _repository.delete(id);
    await _reminders.cancel(id);
  }

  /// Flips completion and drops the reminder when a task is checked off, so
  /// a finished task can't still buzz at its due time.
  Future<void> toggleCompleted(String id) async {
    await _repository.toggleCompleted(id);
    final updated = _repository.getById(id);
    if (updated != null) await _reminders.sync(updated);
  }
}

final taskListProvider =
    StreamNotifierProvider<TaskListNotifier, List<Task>>(TaskListNotifier.new);
