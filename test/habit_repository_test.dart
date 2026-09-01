// Exercises HiveHabitRepository against a real (temp-directory-backed)
// Hive box — in particular the streak recomputation in
// toggleCompletedOn, which is easy to get subtly wrong around gaps and
// the "grace period" that keeps yesterday's streak alive until today's
// instance is done.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import 'package:cotv/hive_registrar.g.dart';
import 'package:cotv/src/models/habit.dart';
import 'package:cotv/src/repositories/habit_repository.dart';

void main() {
  late Directory tempDir;
  late Box<Habit> box;
  late HabitRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cotv_hive_test_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapters();
    }
    box = await Hive.openBox<Habit>('test_habits');
    repository = HiveHabitRepository(box);
  });

  tearDown(() async {
    await box.close();
    await Hive.deleteBoxFromDisk('test_habits', path: tempDir.path);
    await tempDir.delete(recursive: true);
  });

  test('daily streak counts consecutive days ending today', () async {
    await repository.add(Habit(id: 'h1', title: 'Fajr on time'));

    final today = DateTime.now();
    for (var i = 0; i < 3; i++) {
      await repository.toggleCompletedOn('h1', today.subtract(Duration(days: i)));
    }

    final updated = repository.getById('h1')!;
    expect(updated.streakCount, 3);
    expect(updated.completedDates.length, 3);
  });

  test('daily streak stays alive through yesterday (grace period)', () async {
    await repository.add(Habit(id: 'h2', title: 'Dhuhr reading'));

    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    await repository.toggleCompletedOn('h2', yesterday);
    await repository.toggleCompletedOn('h2', yesterday.subtract(const Duration(days: 1)));

    final updated = repository.getById('h2')!;
    expect(updated.streakCount, 2);
  });

  test('daily streak breaks after a gap', () async {
    await repository.add(Habit(id: 'h3', title: 'Evening walk'));

    final today = DateTime.now();
    await repository.toggleCompletedOn('h3', today.subtract(const Duration(days: 5)));
    await repository.toggleCompletedOn('h3', today);

    final updated = repository.getById('h3')!;
    expect(updated.streakCount, 1);
    expect(updated.completedDates.length, 2);
  });

  test('toggling the same date twice removes it', () async {
    await repository.add(Habit(id: 'h4', title: 'Journal'));

    final today = DateTime.now();
    await repository.toggleCompletedOn('h4', today);
    await repository.toggleCompletedOn('h4', today);

    final updated = repository.getById('h4')!;
    expect(updated.completedDates, isEmpty);
    expect(updated.streakCount, 0);
  });

  test('weekly streak counts consecutive weeks', () async {
    await repository.add(
      Habit(id: 'h5', title: 'Long walk', frequency: HabitFrequency.weekly),
    );

    final now = DateTime.now();
    await repository.toggleCompletedOn('h5', now);
    await repository.toggleCompletedOn('h5', now.subtract(const Duration(days: 7)));

    final updated = repository.getById('h5')!;
    expect(updated.streakCount, 2);
  });

  test('toggleCompletedOn throws for an unknown habit id', () async {
    expect(
      () => repository.toggleCompletedOn('missing', DateTime.now()),
      throwsA(isA<StateError>()),
    );
  });

  test('watchAll emits the current list immediately and again on change', () async {
    final emissions = <int>[];
    final subscription = repository.watchAll().map((list) => list.length).listen(emissions.add);
    // Let the stream's initial snapshot flush before mutating, or the two
    // put()-triggered emissions can race ahead of it.
    await Future<void>.delayed(Duration.zero);

    await repository.add(Habit(id: 'h6', title: 'Read Quran'));
    await repository.add(Habit(id: 'h7', title: 'Stretch'));
    await Future<void>.delayed(Duration.zero);

    await subscription.cancel();
    expect(emissions, [0, 1, 2]);
  });
}
