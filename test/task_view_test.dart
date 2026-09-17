// Exercises what survives of the task list's view transform: the dashboard's
// today shortlist, and the ordering the tasks screen groups by.
//
// The four filter tabs went with the redesign, and the invariant they carried
// — no incomplete task invisible under every tab — went with them. The screen
// groups by day now and deliberately shows neither future-dated nor undated
// tasks; `day_groups_test.dart` is where that rule is pinned.

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
  group('todayTasks', () {
    test('holds tasks due later today', () {
      final task = _task('a', due: DateTime(2026, 9, 1, 18));
      expect(_ids(todayTasks([task], _now)), ['a']);
    });

    test('keeps overdue tasks rather than dropping them', () {
      final overdue = _task('a', due: DateTime(2026, 8, 28, 9));
      expect(_ids(todayTasks([overdue], _now)), ['a']);
    });

    test('excludes completed tasks', () {
      final done = _task('a', due: DateTime(2026, 9, 1, 18), completed: true);
      expect(todayTasks([done], _now), isEmpty);
    });

    test('excludes tasks due after today', () {
      final later = _task('a', due: DateTime(2026, 9, 3, 9));
      expect(todayTasks([later], _now), isEmpty);
    });

    test('excludes undated tasks — there is no due date to be due today', () {
      expect(todayTasks([_task('a')], _now), isEmpty);
    });

    test('a task due at 23:59 today still counts as today', () {
      final tonight = _task('a', due: DateTime(2026, 9, 1, 23, 59));
      expect(_ids(todayTasks([tonight], _now)), ['a']);
    });

    test('midnight tomorrow does not', () {
      final tomorrow = _task('a', due: DateTime(2026, 9, 2));
      expect(todayTasks([tomorrow], _now), isEmpty);
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
