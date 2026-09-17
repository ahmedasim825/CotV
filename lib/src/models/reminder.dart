import 'package:hive_ce/hive_ce.dart';

import 'sync_stamped.dart';
import 'task.dart';

part 'reminder.g.dart';

/// A dated prompt, separate from a task.
///
/// A task is something to finish; a reminder is a moment to be told about.
/// They are kept apart rather than modelled as a task with a due date because
/// the two lists are shown side by side and sort on different things.
///
/// The two carry the same completion and priority now, and the tasks screen
/// renders both through one row widget — but the shapes still differ where it
/// counts. [dueAt] is required where `Task.dueDate` is nullable, and a
/// reminder has no description, category or notification flag, because none of
/// those have a meaning for a moment rather than a piece of work.
///
/// [TaskPriority] is reused rather than cloned: a second three-value enum
/// would need its own `typeId`, its own colour resolver and its own mapping to
/// the `priority` column, to describe exactly the same three steps.
@HiveType(typeId: 12)
class Reminder implements SyncStamped {
  const Reminder({
    required this.id,
    required this.title,
    required this.dueAt,
    this.isCompleted = false,
    this.priority = TaskPriority.medium,
    this.updatedAtMillis,
    this.isDeleted = false,
    this.syncedAtMillis,
  });

  /// Stable unique identifier — the box key this reminder is stored under.
  @HiveField(0)
  @override
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final DateTime dueAt;

  @HiveField(3)
  final bool isCompleted;

  @HiveField(4)
  final TaskPriority priority;

  /// See [SyncStamped]. Nullable and defaulted so rows written before these
  /// fields existed still read — the generated adapter only emits a null
  /// guard for parameters that are one or the other.
  @HiveField(5)
  @override
  final int? updatedAtMillis;

  @HiveField(6)
  @override
  final bool isDeleted;

  @HiveField(7)
  @override
  final int? syncedAtMillis;

  /// Strictly before [now]. A reminder landing on the current instant has
  /// not been missed.
  ///
  /// A completed reminder is never overdue: the moment has been dealt with,
  /// so the row has nothing left to warn about.
  bool isOverdue(DateTime now) => !isCompleted && dueAt.isBefore(now);

  /// [id] is never patched — a reminder keeps its identity for the life of
  /// the edit that produced it.
  Reminder copyWith({
    String? title,
    DateTime? dueAt,
    bool? isCompleted,
    TaskPriority? priority,
  }) =>
      Reminder(
        id: id,
        title: title ?? this.title,
        dueAt: dueAt ?? this.dueAt,
        isCompleted: isCompleted ?? this.isCompleted,
        priority: priority ?? this.priority,
        // Carried forward, and deliberately not exposed as parameters — see
        // the same note on `Task.copyWith`.
        updatedAtMillis: updatedAtMillis,
        isDeleted: isDeleted,
        syncedAtMillis: syncedAtMillis,
      );

  /// This reminder marked as changed at [millis]. Called by the repository on
  /// the way to the box, never by UI code.
  Reminder stampUpdated(int millis) => _sync(updatedAtMillis: millis);

  /// A tombstone: still in the box so the deletion can be pushed, filtered
  /// out of every read path.
  Reminder markDeleted(int millis) =>
      _sync(updatedAtMillis: millis, isDeleted: true);

  /// Records that the server has seen this record's current state.
  Reminder markSynced(int millis) => _sync(syncedAtMillis: millis);

  Reminder _sync({int? updatedAtMillis, bool? isDeleted, int? syncedAtMillis}) =>
      Reminder(
        id: id,
        title: title,
        dueAt: dueAt,
        isCompleted: isCompleted,
        priority: priority,
        updatedAtMillis: updatedAtMillis ?? this.updatedAtMillis,
        isDeleted: isDeleted ?? this.isDeleted,
        syncedAtMillis: syncedAtMillis ?? this.syncedAtMillis,
      );
}
