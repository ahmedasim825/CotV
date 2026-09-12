// Exercises the Reminders segment's edit/delete path end to end: a tap on a
// row opens `ReminderFormSheet` pre-filled, Save writes through
// `ReminderListController.update`, and the sheet's delete control writes
// through `.remove` after confirmation. Both mutators had zero callers
// before this fix — see the final-fix-b brief.
//
// No Hive here: `taskRepositoryProvider` is overridden with an in-memory
// stub so `TaskListView`'s default Tasks segment (built once, on the way to
// tapping into Reminders) has something to read that isn't a real box, and
// `reminderListProvider` is a plain in-memory `Notifier` to begin with.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cotv/src/models/reminder.dart';
import 'package:cotv/src/models/task.dart';
import 'package:cotv/src/providers/clock_providers.dart';
import 'package:cotv/src/providers/reminder_providers.dart';
import 'package:cotv/src/providers/task_providers.dart';
import 'package:cotv/src/repositories/task_repository.dart';
import 'package:cotv/src/ui/tasks/task_list_view.dart';
import 'package:cotv/src/ui/theme/app_theme.dart';

/// Always empty and never written to — these tests only exercise the
/// Reminders segment, but `TaskListView` defaults to Tasks on first build,
/// so `visibleTasksProvider` needs a repository that isn't a real Hive box.
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

class _SeededReminders extends ReminderListController {
  _SeededReminders(this._seed);

  final List<Reminder> _seed;

  @override
  List<Reminder> build() => _seed;
}

/// After both sample reminders' due dates (late July 2026), so overdue
/// coloring is deterministic rather than depending on the wall clock.
final _now = DateTime(2026, 7, 28, 12, 0);

Future<void> _pumpReminders(
  WidgetTester tester, {
  required List<Reminder> reminders,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentMinuteProvider.overrideWithValue(_now),
        taskRepositoryProvider.overrideWithValue(_EmptyTaskRepository()),
        reminderListProvider.overrideWith(() => _SeededReminders(reminders)),
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
  await tester.pump();
}

void main() {
  final workout = Reminder(
    id: 'r1',
    title: 'Workout',
    dueAt: DateTime(2026, 7, 29, 6, 0),
  );

  testWidgets(
      'tapping a reminder opens it pre-filled for editing, and Save writes '
      'the new title back to the list', (tester) async {
    await _pumpReminders(tester, reminders: [workout]);

    expect(find.text('Workout'), findsOneWidget);

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
    // No Milo orb anywhere in this tree, so settling is safe here.
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
    await _pumpReminders(tester, reminders: [workout]);

    await tester.tap(find.text('Workout'));
    // See the comment in the test above: the sheet needs to finish sliding
    // into place before anything inside it is hit-testable.
    await tester.pumpAndSettle();
    expect(find.text('Edit reminder'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Delete reminder'));
    await tester.pumpAndSettle();

    expect(find.text('Delete reminder?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    // No Milo orb anywhere in this tree, so settling is safe here.
    await tester.pumpAndSettle();

    // Both the sheet and the dialog are gone...
    expect(find.text('Edit reminder'), findsNothing);
    expect(find.text('Delete reminder?'), findsNothing);
    // ...and the reminder is actually gone, not merely the sheet that
    // edited it.
    expect(find.text('Workout'), findsNothing);
    expect(find.text('No reminders'), findsOneWidget);
  });

  testWidgets('the Reminders segment carries its own add button',
      (tester) async {
    await _pumpReminders(tester, reminders: const []);

    expect(find.text('No reminders'), findsOneWidget);

    await tester.tap(find.text('Reminder'));
    await tester.pump();

    expect(find.text('New reminder'), findsOneWidget);
  });
}
