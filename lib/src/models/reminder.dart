import 'package:flutter/foundation.dart';

/// A dated prompt, separate from a task.
///
/// A task is something to finish; a reminder is a moment to be told about.
/// They are kept apart rather than modelled as a task with a due date because
/// the two lists are shown side by side and sort on different things.
@immutable
class Reminder {
  const Reminder({
    required this.id,
    required this.title,
    required this.dueAt,
  });

  final String id;
  final String title;
  final DateTime dueAt;

  /// Strictly before [now]. A reminder landing on the current instant has
  /// not been missed.
  bool isOverdue(DateTime now) => dueAt.isBefore(now);

  /// [id] is never patched — a reminder keeps its identity for the life of
  /// the edit that produced it.
  Reminder copyWith({String? title, DateTime? dueAt}) => Reminder(
        id: id,
        title: title ?? this.title,
        dueAt: dueAt ?? this.dueAt,
      );
}
