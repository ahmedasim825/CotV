// Exercises the Reminders segment end to end: a tap on a row opens
// `ReminderFormSheet` pre-filled, Save writes through the notifier, the
// sheet's delete control writes through after confirmation, and the inline
// `+` at the foot of the Today card adds one without a sheet at all.
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

/// Always empty and never written to — these tests only exercise the
/// Reminders segment, but `TaskListView` defaults to Tasks on first build,
/// so the task list needs a repository that isn't a real Hive box.
class _EmptyTaskRepository implements TaskRepository {
  @override
  Stream<List<Task>> watchAll() => Stream.value(const []);

  @override
  List<Task> getAll() => const [];

  @override
  Task? getById(String id) => null;

  @override
  Future<void> add(Task task) async {}

  @override
  Future<void> update(Task task) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> toggleCompleted(String id) async {}
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

final _now = DateTime(2026, 7, 28, 12, 0);

/// Due the same day as [_now]. It has to be: the screen groups by day and
/// shows Today, Yesterday and the six days before that — a reminder dated
/// tomorrow has no section to appear in.
final _workout = Reminder(
  id: 'r1',
  title: 'Workout',
  dueAt: DateTime(2026, 7, 28, 18, 0),
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
        taskRepositoryProvider.overrideWithValue(_EmptyTaskRepository()),
        reminderRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: TaskListView()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();

  await tester.tap(find.text('Reminders'));
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

  testWidgets('the Today card adds a reminder inline, without a sheet',
      (tester) async {
    final repository = await _pumpReminders(tester, reminders: const []);

    // The Today section renders even with nothing in it, because it carries
    // the add control.
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Add reminder'));
    await tester.pumpAndSettle();

    // No sheet — the row became a field in place. Asserted on the sheet type
    // rather than its title: "New reminder" is also the inline field's hint,
    // so the text is on screen either way.
    expect(find.byType(ReminderFormSheet), findsNothing);
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Stretch');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(repository.getAll().single.title, 'Stretch');
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
