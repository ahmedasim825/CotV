import 'package:hive_ce/hive_ce.dart';

import 'sync_stamped.dart';

part 'task.g.dart';

/// Relative urgency of a [Task], surfaced in sorting and UI emphasis.
///
/// [none] is declared first because the picker lists it first, and its
/// `@HiveField` is 3 because 0-2 were already spent: the adapter writes the
/// annotation, not the declaration index, so rows written before this value
/// existed still read back as the priority they were saved with.
@HiveType(typeId: 1)
enum TaskPriority {
  @HiveField(3)
  none,
  @HiveField(0)
  low,
  @HiveField(1)
  medium,
  @HiveField(2)
  high,
}

/// How often a [Task] comes back.
///
/// Stored, and nothing acts on it yet. A task that regenerates needs somewhere
/// to decide *when* the next one is written and something to stop a missed
/// week piling up six copies on the day the app next opens — that is a feature
/// of its own, and half of it would be worse than none. Until it lands this
/// records what the user asked for so the answer is not lost.
@HiveType(typeId: 2)
enum TaskRepeat {
  @HiveField(0)
  never,
  @HiveField(1)
  hourly,
  @HiveField(2)
  daily,
  @HiveField(3)
  weekdays,
  @HiveField(4)
  weekends,
  @HiveField(5)
  weekly,
  @HiveField(6)
  biweekly,
  @HiveField(7)
  monthly,
  @HiveField(8)
  everyThreeMonths,
  @HiveField(9)
  everySixMonths,
  @HiveField(10)
  yearly,
}

/// How far ahead of its due moment a [Task] gives warning.
///
/// A second notification, not a replacement: the one at the due moment still
/// fires. See `TaskReminderController.sync`.
@HiveType(typeId: 3)
enum TaskEarlyReminder {
  @HiveField(0)
  never,
  @HiveField(1)
  oneDay,
  @HiveField(2)
  twoDays,
  @HiveField(3)
  oneWeek,
  @HiveField(4)
  twoWeeks,
  @HiveField(5)
  oneMonth,
  @HiveField(6)
  threeMonths,
  @HiveField(7)
  sixMonths,
}

extension TaskEarlyReminderX on TaskEarlyReminder {
  /// The moment this reminder should fire for a task due at [due], or null
  /// when there is nothing to fire.
  ///
  /// Counted off the due date rather than subtracted as a fixed [Duration], so
  /// "1 month before" a task due on the 31st of March is the 28th of February
  /// and not the 1st of March.
  DateTime? leadFrom(DateTime due) {
    switch (this) {
      case TaskEarlyReminder.never:
        return null;
      case TaskEarlyReminder.oneDay:
        return due.subtract(const Duration(days: 1));
      case TaskEarlyReminder.twoDays:
        return due.subtract(const Duration(days: 2));
      case TaskEarlyReminder.oneWeek:
        return due.subtract(const Duration(days: 7));
      case TaskEarlyReminder.twoWeeks:
        return due.subtract(const Duration(days: 14));
      case TaskEarlyReminder.oneMonth:
        return _monthsBefore(due, 1);
      case TaskEarlyReminder.threeMonths:
        return _monthsBefore(due, 3);
      case TaskEarlyReminder.sixMonths:
        return _monthsBefore(due, 6);
    }
  }

  /// [due] moved back [months] calendar months, clamped to the length of the
  /// month it lands in. [DateTime] would roll the 31st of a 30-day month into
  /// the 1st of the next, which reads as a day late rather than a month early.
  static DateTime _monthsBefore(DateTime due, int months) {
    final target = DateTime(due.year, due.month - months);
    final lastDay = DateTime(target.year, target.month + 1, 0).day;
    return DateTime(
      target.year,
      target.month,
      due.day < lastDay ? due.day : lastDay,
      due.hour,
      due.minute,
    );
  }
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
    this.priority = TaskPriority.none,
    DateTime? createdAt,
    this.hasReminder = false,
    this.isStudy = false,
    this.subjectId,
    this.repeat = TaskRepeat.never,
    this.earlyReminder = TaskEarlyReminder.never,
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

  /// Whether this task is study work, which is what puts a [subjectId] on it.
  @HiveField(12)
  final bool isStudy;

  /// The `Subject` this task belongs to, by id.
  ///
  /// A plain id rather than a relation: subjects are tombstoned rather than
  /// removed, but they can still be deleted, and a task should outlive the
  /// subject it was filed under rather than block its removal. Every read
  /// resolves it against the live list and falls back to unfiled.
  @HiveField(13)
  final String? subjectId;

  @HiveField(14)
  final TaskRepeat repeat;

  @HiveField(15)
  final TaskEarlyReminder earlyReminder;

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
    bool? isStudy,
    String? subjectId,
    bool clearSubject = false,
    TaskRepeat? repeat,
    TaskEarlyReminder? earlyReminder,
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
      hasReminder: nextDueDate == null
          ? false
          : (hasReminder ?? this.hasReminder),
      isStudy: isStudy ?? this.isStudy,
      // Cleared with the flag rather than by passing null, which
      // `??` cannot tell from "leave it alone" -- the same shape
      // `clearDueDate` uses just above.
      subjectId: clearSubject ? null : (subjectId ?? this.subjectId),
      repeat: repeat ?? this.repeat,
      earlyReminder: earlyReminder ?? this.earlyReminder,
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
        isStudy: isStudy,
        subjectId: subjectId,
        repeat: repeat,
        earlyReminder: earlyReminder,
        updatedAtMillis: updatedAtMillis ?? this.updatedAtMillis,
        isDeleted: isDeleted ?? this.isDeleted,
        syncedAtMillis: syncedAtMillis ?? this.syncedAtMillis,
      );
}
