// Row mapping for MiloSyncService, driven with fixture maps.
//
// No client and no network: every function under test is pure, and the
// shapes below are what PostgREST actually sends — numerics as JSON
// numbers, timestamptz as ISO-8601 strings, date[] as a list of plain
// calendar dates.

import 'package:flutter_test/flutter_test.dart';

import 'package:cotv/src/models/reminder.dart';
import 'package:cotv/src/models/study_log.dart';
import 'package:cotv/src/models/subject.dart';
import 'package:cotv/src/models/sync_stamped.dart';
import 'package:cotv/src/models/task.dart';
import 'package:cotv/src/services/milo_sync_service.dart';

void main() {
  group('enum names are the wire format', () {
    // The columns store the enum *name*, so reordering either enum must not
    // repoint existing rows. If one of these lists changes, the Postgres
    // column's contents change meaning and the migration needs a data fix.
    test('task priority', () {
      expect(TaskPriority.values.map((p) => p.name).toList(),
          ['low', 'medium', 'high']);
    });


    test('an unknown value from a newer build falls back rather than throws',
        () {
      final row = _taskRow({'priority': 'catastrophic'});
      expect(taskFromRow(row).priority, TaskPriority.medium);
    });
  });

  group('tasks', () {
    test('round-trips through a row', () {
      final task = Task(
        id: 't1',
        title: 'Read chapter 4',
        description: 'Cardiovascular',
        dueDate: DateTime(2026, 9, 18, 14, 30),
        isCompleted: true,
        category: 'Study',
        priority: TaskPriority.high,
        createdAt: DateTime(2026, 9, 1, 8),
        hasReminder: true,
      ).stampUpdated(1700);

      final back = taskFromRow(_asServerRow(taskToRow(task)));

      expect(back.id, 't1');
      expect(back.title, 'Read chapter 4');
      expect(back.description, 'Cardiovascular');
      expect(back.dueDate, DateTime(2026, 9, 18, 14, 30));
      expect(back.isCompleted, isTrue);
      expect(back.category, 'Study');
      expect(back.priority, TaskPriority.high);
      expect(back.createdAt, DateTime(2026, 9, 1, 8));
      expect(back.hasReminder, isTrue);
      expect(back.updatedAtMillis, 1700);
    });

    test('a pulled record reads as clean', () {
      final back = taskFromRow(_taskRow());
      // Not dirty: a pulled record stamped as a local edit would be pushed
      // straight back, and the two devices would trade it forever.
      expect(back.isDirty, isFalse);
      expect(back.syncedAtMillis, back.updatedAtMillis);
    });

    test('the deleted column becomes a tombstone', () {
      expect(taskFromRow(_taskRow({'deleted': true})).isDeleted, isTrue);
      final row = taskToRow(Task(id: 't1', title: 'Gone').markDeleted(90));
      expect(row['deleted'], isTrue);
      expect(row['client_updated_at'], 90);
    });

    test('an unstamped record still pushes with a usable clock', () {
      // Belt and braces over the migration: a stamp of null would sort as
      // older than everything and lose to any remote row.
      final row = taskToRow(Task(id: 't1', title: 'Unstamped'));
      expect(row['client_updated_at'], isA<int>());
      expect(row['client_updated_at'], greaterThan(0));
    });

    test('a null due date survives both directions', () {
      final row = taskToRow(Task(id: 't1', title: 'Someday').stampUpdated(1));
      expect(row['due_date'], isNull);
      expect(taskFromRow(_asServerRow(row)).dueDate, isNull);
    });
  });

  group('reminders', () {
    test('round-trips through a row', () {
      final reminder = Reminder(
        id: 'r1',
        title: 'Watch the lecture',
        dueAt: DateTime(2026, 9, 17, 18, 0),
        isCompleted: true,
        priority: TaskPriority.high,
      ).stampUpdated(1700);

      final back = reminderFromRow(_asServerRow(reminderToRow(reminder)));

      expect(back.id, 'r1');
      expect(back.title, 'Watch the lecture');
      expect(back.dueAt, DateTime(2026, 9, 17, 18, 0));
      expect(back.isCompleted, isTrue);
      expect(back.priority, TaskPriority.high);
      expect(back.updatedAtMillis, 1700);
    });

    test('priority travels as the enum name, same as a task', () {
      final row = reminderToRow(
        Reminder(id: 'r1', title: 'x', dueAt: DateTime(2026, 9, 17))
            .stampUpdated(1),
      );
      expect(row['priority'], 'medium');
    });

    test('a pulled record reads as clean', () {
      final row = reminderToRow(
        Reminder(id: 'r1', title: 'x', dueAt: DateTime(2026, 9, 17))
            .stampUpdated(1),
      );
      final back = reminderFromRow(_asServerRow(row));
      // Not dirty: a pulled record stamped as a local edit would be pushed
      // straight back, and the two devices would trade it forever.
      expect(back.isDirty, isFalse);
      expect(back.syncedAtMillis, back.updatedAtMillis);
    });

    test('a tombstone survives the round trip', () {
      final row = reminderToRow(
        Reminder(id: 'r1', title: 'x', dueAt: DateTime(2026, 9, 17))
            .markDeleted(9),
      );
      expect(reminderFromRow(_asServerRow(row)).isDeleted, isTrue);
    });
  });

  group('subjects and study logs', () {
    test('subject round-trips, colour included', () {
      final subject = Subject(
        id: 's1',
        name: 'Physiology',
        colorValue: 0xFFD8A657,
        createdAt: DateTime(2026, 3, 2),
      ).stampUpdated(1700);

      final back = subjectFromRow(_asServerRow(subjectToRow(subject)));

      expect(back.name, 'Physiology');
      expect(back.colorValue, 0xFFD8A657);
      expect(back.createdAt, DateTime(2026, 3, 2));
    });

    test('a study log keeps its composite id', () {
      final log = StudyLog(
        id: 'study-s1-1757800000000000',
        subjectId: 's1',
        subjectName: 'Physiology',
        durationMinutes: 45,
        timestamp: DateTime(2026, 9, 14, 20, 15),
      ).stampUpdated(1700);

      final back = studyLogFromRow(_asServerRow(studyLogToRow(log)));

      // Not a uuid, which is why the id column is text.
      expect(back.id, 'study-s1-1757800000000000');
      expect(back.subjectName, 'Physiology');
      expect(back.durationMinutes, 45);
      expect(back.timestamp, DateTime(2026, 9, 14, 20, 15));
    });
  });

  group('wire formats PostgREST actually sends', () {
    test('a timestamp with an explicit offset parses to the same instant', () {
      final withZ = _taskRow({'created_at': '2026-09-01T05:00:00Z'});
      final withOffset =
          _taskRow({'created_at': '2026-09-01T08:00:00+03:00'});

      expect(taskFromRow(withZ).createdAt,
          taskFromRow(withOffset).createdAt);
    });

    test('a timestamp with microseconds parses', () {
      final row = _taskRow({'created_at': '2026-09-01T05:00:00.123456Z'});
      expect(taskFromRow(row).createdAt.isUtc, isFalse,
          reason: 'read back into the local zone the app compares in');
    });

    test('client_updated_at arrives as a JSON number', () {
      expect(taskFromRow(_taskRow({'client_updated_at': 1757800000000}))
          .updatedAtMillis, 1757800000000);
    });

    test('a bigint colour arrives as a number, not a string', () {
      final row = _asServerRow(subjectToRow(
        Subject(id: 's1', name: 'X', colorValue: 4292508759).stampUpdated(1),
      ));
      expect(subjectFromRow(row).colorValue, 4292508759);
    });
  });
}

/// A row as the server hands it back: whatever the client sent, plus the
/// server-stamped cursor it adds.
Map<String, dynamic> _asServerRow(Map<String, Object?> row) => {
      ...row,
      'user_id': 'user-1',
      'updated_at': '2026-09-17T05:00:00Z',
    };

Map<String, dynamic> _taskRow([Map<String, Object?> overrides = const {}]) => {
      'id': 't1',
      'user_id': 'user-1',
      'title': 'A task',
      'description': '',
      'due_date': null,
      'is_completed': false,
      'category': 'General',
      'priority': 'medium',
      'created_at': '2026-09-01T05:00:00Z',
      'has_reminder': false,
      'client_updated_at': 1700,
      'updated_at': '2026-09-17T05:00:00Z',
      'deleted': false,
      ...overrides,
    };
