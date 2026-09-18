// Renders the Tasks pane alone, at phone size, with representative data.
//
//     flutter run -d windows -t tool/tasks_preview.dart
//
// A companion to `ios_preview.dart`, which boots the whole shell. That one is
// the right tool for the nav pill and the breakpoints; it is the wrong one for
// this screen, because the Tasks pane is reached by tapping a nav item and its
// interesting states — a populated Yesterday, a past section at 60%, an
// overdue reminder — only exist once there is data behind them. So this
// entrypoint seeds both lists in memory and paints the real shell — nav pill
// included — inside a fixed 393x852 frame, so a screenshot lines up against
// the design regardless of how large the desktop window is. Open it and tap
// Tasks.
//
// **What this does and does not tell you.** The widgets, the palette, the
// grouping and the layout are the real ones. The *typeface* is not: the SF Pro
// path in `AppTypography` turns on for `TargetPlatform.iOS`, which this does
// force — but Windows has no SF Pro to fall through to, so the text renders in
// whatever this machine's UI font is. Type has to be judged on a device or in
// the simulator.
//
// Nothing here is reachable from the app. Tasks and reminders are seeded in
// memory, over repository overrides, so neither list touches a box. The rest
// of the shell does still need its boxes open — the study session it
// reconciles on launch, the chat transcript Milo reads — so storage is
// initialised under a preview subdirectory of its own, the way
// `ios_preview.dart` does it, and cannot disturb the installed build's data.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cotv/src/models/reminder.dart';
import 'package:cotv/src/models/task.dart';
import 'package:cotv/src/providers/clock_providers.dart';
import 'package:cotv/src/providers/reminder_providers.dart';
import 'package:cotv/src/providers/chat_session_providers.dart';
import 'package:cotv/src/providers/task_providers.dart';
import 'package:cotv/src/repositories/reminder_repository.dart';
import 'package:cotv/src/repositories/task_repository.dart';
import 'package:cotv/src/storage/local_storage.dart';
import 'package:cotv/src/providers/ambient_providers.dart';
import 'package:cotv/src/ui/app_shell.dart';
import 'package:cotv/src/ui/components/liquid_glass.dart';
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
  // Ahead of today, so the Upcoming filter has something to show. Negative
  // days, because `_at` counts backwards — one per future section, so all
  // three headings appear.
  Task(
    id: 't8',
    title: 'Anatomy lab',
    dueDate: _at(-1, 10, 0),
    priority: TaskPriority.high,
  ),
  Task(
    id: 't9',
    title: 'Pharmacology quiz',
    dueDate: _at(-4, 9, 0),
    priority: TaskPriority.medium,
  ),
  Task(
    id: 't10',
    title: 'End of block exam',
    dueDate: _at(-21, 9, 0),
    priority: TaskPriority.high,
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
  // One in the future too, so Upcoming shows the merge rather than a list of
  // tasks — the due line under a reminder is the only thing telling the two
  // kinds apart, and it has to be visible in every section that can hold one.
  Reminder(
    id: 'r6',
    title: 'Call the clinic',
    dueAt: _at(-2, 11, 30),
    priority: TaskPriority.medium,
  ),
];

Future<void> main() async {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  WidgetsFlutterBinding.ensureInitialized();
  // Its own directory, so this can run while the installed build is open.
  // Hive takes a file lock per box, and the second process to start dies on a
  // locked box before it ever paints.
  await initializeLocalStorage(subdirectory: 'tasks-preview');
  final database = await bootstrapAppDatabase();
  // Same compile-once-up-front as `main.dart`: the nav pill's refraction is
  // half of what this screenshot is for, and a null program silently drops it
  // back to a plain blur.
  final program = await loadLiquidGlassProgram();

  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        currentMinuteProvider.overrideWithValue(_now),
        taskRepositoryProvider
            .overrideWithValue(_MemoryTaskRepository(_tasks)),
        reminderRepositoryProvider
            .overrideWithValue(_MemoryReminderRepository(_reminders)),
      ],
      child: _PreviewApp(glassProgram: program),
    ),
  );
}

class _PreviewApp extends ConsumerWidget {
  const _PreviewApp({this.glassProgram});

  final ui.FragmentProgram? glassProgram;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refract = ref.watch(liquidGlassRefractionProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      // Mirrors `PrayerLockoutApp`'s builder, minus the `SecurityGate`: an
      // app-lock prompt in front of a screenshot helps nobody.
      home: LiquidGlassScope(
        program: refract ? glassProgram : null,
        child: const _PhoneFrame(child: AppShell()),
      ),
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
            // Copied from the ambient data rather than built fresh, so only
            // the two fields this frame actually changes are changed.
            //
            // Building a `MediaQueryData()` here instead defaults
            // `devicePixelRatio` to 1, and that is not cosmetic: `LiquidGlass`
            // reads it to convert its own size into device pixels for the
            // refraction shader, while the engine keeps handing that shader a
            // texture measured in real ones. On a 150%-scaled display the two
            // disagree by half the widget's width, the SDF rect lands that far
            // to the right, and the nav pill renders with a hard vertical seam
            // down the middle — a bug entirely of this harness's making, which
            // cost an hour of hunting it in the shader.
            data: MediaQuery.of(context).copyWith(
              size: size,
              padding: const EdgeInsets.only(top: 59, bottom: 34),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(44),
              // `AppShell` brings its own Scaffold and reads the bottom
              // inset the nav pill republishes, so this only supplies the
              // ground the pill floats over.
              child: ColoredBox(
                color: palette.background,
                child: OrbFieldBackground(child: child),
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
