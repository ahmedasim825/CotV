import 'package:hive_ce/hive_ce.dart';

import 'sync_stamped.dart';

part 'task.g.dart';

/// Relative urgency of a [Task], surfaced in sorting and UI emphasis.
@HiveType(typeId: 1)
enum TaskPriority {
  @HiveField(0)
  low,
  @HiveField(1)
  medium,
  @HiveField(2)
  high,
}

/// A single to-do item.
@HiveType(typeId: 0)
class Task implements SyncStamped {
  Task({
    required this.id,
    required this.title,
    this.description = '',
    this.dueDate,
    this.isCompleted = false,
    this.category = 'General',
    this.priority = TaskPriority.medium,
    DateTime? createdAt,
    this.hasReminder = false,
    this.updatedAtMillis,
    this.isDeleted = false,
    this.syncedAtMillis,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Stable unique identifier — the box key this task is stored under.
  @HiveField(0)
  @override
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String description;

  @HiveField(3)
  final DateTime? dueDate;

  @HiveField(4)
  final bool isCompleted;

  /// Free-form user-defined grouping (e.g. "Work", "Personal", "Prayer").
  @HiveField(5)
  final String category;

  @HiveField(6)
  final TaskPriority priority;

  @HiveField(7)
  final DateTime createdAt;

  /// Whether a local notification should fire at [dueDate].
  ///
  /// Only meaningful alongside a non-null [dueDate] — there is nothing to
  /// schedule against otherwise, so [copyWith] forces this false whenever
  /// the due date is cleared.
  @HiveField(8)
  final bool hasReminder;

  /// See [SyncStamped]. Nullable and defaulted so rows written before these
  /// fields existed still read — the generated adapter only emits a null
  /// guard for parameters that are one or the other.
  @HiveField(9)
  @override
  final int? updatedAtMillis;

  @HiveField(10)
  @override
  final bool isDeleted;

  @HiveField(11)
  @override
  final int? syncedAtMillis;

  /// True when this task should currently hold a scheduled notification.
  bool get wantsReminder => hasReminder && dueDate != null && !isCompleted;

  Task copyWith({
    String? title,
    String? description,
    DateTime? dueDate,
    bool clearDueDate = false,
    bool? isCompleted,
    String? category,
    TaskPriority? priority,
    bool? hasReminder,
  }) {
    final nextDueDate = clearDueDate ? null : (dueDate ?? this.dueDate);
    return Task(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      dueDate: nextDueDate,
      isCompleted: isCompleted ?? this.isCompleted,
      category: category ?? this.category,
      priority: priority ?? this.priority,
      createdAt: createdAt,
      hasReminder:
          nextDueDate == null ? false : (hasReminder ?? this.hasReminder),
      // Carried forward, and deliberately not exposed as parameters. An
      // edit made through here is stamped by the repository that persists
      // it, so no widget can set a sync timestamp — and dropping them here
      // would silently un-migrate the row on every edit.
      updatedAtMillis: updatedAtMillis,
      isDeleted: isDeleted,
      syncedAtMillis: syncedAtMillis,
    );
  }

  /// This task marked as changed at [millis]. Called by the repository on
  /// the way to the box, never by UI code.
  Task stampUpdated(int millis) => _sync(updatedAtMillis: millis);

  /// A tombstone: still in the box so the deletion can be pushed, filtered
  /// out of every read path.
  Task markDeleted(int millis) =>
      _sync(updatedAtMillis: millis, isDeleted: true);

  /// Records that the server has seen this record's current state.
  Task markSynced(int millis) => _sync(syncedAtMillis: millis);

  Task _sync({int? updatedAtMillis, bool? isDeleted, int? syncedAtMillis}) =>
      Task(
        id: id,
        title: title,
        description: description,
        dueDate: dueDate,
        isCompleted: isCompleted,
        category: category,
        priority: priority,
        createdAt: createdAt,
        hasReminder: hasReminder,
        updatedAtMillis: updatedAtMillis ?? this.updatedAtMillis,
        isDeleted: isDeleted ?? this.isDeleted,
        syncedAtMillis: syncedAtMillis ?? this.syncedAtMillis,
      );
}
