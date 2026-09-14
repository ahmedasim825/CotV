// Exercises the merge behind the iOS dashboard's one Tasks / Reminders card.
// The invariant that matters most: the ordering is total, because the card
// draws no headings and a row that moved for an invisible reason reads as a
// bug.

import 'package:flutter_test/flutter_test.dart';

import 'package:cotv/src/models/agenda_view.dart';
import 'package:cotv/src/models/reminder.dart';
import 'package:cotv/src/models/task.dart';

Task _task(String id, {DateTime? due, bool completed = false}) => Task(
      id: id,
      title: id,
      dueDate: due,
      isCompleted: completed,
      createdAt: DateTime(2026, 1, 1),
    );

Reminder _reminder(String id, DateTime due) =>
    Reminder(id: id, title: id, dueAt: due);

List<String> _ids(List<AgendaEntry> entries) =>
    entries.map((e) => e.id).toList();

void main() {
  group('mergeAgenda', () {
    test('interleaves both kinds by due time', () {
      final entries = mergeAgenda(
        [
          _task('a', due: DateTime(2026, 3, 17, 9)),
          _task('b', due: DateTime(2026, 3, 17, 17)),
        ],
        [
          _reminder('x', DateTime(2026, 3, 17, 13)),
        ],
      );

      expect(_ids(entries), ['task-a', 'reminder-x', 'task-b']);
    });

    test('a task outranks a reminder due at the same instant', () {
      final at = DateTime(2026, 3, 17, 13);
      final entries = mergeAgenda([_task('a', due: at)], [_reminder('x', at)]);

      expect(_ids(entries), ['task-a', 'reminder-x']);
    });

    test('the ordering is total, so input order cannot change output', () {
      final at = DateTime(2026, 3, 17, 13);
      final tasks = [
        _task('c', due: at),
        _task('a', due: at),
        _task('b', due: at),
      ];

      final forwards = _ids(mergeAgenda(tasks, const []));
      final backwards = _ids(mergeAgenda(tasks.reversed.toList(), const []));

      expect(forwards, ['task-a', 'task-b', 'task-c']);
      expect(backwards, forwards);
    });

    test('an undated task is dropped rather than given a position', () {
      final entries = mergeAgenda(
        [_task('a'), _task('b', due: DateTime(2026, 3, 17, 9))],
        const [],
      );

      expect(_ids(entries), ['task-b']);
    });

    test('ids are prefixed, so the two boxes cannot collide on one', () {
      final at = DateTime(2026, 3, 17, 13);
      final entries = mergeAgenda([_task('same', due: at)], [
        _reminder('same', at),
      ]);

      expect(_ids(entries), ['task-same', 'reminder-same']);
      expect(entries.map((e) => e.sourceId), ['same', 'same']);
    });

    test('a completed task carries its tick; a reminder never does', () {
      final at = DateTime(2026, 3, 17, 13);
      final entries = mergeAgenda(
        [_task('a', due: at, completed: true)],
        [_reminder('x', at)],
      );

      expect(entries[0].isCompleted, isTrue);
      expect(entries[1].isCompleted, isFalse);
    });

    test('isOverdue matches Reminder.isOverdue at the boundary instant', () {
      final at = DateTime(2026, 3, 17, 13);
      final entry = mergeAgenda(const [], [_reminder('x', at)]).single;

      expect(entry.isOverdue(at), isFalse);
      expect(entry.isOverdue(at.add(const Duration(minutes: 1))), isTrue);
    });

    test('the result cannot be mutated by a caller', () {
      final entries = mergeAgenda(
        [_task('a', due: DateTime(2026, 3, 17, 9))],
        const [],
      );

      expect(() => entries.add(entries.first), throwsUnsupportedError);
    });
  });
}
