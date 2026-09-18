// Renders the Tasks pane alone, at phone size, with representative data.
//
//     flutter run -d windows -t tool/tasks_preview.dart
//
// A companion to `ios_preview.dart`, which boots the whole shell. That one is
// the right tool for the nav pill and the breakpoints; it is the wrong one for
// this screen, because the Tasks pane is reached by tapping a nav item and its
// interesting states — a populated Yesterday, a past section at 60%, an
// overdue reminder — only exist once there is data behind them. So this
// entrypoint skips the shell, seeds both lists in memory, and paints the pane
// inside a fixed 393x852 frame so a screenshot lines up against the design
// regardless of how large the desktop window is.
//
// **What this does and does not tell you.** The widgets, the palette, the
// grouping and the layout are the real ones. The *typeface* is not: the SF Pro
// path in `AppTypography` turns on for `TargetPlatform.iOS`, which this does
// force — but Windows has no SF Pro to fall through to, so the text renders in
// whatever this machine's UI font is. Type has to be judged on a device or in
// the simulator.
//
// Nothing here is reachable from the app. Seeding is in-memory, so it touches
// no Hive box and cannot disturb the installed build's data.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cotv/src/models/reminder.dart';
import 'package:cotv/src/models/task.dart';
import 'package:cotv/src/providers/clock_providers.dart';
import 'package:cotv/src/providers/reminder_providers.dart';
import 'package:cotv/src/providers/task_providers.dart';
import 'package:cotv/src/repositories/reminder_repository.dart';
import 'package:cotv/src/repositories/task_repository.dart';
import 'package:cotv/src/ui/tasks/task_list_view.dart';
import 'package:cotv/src/ui/theme/app_theme.dart';
import 'package:cotv/src/ui/widgets/orb_field_background.dart';

/// Pinned rather than `DateTime.now()`, so the same screenshot comes out of
/// this tomorrow and the sections below always land where they are meant to.
final _now = DateTime(2026, 9, 18, 14, 30);

DateTime _at(int daysAgo, int hour, int minute) => DateTime(
      _now.year,
      _now.month,
      _now.day - daysAgo,
      hour,
      minute,
    );

final _tasks = <Task>[
  Task(
    id: 't1',
    title: 'Workout',
    dueDate: _at(0, 7, 0),
    priority: TaskPriority.low,
  ),
  Task(
    id: 't2',
    title: "Watch Dr.Bassant's Lecture",
    dueDate: _at(0, 18, 0),
    priority: TaskPriority.medium,
  ),
  Task(
    id: 't3',
    title: "Watch Dr.Tarek's Lecture",
    dueDate: _at(0, 20, 0),
    priority: TaskPriority.high,
    isCompleted: true,
  ),
  Task(
    id: 't4',
    title: 'Workout',
    dueDate: _at(1, 7, 0),
    priority: TaskPriority.low,
  ),
  Task(
    id: 't5',
    title: "Watch Dr.Bassant's Lecture",
    dueDate: _at(1, 18, 0),
    priority: TaskPriority.medium,
  ),
  Task(
    id: 't6',
    title: "Watch Dr.Tarek's Lecture",
    dueDate: _at(1, 20, 0),
    priority: TaskPriority.high,
    isCompleted: true,
  ),
  Task(
    id: 't7',
    title: 'Revise cardiovascular block',
    dueDate: _at(4, 9, 0),
    priority: TaskPriority.medium,
  ),
];

final _reminders = <Reminder>[
  // Due later today: the muted due line.
  Reminder(
    id: 'r1',
    title: 'Workout',
    dueAt: _at(0, 18, 0),
    priority: TaskPriority.low,
  ),
  // Already past, and not ticked: the overdue red.
  Reminder(
    id: 'r2',
    title: "Watch Dr.Bassant's Lecture",
    dueAt: _at(0, 9, 0),
    priority: TaskPriority.medium,
  ),
  // Past but ticked, so it reads as handled rather than missed.
  Reminder(
    id: 'r3',
    title: "Watch Dr.Tarek's Lecture",
    dueAt: _at(0, 11, 0),
    priority: TaskPriority.high,
    isCompleted: true,
  ),
  Reminder(
    id: 'r4',
    title: 'Workout',
    dueAt: _at(1, 18, 0),
    priority: TaskPriority.low,
  ),
  Reminder(
    id: 'r5',
    title: "Watch Dr.Tarek's Lecture",
    dueAt: _at(1, 20, 0),
    priority: TaskPriority.high,
    isCompleted: true,
  ),
];

void main() {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  runApp(
    ProviderScope(
      overrides: [
        currentMinuteProvider.overrideWithValue(_now),
        taskRepositoryProvider
            .overrideWithValue(_MemoryTaskRepository(_tasks)),
        reminderRepositoryProvider
            .overrideWithValue(_MemoryReminderRepository(_reminders)),
      ],
      child: const _PreviewApp(),
    ),
  );
}

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const _PhoneFrame(child: TaskListView()),
    );
  }
}

/// A 393x852 viewport — iPhone 14 Pro — centred in whatever the desktop
/// window happens to be.
///
/// The [MediaQuery] is rebuilt rather than inherited so `AdaptiveLayout`
/// resolves to the compact breakpoint and `pagePadding` matches a phone, and
/// so the pane's own bottom inset is the home indicator's rather than the
/// desktop window's zero.
class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({required this.child});

  static const Size size = Size(393, 852);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return ColoredBox(
      color: const Color(0xFF0B0B0C),
      child: Center(
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: MediaQuery(
            data: MediaQueryData(
              size: size,
              padding: const EdgeInsets.only(top: 59, bottom: 34),
              devicePixelRatio: 1,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(44),
              child: Scaffold(
                backgroundColor: palette.background,
                body: OrbFieldBackground(
                  child: SafeArea(bottom: false, child: child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MemoryTaskRepository implements TaskRepository {
  _MemoryTaskRepository(List<Task> seed) : _tasks = [...seed];

  final List<Task> _tasks;
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

class _MemoryReminderRepository implements ReminderRepository {
  _MemoryReminderRepository(List<Reminder> seed) : _reminders = [...seed];

  final List<Reminder> _reminders;
  final _changes = StreamController<List<Reminder>>.broadcast();

  void _emit() => _changes.add(List.unmodifiable(_reminders));

  @override
  Stream<List<Reminder>> watchAll() async* {
    yield List.unmodifiable(_reminders);
    yield* _changes.stream;
  }

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
