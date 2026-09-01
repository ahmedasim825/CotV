import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../models/task.dart';
import 'hive_repository_utils.dart';

/// CRUD access to [Task]s.
abstract class TaskRepository {
  /// Emits the full task list immediately and again on every change.
  Stream<List<Task>> watchAll();

  List<Task> getAll();

  Task? getById(String id);

  Future<void> add(Task task);

  Future<void> update(Task task);

  Future<void> delete(String id);

  /// Flips [Task.isCompleted]. Throws [StateError] if [id] doesn't exist.
  Future<void> toggleCompleted(String id);
}

class HiveTaskRepository implements TaskRepository {
  HiveTaskRepository(this._box);

  final Box<Task> _box;

  @override
  Stream<List<Task>> watchAll() => watchBoxValues(_box);

  @override
  List<Task> getAll() => _box.values.toList(growable: false);

  @override
  Task? getById(String id) => _box.get(id);

  @override
  Future<void> add(Task task) => _box.put(task.id, task);

  @override
  Future<void> update(Task task) => _box.put(task.id, task);

  @override
  Future<void> delete(String id) => _box.delete(id);

  @override
  Future<void> toggleCompleted(String id) async {
    final task = _box.get(id);
    if (task == null) {
      throw StateError('Task "$id" not found.');
    }
    await _box.put(id, task.copyWith(isCompleted: !task.isCompleted));
  }
}
