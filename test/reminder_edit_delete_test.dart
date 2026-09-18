// Exercises a reminder's row in the merged tasks list, end to end: a tap opens
// `ReminderFormSheet` pre-filled, Save writes through the notifier, the sheet's
// delete control writes through after confirmation, and the checkbox toggles.
//
// There is no Reminders segment to reach first any more — tasks and reminders
// share one list — so these pump the screen and find the row directly. The
// task repository is still overridden empty, so the only rows on screen are
// the reminders each test seeds.
//
// No Hive here. Both `taskRepositoryProvider` and `reminderRepositoryProvider`
// are overridden with in-memory stubs, so the real notifiers run — the write
// path is what these tests are about — without real file IO, which cannot
// complete inside the fake async zone `testWidgets` runs a body in.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cotv/src/models/reminder.dart';
import 'package:cotv/src/models/task.dart';
import 'package:cotv/src/providers/clock_providers.dart';
import 'package:cotv/src/providers/reminder_providers.dart';
import 'package:cotv/src/providers/task_providers.dart';
import 'package:cotv/src/repositories/reminder_repository.dart';
import 'package:cotv/src/repositories/task_repository.dart';
import 'package:cotv/src/ui/tasks/reminder_form_sheet.dart';
import 'package:cotv/src/ui/tasks/task_list_view.dart';
import 'package:cotv/src/ui/theme/app_theme.dart';

/// Starts empty, and remembers what it is given.
///
/// It would be simpler to discard writes — no test here seeds a task — but the
/// inline add row writes a *task* now even on a list of reminders, and a stub
/// that threw the write away would let that test pass without the row ever
/// reaching the screen.
class _FakeTaskRepository implements TaskRepository {
  final List<Task> _tasks = [];
  final _changes = StreamController<List<Task>>.broadcast();

  void _emit() => _changes.add(List.unmodifiable(_tasks));

  @override
  Stream<List<Task>> watchAll() async* {
    yield List.unmodifiable(_tasks);
    yield* _changes.stream;
  }

  @override
  List<Task> getAll() => List.unmodifiable(_tasks);

  @override
  Task? getById(String id) {
    for (final task in _tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  @override
  Future<void> add(Task task) async {
    _tasks.add(task);
    _emit();
  }

  @override
  Future<void> update(Task task) async {
    final index = _tasks.indexWhere((t) => t.id == task.id);
    if (index >= 0) _tasks[index] = task;
    _emit();
  }

  @override
  Future<void> delete(String id) async {
    _tasks.removeWhere((t) => t.id == id);
    _emit();
  }

  @override
  Future<void> toggleCompleted(String id) async {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index < 0) return;
    _tasks[index] =
        _tasks[index].copyWith(isCompleted: !_tasks[index].isCompleted);
    _emit();
  }
}

/// A list in memory behind the real [ReminderListNotifier].
///
/// Deliberately a repository stub rather than a notifier stub: overriding the
/// notifier would replace the very code these tests exist to cover.
class _FakeReminderRepository implements ReminderRepository {
  _FakeReminderRepository(List<Reminder> seed)
      : _reminders = [...seed],
        _changes = StreamController<List<Reminder>>.broadcast();

  final List<Reminder> _reminders;
  final StreamController<List<Reminder>> _changes;

  @override
  Stream<List<Reminder>> watchAll() async* {
    yield List.unmodifiable(_reminders);
    yield* _changes.stream;
  }

  void _emit() => _changes.add(List.unmodifiable(_reminders));

  @override
  List<Reminder> getAll() => List.unmodifiable(_reminders);

  @override
  Reminder? getById(String id) {
    for (final reminder in _reminders) {
      if (reminder.id == id) return reminder;
    }
    return null;
  }

  @override
  Future<void> add(Reminder reminder) async {
    _reminders.add(reminder);
    _emit();
  }

  @override
  Future<void> update(Reminder reminder) async {
    final index = _reminders.indexWhere((r) => r.id == reminder.id);
    if (index >= 0) _reminders[index] = reminder;
    _emit();
  }

  @override
  Future<void> delete(String id) async {
    _reminders.removeWhere((r) => r.id == id);
    _emit();
  }

  @override
  Future<void> toggleCompleted(String id) async {
    final index = _reminders.indexWhere((r) => r.id == id);
    if (index < 0) return;
    _reminders[index] =
        _reminders[index].copyWith(isCompleted: !_reminders[index].isCompleted);
    _emit();
  }
}

/// Midday today, and every fixture below is relative to it.
///
/// Not a fixed date, which is what this was. The inline add row builds a
/// `Task` whose `createdAt` defaults to `DateTime.now()` — the wall clock, not
/// `currentMinuteProvider` — and the screen files an undated task by that. Pin
/// the provider to some day in the past and the two disagree by however long
/// ago that was, so the new row lands outside every section and never appears.
final _today = DateTime.now();
final _now = DateTime(_today.year, _today.month, _today.day, 12);

/// Due the same day as [_now]. It has to be: the screen groups by day and
/// shows Today, Yesterday and the six days before that — a reminder dated
/// tomorrow has no section to appear in.
final _workout = Reminder(
  id: 'r1',
  title: 'Workout',
  dueAt: DateTime(_today.year, _today.month, _today.day, 18),
);

Future<_FakeReminderRepository> _pumpReminders(
  WidgetTester tester, {
  required List<Reminder> reminders,
}) async {
  final repository = _FakeReminderRepository(reminders);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentMinuteProvider.overrideWithValue(_now),
        taskRepositoryProvider.overrideWithValue(_FakeTaskRepository()),
        reminderRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: TaskListView()),
      ),
    ),
  );
  // Twice: once for each box's stream to deliver. The screen holds a spinner
  // until both have, so a single pump renders nothing.
  await tester.pump();
  await tester.pump();
  await tester.pumpAndSettle();

  return repository;
}

void main() {
  testWidgets(
      'tapping a reminder opens it pre-filled for editing, and Save writes '
      'the new title back to the list', (tester) async {
    await _pumpReminders(tester, reminders: [_workout]);

    expect(find.text('Workout'), findsOneWidget);
    expect(find.text('Today at 18:00'), findsOneWidget);

    await tester.tap(find.text('Workout'));
    // The sheet slides up from off-screen; a single argument-less pump()
    // rebuilds the tree without advancing the transition, so its contents
    // exist but aren't yet at their resting (hit-testable) position. No
    // Milo orb anywhere in this tree, so settling is safe here.
    await tester.pumpAndSettle();

    expect(find.text('Edit reminder'), findsOneWidget);
    final field = tester.widget<TextFormField>(find.byType(TextFormField));
    expect(field.controller?.text, 'Workout');

    await tester.enterText(find.byType(TextFormField), 'Workout — moved');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // The sheet closed...
    expect(find.text('Edit reminder'), findsNothing);
    // ...and the list reflects the edit, not a second row alongside it.
    expect(find.text('Workout — moved'), findsOneWidget);
    expect(find.text('Workout'), findsNothing);
  });

  testWidgets(
      "the edit sheet's delete control removes the reminder once confirmed",
      (tester) async {
    final repository = await _pumpReminders(tester, reminders: [_workout]);

    await tester.tap(find.text('Workout'));
    // See the comment in the test above: the sheet needs to finish sliding
    // into place before anything inside it is hit-testable.
    await tester.pumpAndSettle();
    expect(find.text('Edit reminder'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Delete reminder'));
    await tester.pumpAndSettle();

    expect(find.text('Delete reminder?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    // Both the sheet and the dialog are gone...
    expect(find.text('Edit reminder'), findsNothing);
    expect(find.text('Delete reminder?'), findsNothing);
    // ...and the reminder is actually gone, not merely the sheet that
    // edited it.
    expect(find.text('Workout'), findsNothing);
    expect(repository.getAll(), isEmpty);
  });

  testWidgets('the Today card adds a task inline, without a sheet',
      (tester) async {
    final repository = await _pumpReminders(tester, reminders: const []);

    // The Today section renders even with nothing in it, because it carries
    // the add control.
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsNothing);

    // 'Add task', not 'Add reminder'. The list is merged, so the add row has
    // to pick one kind, and it picks the one that needs no date — a reminder
    // cannot exist without a moment and this control has nowhere to ask.
    await tester.tap(find.bySemanticsLabel('Add task'));
    await tester.pumpAndSettle();

    // No sheet — the row became a field in place. Asserted on the sheet type
    // rather than its title: "New task" is also the inline field's hint, so
    // the text is on screen either way.
    expect(find.byType(ReminderFormSheet), findsNothing);
    expect(find.byType(TextField), findsOneWidget);

    // The ⓘ only exists while the field is open.
    expect(find.bySemanticsLabel('About this task'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Stretch');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // Nothing reached the reminder box — the inline add writes a task — and
    // the task it wrote is on screen.
    expect(repository.getAll(), isEmpty);
    expect(find.text('Stretch'), findsOneWidget);
    // Still open and focused, ready for the next one.
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('the checkbox writes through and strikes the title',
      (tester) async {
    final repository = await _pumpReminders(tester, reminders: [_workout]);

    await tester.tap(find.bySemanticsLabel('Workout'));
    await tester.pumpAndSettle();

    expect(repository.getAll().single.isCompleted, isTrue);

    final title = tester.widget<Text>(find.text('Workout'));
    final style = DefaultTextStyle.of(
      tester.element(find.text('Workout')),
    ).style.merge(title.style);
    expect(style.decoration, TextDecoration.lineThrough);
  });
}
