import 'package:hive_ce/hive_ce.dart';

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
class Task {
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
  }) : createdAt = createdAt ?? DateTime.now();

  /// Stable unique identifier — the box key this task is stored under.
  @HiveField(0)
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
    );
  }
}
