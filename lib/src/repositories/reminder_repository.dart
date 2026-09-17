import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../models/reminder.dart';
import '../models/sync_stamped.dart';
import 'hive_repository_utils.dart';
import 'syncable_repository.dart';

/// CRUD access to [Reminder]s. Deliberately the same shape as
/// `TaskRepository` — the two lists sit on one screen and are mutated by the
/// same row widget, so a reminder that had to be toggled through a different
/// verb would be a seam with nothing behind it.
abstract class ReminderRepository {
  /// Emits the full reminder list immediately and again on every change.
  Stream<List<Reminder>> watchAll();

  List<Reminder> getAll();

  Reminder? getById(String id);

  Future<void> add(Reminder reminder);

  Future<void> update(Reminder reminder);

  Future<void> delete(String id);

  /// Flips [Reminder.isCompleted]. Throws [StateError] if [id] doesn't exist.
  Future<void> toggleCompleted(String id);
}

class HiveReminderRepository
    implements ReminderRepository, SyncableRepository<Reminder> {
  HiveReminderRepository(this._box, [this._clock = systemSyncClock]);

  final Box<Reminder> _box;
  final SyncClock _clock;

  @override
  Stream<List<Reminder>> watchAll() => watchLiveBoxValues(_box);

  @override
  List<Reminder> getAll() => liveValues(_box.values);

  @override
  Reminder? getById(String id) {
    final reminder = _box.get(id);
    return reminder == null || reminder.isDeleted ? null : reminder;
  }

  @override
  Future<void> add(Reminder reminder) =>
      _box.put(reminder.id, reminder.stampUpdated(_clock()));

  @override
  Future<void> update(Reminder reminder) =>
      _box.put(reminder.id, reminder.stampUpdated(_clock()));

  /// Tombstones [id] rather than removing it, so the deletion survives long
  /// enough to be pushed. Every read path filters it out from here on.
  @override
  Future<void> delete(String id) async {
    final reminder = _box.get(id);
    if (reminder == null) return;
    await _box.put(id, reminder.markDeleted(_clock()));
  }

  @override
  Future<void> toggleCompleted(String id) async {
    final reminder = getById(id);
    if (reminder == null) {
      throw StateError('Reminder "$id" not found.');
    }
    await _box.put(
      id,
      reminder
          .copyWith(isCompleted: !reminder.isCompleted)
          .stampUpdated(_clock()),
    );
  }

  @override
  List<Reminder> allIncludingDeleted() => _box.values.toList(growable: false);

  @override
  Future<void> applyRemote(Reminder record) => _box.put(record.id, record);

  @override
  Future<void> markSynced(String id, int millis) async {
    final reminder = _box.get(id);
    if (reminder == null || reminder.updatedAtMillis != millis) return;
    await _box.put(id, reminder.markSynced(millis));
  }

  @override
  Future<int> purgeTombstonesBefore(int millis) async {
    final stale = _box.values
        .where((reminder) =>
            reminder.isDeleted &&
            !reminder.isDirty &&
            (reminder.updatedAtMillis ?? 0) < millis)
        .map((reminder) => reminder.id)
        .toList(growable: false);
    await _box.deleteAll(stale);
    return stale.length;
  }
}
