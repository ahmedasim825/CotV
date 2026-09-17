// Stage 1 of cross-device sync: record metadata and soft deletes.
//
// The two claims worth proving here are the ones that would be silent and
// expensive to get wrong. First, that a box written before these fields
// existed still reads — the generated adapter's null handling is what the
// whole migration rests on. Second, that a tombstone is invisible to every
// read path: it stays in the box so the deletion can be pushed, and
// anything above the repository that saw it would be showing the user a
// task they deleted.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import 'package:cotv/hive_registrar.g.dart';
import 'package:cotv/src/models/habit.dart';
import 'package:cotv/src/models/study_log.dart';
import 'package:cotv/src/models/subject.dart';
import 'package:cotv/src/models/sync_stamped.dart';
import 'package:cotv/src/models/task.dart';
import 'package:cotv/src/repositories/habit_repository.dart';
import 'package:cotv/src/repositories/study_log_repository.dart';
import 'package:cotv/src/repositories/subject_repository.dart';
import 'package:cotv/src/repositories/task_repository.dart';

/// Writes a [Task] in its pre-sync shape: the original nine fields and
/// nothing else, exactly as the adapter generated before 9/10/11 existed.
///
/// Registered over the real adapter for one write, then swapped back. This
/// is the only honest way to produce a row that predates the migration —
/// hand-building a Task and clearing the fields would still be written by
/// the current adapter, with all twelve field bytes present.
class _LegacyTaskAdapter extends TypeAdapter<Task> {
  @override
  final int typeId = 0;

  @override
  Task read(BinaryReader reader) {
    final count = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < count; i++) reader.readByte(): reader.read(),
    };
    return Task(
      id: fields[0] as String,
      title: fields[1] as String,
      createdAt: fields[7] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, Task obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.description)
      ..writeByte(3)
      ..write(obj.dueDate)
      ..writeByte(4)
      ..write(obj.isCompleted)
      ..writeByte(5)
      ..write(obj.category)
      ..writeByte(6)
      ..write(obj.priority)
      ..writeByte(7)
      ..write(obj.createdAt)
      ..writeByte(8)
      ..write(obj.hasReminder);
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cotv_tombstone_test_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapters();
    }
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  group('backward compatibility', () {
    test('a row written without the sync fields still reads', () async {
      Hive.registerAdapter(_LegacyTaskAdapter(), override: true);
      var box = await Hive.openBox<Task>('legacy_tasks');
      await box.put('t1', Task(id: 't1', title: 'Written last March'));
      await box.close();

      // Back to the generated adapter. Restored one at a time rather than
      // through registerAdapters(), which re-registers every typeId without
      // override and would collide on the ones already in place.
      Hive.registerAdapter(TaskAdapter(), override: true);
      box = await Hive.openBox<Task>('legacy_tasks');

      final task = box.get('t1')!;
      expect(task.title, 'Written last March');
      expect(task.updatedAtMillis, isNull);
      expect(task.isDeleted, isFalse);
      expect(task.syncedAtMillis, isNull);
    });
  });

  group('copyWith carries the sync fields', () {
    test('an edit does not un-migrate the record', () {
      final stamped = Task(id: 't1', title: 'Original')
          .stampUpdated(1000)
          .markSynced(1000);

      final edited = stamped.copyWith(title: 'Edited');

      expect(edited.title, 'Edited');
      expect(edited.updatedAtMillis, 1000);
      expect(edited.syncedAtMillis, 1000);
      expect(edited.isDeleted, isFalse);
    });

    test('a tombstone survives an edit', () {
      final deleted = Task(id: 't1', title: 'Gone').markDeleted(1000);
      expect(deleted.copyWith(title: 'Still gone').isDeleted, isTrue);
    });
  });

  group('tasks', () {
    late Box<Task> box;
    late HiveTaskRepository repository;

    setUp(() async {
      box = await Hive.openBox<Task>('t_tasks');
      repository = HiveTaskRepository(box, () => 5000);
    });

    test('writes are stamped with the clock', () async {
      await repository.add(Task(id: 't1', title: 'Stamped'));
      expect(box.get('t1')!.updatedAtMillis, 5000);
      // Never synced, so dirty — which is what makes the first push send it.
      expect(box.get('t1')!.isDirty, isTrue);
    });

    test('delete tombstones rather than removing', () async {
      await repository.add(Task(id: 't1', title: 'Doomed'));
      await repository.delete('t1');

      expect(box.get('t1'), isNotNull, reason: 'the row must survive to push');
      expect(box.get('t1')!.isDeleted, isTrue);
      expect(repository.getAll(), isEmpty);
      expect(repository.getById('t1'), isNull);
      expect(await repository.watchAll().first, isEmpty);
      expect(repository.allIncludingDeleted(), hasLength(1));
    });

    test('toggleCompleted refuses a tombstoned task', () async {
      await repository.add(Task(id: 't1', title: 'Doomed'));
      await repository.delete('t1');
      expect(() => repository.toggleCompleted('t1'), throwsStateError);
    });

    test('markSynced is ignored when the record moved on', () async {
      await repository.add(Task(id: 't1', title: 'Racy'));
      // A push of the 5000 state lands after a local edit at 7000.
      final edited = HiveTaskRepository(box, () => 7000);
      await edited.update(box.get('t1')!);
      await repository.markSynced('t1', 5000);

      expect(box.get('t1')!.syncedAtMillis, isNull);
      expect(box.get('t1')!.isDirty, isTrue,
          reason: 'the 7000 edit still needs pushing');
    });

    test('applyRemote keeps the timestamp it arrived with', () async {
      await repository.applyRemote(
        Task(id: 't1', title: 'From the phone')
            .stampUpdated(1234)
            .markSynced(1234),
      );
      expect(box.get('t1')!.updatedAtMillis, 1234);
      expect(box.get('t1')!.isDirty, isFalse,
          reason: 'a pulled record must not read as a local edit');
    });

    test('purge drops only synced tombstones past the cutoff', () async {
      await repository.applyRemote(
        Task(id: 'old', title: 'Old').markDeleted(1000).markSynced(1000),
      );
      await repository.applyRemote(
        Task(id: 'recent', title: 'Recent').markDeleted(9000).markSynced(9000),
      );
      await repository.applyRemote(
        Task(id: 'unpushed', title: 'Unpushed').markDeleted(1000),
      );

      final purged = await repository.purgeTombstonesBefore(5000);

      expect(purged, 1);
      expect(box.get('old'), isNull);
      expect(box.get('recent'), isNotNull);
      expect(box.get('unpushed'), isNotNull,
          reason: 'dropping it before pushing would resurrect the row');
    });
  });

  group('subjects', () {
    test('findByName skips tombstones', () async {
      final box = await Hive.openBox<Subject>('t_subjects');
      final repository = HiveSubjectRepository(box, () => 5000);
      await repository.add(
        Subject(id: 's1', name: 'Physiology', colorValue: 0xFF000000),
      );

      expect(repository.findByName('physiology'), isNotNull);
      await repository.delete('s1');

      // Milo's tool-dispatch path: a leak here starts a timer against a
      // subject the user deleted.
      expect(repository.findByName('physiology'), isNull);
      expect(repository.getAll(), isEmpty);
    });
  });

  group('study logs', () {
    test('append stamps and delete tombstones', () async {
      final box = await Hive.openBox<StudyLog>('t_logs');
      final repository = HiveStudyLogRepository(box, () => 5000);
      await repository.append(
        StudyLog(
          id: 'study-s1-1',
          subjectId: 's1',
          subjectName: 'Physiology',
          durationMinutes: 45,
          timestamp: DateTime(2026, 9, 14),
        ),
      );

      expect(box.get('study-s1-1')!.updatedAtMillis, 5000);
      await repository.delete('study-s1-1');
      expect(repository.getAll(), isEmpty);
      expect(box.get('study-s1-1')!.isDeleted, isTrue);
    });
  });

  group('habits', () {
    test('a toggle stamps the record', () async {
      final box = await Hive.openBox<Habit>('t_habits');
      final repository = HiveHabitRepository(box, () => 5000);
      await repository.add(Habit(id: 'h1', title: 'Fajr on time'));
      await repository.toggleCompletedOn('h1', DateTime.now());

      expect(box.get('h1')!.updatedAtMillis, 5000);
      expect(box.get('h1')!.streakCount, 1);
    });
  });
}
