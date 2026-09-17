import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../models/task.dart';
import '../models/sync_stamped.dart';
import 'hive_repository_utils.dart';
import 'syncable_repository.dart';

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

class HiveTaskRepository implements TaskRepository, SyncableRepository<Task> {
  HiveTaskRepository(this._box, [this._clock = systemSyncClock]);

  final Box<Task> _box;
  final SyncClock _clock;

  @override
  Stream<List<Task>> watchAll() => watchLiveBoxValues(_box);

  @override
  List<Task> getAll() => liveValues(_box.values);

  @override
  Task? getById(String id) {
    final task = _box.get(id);
    return task == null || task.isDeleted ? null : task;
  }

  @override
  Future<void> add(Task task) => _box.put(task.id, task.stampUpdated(_clock()));

  @override
  Future<void> update(Task task) =>
      _box.put(task.id, task.stampUpdated(_clock()));

  /// Tombstones [id] rather than removing it, so the deletion survives long
  /// enough to be pushed. Every read path filters it out from here on.
  @override
  Future<void> delete(String id) async {
    final task = _box.get(id);
    if (task == null) return;
    await _box.put(id, task.markDeleted(_clock()));
  }

  @override
  Future<void> toggleCompleted(String id) async {
    final task = getById(id);
    if (task == null) {
      throw StateError('Task "$id" not found.');
    }
    await _box.put(
      id,
      task.copyWith(isCompleted: !task.isCompleted).stampUpdated(_clock()),
    );
  }

  @override
  List<Task> allIncludingDeleted() => _box.values.toList(growable: false);

  @override
  Future<void> applyRemote(Task record) => _box.put(record.id, record);

  @override
  Future<void> markSynced(String id, int millis) async {
    final task = _box.get(id);
    if (task == null || task.updatedAtMillis != millis) return;
    await _box.put(id, task.markSynced(millis));
  }

  @override
  Future<int> purgeTombstonesBefore(int millis) async {
    final stale = _box.values
        .where((task) =>
            task.isDeleted &&
            !task.isDirty &&
            (task.updatedAtMillis ?? 0) < millis)
        .map((task) => task.id)
        .toList(growable: false);
    await _box.deleteAll(stale);
    return stale.length;
  }
}
