// Exercises the task list's filter/sort transform. The invariant that
// matters most: no incomplete task may be invisible under every tab.

import 'package:flutter_test/flutter_test.dart';

import 'package:cotv/src/models/task.dart';
import 'package:cotv/src/models/task_view.dart';

final _now = DateTime(2026, 9, 1, 12, 0);

Task _task(
  String id, {
  DateTime? due,
  bool completed = false,
  TaskPriority priority = TaskPriority.medium,
  DateTime? createdAt,
}) {
  return Task(
    id: id,
    title: id,
    dueDate: due,
    isCompleted: completed,
    priority: priority,
    createdAt: createdAt ?? DateTime(2026, 1, 1),
  );
}

List<String> _ids(List<Task> tasks) => tasks.map((t) => t.id).toList();

void main() {
  group('filterTasks', () {
    test('Today holds tasks due later today', () {
      final task = _task('a', due: DateTime(2026, 9, 1, 18));
      expect(_ids(filterTasks([task], TaskFilter.today, _now)), ['a']);
    });

    test('Today keeps overdue tasks rather than dropping them', () {
      final overdue = _task('a', due: DateTime(2026, 8, 28, 9));
      expect(_ids(filterTasks([overdue], TaskFilter.today, _now)), ['a']);
    });

    test('Today excludes completed tasks', () {
      final done = _task('a', due: DateTime(2026, 9, 1, 18), completed: true);
      expect(filterTasks([done], TaskFilter.today, _now), isEmpty);
    });

    test('Upcoming holds tasks due after today', () {
      final later = _task('a', due: DateTime(2026, 9, 3, 9));
      expect(_ids(filterTasks([later], TaskFilter.upcoming, _now)), ['a']);
    });

    test('Upcoming catches undated tasks so they are never orphaned', () {
      final undated = _task('a');
      expect(_ids(filterTasks([undated], TaskFilter.upcoming, _now)), ['a']);
    });

    test('a task due at 23:59 today is Today, not Upcoming', () {
      final tonight = _task('a', due: DateTime(2026, 9, 1, 23, 59));
      expect(_ids(filterTasks([tonight], TaskFilter.today, _now)), ['a']);
      expect(filterTasks([tonight], TaskFilter.upcoming, _now), isEmpty);
    });

    test('Completed holds only completed tasks', () {
      final tasks = [_task('a', completed: true), _task('b')];
      expect(_ids(filterTasks(tasks, TaskFilter.completed, _now)), ['a']);
    });

    test('Priority holds only outstanding high-priority tasks', () {
      final tasks = [
        _task('high', priority: TaskPriority.high),
        _task('med', priority: TaskPriority.medium),
        _task('done', priority: TaskPriority.high, completed: true),
      ];
      expect(_ids(filterTasks(tasks, TaskFilter.priority, _now)), ['high']);
    });

    test('every incomplete task appears under at least one filter', () {
      final tasks = [
        _task('overdue', due: DateTime(2026, 8, 1)),
        _task('today', due: DateTime(2026, 9, 1, 20)),
        _task('later', due: DateTime(2026, 12, 1)),
        _task('undated'),
      ];

      final covered = <String>{
        for (final filter in TaskFilter.values)
          ..._ids(filterTasks(tasks, filter, _now)),
      };

      expect(covered, containsAll(['overdue', 'today', 'later', 'undated']));
    });
  });

  group('sortTasks', () {
    test('priority sort runs high, medium, low', () {
      final tasks = [
        _task('low', priority: TaskPriority.low),
        _task('high', priority: TaskPriority.high),
        _task('med', priority: TaskPriority.medium),
      ];
      expect(_ids(sortTasks(tasks, TaskSort.priority)), ['high', 'med', 'low']);
    });

    test('priority ties fall back to the earlier due date', () {
      final tasks = [
        _task('later', priority: TaskPriority.high, due: DateTime(2026, 9, 5)),
        _task('sooner', priority: TaskPriority.high, due: DateTime(2026, 9, 2)),
      ];
      expect(_ids(sortTasks(tasks, TaskSort.priority)), ['sooner', 'later']);
    });

    test('due-time sort runs earliest first', () {
      final tasks = [
        _task('b', due: DateTime(2026, 9, 4)),
        _task('a', due: DateTime(2026, 9, 2)),
      ];
      expect(_ids(sortTasks(tasks, TaskSort.dueTime)), ['a', 'b']);
    });

    test('undated tasks sink below dated ones under either sort', () {
      final tasks = [
        _task('undated'),
        _task('dated', due: DateTime(2026, 9, 4)),
      ];
      expect(_ids(sortTasks(tasks, TaskSort.dueTime)), ['dated', 'undated']);
      expect(_ids(sortTasks(tasks, TaskSort.priority)), ['dated', 'undated']);
    });

    test('fully tied tasks keep a stable, creation-ordered result', () {
      final tasks = [
        _task('second', createdAt: DateTime(2026, 2, 1)),
        _task('first', createdAt: DateTime(2026, 1, 1)),
      ];
      expect(_ids(sortTasks(tasks, TaskSort.priority)), ['first', 'second']);
    });

    test('sorting does not mutate the input list', () {
      final tasks = [
        _task('low', priority: TaskPriority.low),
        _task('high', priority: TaskPriority.high),
      ];
      sortTasks(tasks, TaskSort.priority);
      expect(_ids(tasks), ['low', 'high']);
    });
  });

  group('Task.copyWith', () {
    test('clearing the due date also clears the reminder', () {
      final task = Task(
        id: 'a',
        title: 'a',
        dueDate: DateTime(2026, 9, 2),
        hasReminder: true,
      );
      final cleared = task.copyWith(clearDueDate: true);

      expect(cleared.dueDate, isNull);
      expect(cleared.hasReminder, isFalse);
    });

    test('a reminder needs a due date and an incomplete task', () {
      final due = DateTime(2026, 9, 2);
      expect(
        Task(id: 'a', title: 'a', dueDate: due, hasReminder: true).wantsReminder,
        isTrue,
      );
      expect(
        Task(id: 'b', title: 'b', hasReminder: true).wantsReminder,
        isFalse,
      );
      expect(
        Task(
          id: 'c',
          title: 'c',
          dueDate: due,
          hasReminder: true,
          isCompleted: true,
        ).wantsReminder,
        isFalse,
      );
    });
  });
}
