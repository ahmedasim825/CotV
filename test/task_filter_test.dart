// Exercises the filter at the head of the tasks list: that each entry narrows
// the list the way its label claims, and that the button follows the choice.
//
// The menu itself is a native `UIMenu` on a device and a `CupertinoActionSheet`
// everywhere else, including here — the package gates on `Platform.isIOS`,
// which is false under `flutter_test` on this machine whatever the theme says.
// So these drive the fallback, and the dropdown, its blur and SF Pro on the
// button can only be checked on a device.

import 'dart:async';

import 'package:flutter/cupertino.dart';
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
import 'package:cotv/src/ui/tasks/task_list_view.dart';
import 'package:cotv/src/ui/theme/app_theme.dart';

/// Relative to the real clock, because the screen files an undated task by its
/// `createdAt`, which comes from the wall clock rather than the provider.
final _today = DateTime.now();
DateTime _at(int daysFromToday, int hour) => DateTime(
      _today.year,
      _today.month,
      _today.day + daysFromToday,
      hour,
    );
final _now = _at(0, 12);

class _Tasks implements TaskRepository {
  _Tasks(this._tasks);
  final List<Task> _tasks;

  @override
  Stream<List<Task>> watchAll() => Stream.value(List.unmodifiable(_tasks));
  @override
  List<Task> getAll() => List.unmodifiable(_tasks);
  @override
  Task? getById(String id) =>
      _tasks.where((t) => t.id == id).firstOrNull;
  @override
  Future<void> add(Task task) async {}
  @override
  Future<void> update(Task task) async {}
  @override
  Future<void> delete(String id) async {}
  @override
  Future<void> toggleCompleted(String id) async {}
}

class _Reminders implements ReminderRepository {
  _Reminders(this._reminders);
  final List<Reminder> _reminders;

  @override
  Stream<List<Reminder>> watchAll() =>
      Stream.value(List.unmodifiable(_reminders));
  @override
  List<Reminder> getAll() => List.unmodifiable(_reminders);
  @override
  Reminder? getById(String id) =>
      _reminders.where((r) => r.id == id).firstOrNull;
  @override
  Future<void> add(Reminder reminder) async {}
  @override
  Future<void> update(Reminder reminder) async {}
  @override
  Future<void> delete(String id) async {}
  @override
  Future<void> toggleCompleted(String id) async {}
}

final _tasks = [
  Task(id: 't-today', title: 'Task today', dueDate: _at(0, 9)),
  Task(id: 't-past', title: 'Task yesterday', dueDate: _at(-1, 9)),
  Task(id: 't-future', title: 'Task next week', dueDate: _at(3, 9)),
];

final _reminders = [
  Reminder(id: 'r-today', title: 'Reminder today', dueAt: _at(0, 18)),
  Reminder(id: 'r-future', title: 'Reminder next week', dueAt: _at(4, 18)),
];

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentMinuteProvider.overrideWithValue(_now),
        taskRepositoryProvider.overrideWithValue(_Tasks(_tasks)),
        reminderRepositoryProvider.overrideWithValue(_Reminders(_reminders)),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: TaskListView()),
      ),
    ),
  );
  // Once per box's stream; the screen holds a spinner until both answer.
  await tester.pump();
  await tester.pump();
  await tester.pumpAndSettle();
}

/// Opens the menu and picks [label] out of the action-sheet fallback.
Future<void> _choose(WidgetTester tester, String label) async {
  await tester.tap(find.text('All').first);
  await tester.pumpAndSettle();

  await tester.tap(
    find.descendant(
      of: find.byType(CupertinoActionSheet),
      matching: find.text(label),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('All interleaves both kinds and hides the future',
      (tester) async {
    await _pump(tester);

    expect(find.text('Task today'), findsOneWidget);
    expect(find.text('Reminder today'), findsOneWidget);
    expect(find.text('Task yesterday'), findsOneWidget);

    // The default range stops at today.
    expect(find.text('Task next week'), findsNothing);
    expect(find.text('Reminder next week'), findsNothing);
  });

  testWidgets('only a reminder carries a due line', (tester) async {
    await _pump(tester);

    // The reminder's moment is the point of it, so it says so. A task's date
    // is carried by the section it sits in.
    expect(find.text('Today at 18:00'), findsOneWidget);
    expect(find.text('Today at 09:00'), findsNothing);
  });

  testWidgets('Tasks drops the reminders', (tester) async {
    await _pump(tester);
    await _choose(tester, 'Tasks');

    expect(find.text('Task today'), findsOneWidget);
    expect(find.text('Reminder today'), findsNothing);
    // The button reports what it is showing.
    expect(find.text('Tasks'), findsWidgets);
  });

  testWidgets('Reminders drops the tasks', (tester) async {
    await _pump(tester);
    await _choose(tester, 'Reminders');

    expect(find.text('Reminder today'), findsOneWidget);
    expect(find.text('Task today'), findsNothing);
    expect(find.text('Task yesterday'), findsNothing);
  });

  testWidgets('Upcoming shows the future and nothing else', (tester) async {
    await _pump(tester);
    await _choose(tester, 'Upcoming');

    expect(find.text('Task next week'), findsOneWidget);
    expect(find.text('Reminder next week'), findsOneWidget);

    // Today is neither shown nor headed — and with no Today section there is
    // no inline add, which is the one thing this filter costs.
    expect(find.text('Task today'), findsNothing);
    expect(find.text('Today'), findsNothing);
    expect(find.bySemanticsLabel('Add task'), findsNothing);

    expect(find.text('This week'), findsOneWidget);
  });

  testWidgets('Past drops Today, which the grouping would otherwise force',
      (tester) async {
    await _pump(tester);
    await _choose(tester, 'Past');

    expect(find.text('Task yesterday'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);

    // `groupByDay` always emits Today so the add row has a home. A list called
    // Past that opened on today would be a plain contradiction.
    expect(find.text('Today'), findsNothing);
    expect(find.text('Task today'), findsNothing);
  });
}
