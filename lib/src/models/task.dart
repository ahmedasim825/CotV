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

  Task copyWith({
    String? title,
    String? description,
    DateTime? dueDate,
    bool clearDueDate = false,
    bool? isCompleted,
    String? category,
    TaskPriority? priority,
  }) {
    return Task(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      isCompleted: isCompleted ?? this.isCompleted,
      category: category ?? this.category,
      priority: priority ?? this.priority,
      createdAt: createdAt,
    );
  }
}
