// Exercises the tasks screen's own merge. The three things that matter, and
// each is a way this differs from `mergeAgenda` next door: undated tasks are
// kept, reminder completion survives, and priority comes through.

import 'package:flutter_test/flutter_test.dart';

import 'package:cotv/src/models/reminder.dart';
import 'package:cotv/src/models/task.dart';
import 'package:cotv/src/models/task_list_entry.dart';

Task _task(
  String id, {
  DateTime? due,
  DateTime? createdAt,
  bool completed = false,
  TaskPriority priority = TaskPriority.medium,
}) =>
    Task(
      id: id,
      title: id,
      dueDate: due,
      isCompleted: completed,
      priority: priority,
      createdAt: createdAt ?? DateTime(2026, 1, 1),
    );

Reminder _reminder(
  String id, {
  required DateTime dueAt,
  bool completed = false,
  TaskPriority priority = TaskPriority.medium,
}) =>
    Reminder(
      id: id,
      title: id,
      dueAt: dueAt,
      isCompleted: completed,
      priority: priority,
    );

List<String> _ids(List<TaskListEntry> entries) =>
    entries.map((e) => e.id).toList();

void main() {
  group('what mergeAgenda would have dropped', () {
    test('an undated task is kept, and bucketed by its creation date', () {
      final created = DateTime(2026, 3, 2, 9);
      final merged = mergeTaskList([_task('a', createdAt: created)], const []);

      expect(merged, hasLength(1));
      expect(merged.single.dueAt, isNull, reason: 'it genuinely has no due');
      expect(merged.single.bucketDate, created);
    });

    test('a completed reminder reports itself completed', () {
      final merged = mergeTaskList(
        const [],
        [_reminder('r', dueAt: DateTime(2026, 3, 2), completed: true)],
      );
      expect(merged.single.isCompleted, isTrue);
    });

    test('priority survives from both kinds', () {
      final merged = mergeTaskList(
        [_task('t', due: DateTime(2026, 3, 2), priority: TaskPriority.high)],
        [
          _reminder('r',
              dueAt: DateTime(2026, 3, 3), priority: TaskPriority.low),
        ],
      );
      expect(merged[0].priority, TaskPriority.high);
      expect(merged[1].priority, TaskPriority.low);
    });
  });

  group('identity', () {
    test('ids are prefixed so the two boxes cannot collide', () {
      final merged = mergeTaskList(
        [_task('x', due: DateTime(2026, 3, 2))],
        [_reminder('x', dueAt: DateTime(2026, 3, 3))],
      );
      expect(_ids(merged), ['task-x', 'reminder-x']);
      // The bare id is what the toggle and the edit sheet need back.
      expect(merged.map((e) => e.sourceId), ['x', 'x']);
    });

    test('kind is carried through', () {
      final merged = mergeTaskList(
        [_task('t', due: DateTime(2026, 3, 2))],
        [_reminder('r', dueAt: DateTime(2026, 3, 3))],
      );
      expect(merged.map((e) => e.kind),
          [TaskListKind.task, TaskListKind.reminder]);
    });
  });

  group('ordering', () {
    test('soonest first', () {
      final merged = mergeTaskList(
        [_task('late', due: DateTime(2026, 3, 5))],
        [_reminder('early', dueAt: DateTime(2026, 3, 1))],
      );
      expect(_ids(merged), ['reminder-early', 'task-late']);
    });

    test('a task wins a tie against the reminder about it', () {
      final at = DateTime(2026, 3, 2, 13);
      final merged =
          mergeTaskList([_task('t', due: at)], [_reminder('r', dueAt: at)]);
      expect(_ids(merged), ['task-t', 'reminder-r']);
    });

    test('the ordering is total, so it cannot reshuffle between rebuilds', () {
      final at = DateTime(2026, 3, 2, 13);
      final tasks = [_task('b', due: at), _task('a', due: at)];
      final first = _ids(mergeTaskList(tasks, const []));
      final second = _ids(mergeTaskList(tasks.reversed.toList(), const []));
      expect(first, second);
      expect(first, ['task-a', 'task-b'], reason: 'id breaks the last tie');
    });

    test('the result cannot be mutated by a caller', () {
      final merged = mergeTaskList([_task('a', due: DateTime(2026, 3, 2))],
          const []);
      expect(() => merged.add(merged.first), throwsUnsupportedError);
    });
  });

  group('isOverdue', () {
    final now = DateTime(2026, 3, 2, 12);

    test('a past due reads overdue', () {
      final merged =
          mergeTaskList(const [], [_reminder('r', dueAt: DateTime(2026, 3, 2, 11))]);
      expect(merged.single.isOverdue(now), isTrue);
    });

    test('a completed one never does', () {
      final merged = mergeTaskList(const [], [
        _reminder('r', dueAt: DateTime(2026, 3, 2, 11), completed: true),
      ]);
      expect(merged.single.isOverdue(now), isFalse);
    });

    test('landing on the instant is not late', () {
      final merged = mergeTaskList(const [], [_reminder('r', dueAt: now)]);
      expect(merged.single.isOverdue(now), isFalse);
    });

    test('an undated task is never overdue — it has no due to miss', () {
      final merged = mergeTaskList([_task('a')], const []);
      expect(merged.single.isOverdue(now), isFalse);
    });
  });
}
