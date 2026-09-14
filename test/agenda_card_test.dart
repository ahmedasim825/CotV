// Tests for the iOS dashboard's one Tasks / Reminders card.
//
// What matters here is the thing the mock made load-bearing: with no headings
// and no group separator, the ring colour is the *only* signal telling a task
// from a reminder. So the colours are pinned by value, and so is the merged
// order they appear in.
//
// The card is platform-gated material, but `AgendaCard` itself is not — it is
// pumped directly, and `HomeCardFrame` reads `context.useLiquidGlass` to pick
// its surface. The theme below therefore carries `platform: TargetPlatform.iOS`
// so the card renders the way iOS will actually draw it.
//
// Hive is real, backed by a temp directory, matching `home_dashboard_test.dart`.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` is not in flutter_riverpod.dart's own show-list in 3.4.x — it
// only comes through this leaf import.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import 'package:cotv/hive_registrar.g.dart';
import 'package:cotv/src/models/habit.dart';
import 'package:cotv/src/models/reminder.dart';
import 'package:cotv/src/models/task.dart';
import 'package:cotv/src/models/user_settings.dart';
import 'package:cotv/src/providers/clock_providers.dart';
import 'package:cotv/src/providers/notification_providers.dart';
import 'package:cotv/src/providers/reminder_providers.dart';
import 'package:cotv/src/providers/task_providers.dart';
import 'package:cotv/src/repositories/task_repository.dart';
import 'package:cotv/src/services/notification_service.dart';
import 'package:cotv/src/storage/local_storage.dart';
import 'package:cotv/src/ui/home/widgets/agenda_card.dart';
import 'package:cotv/src/ui/tasks/reminder_form_sheet.dart';
import 'package:cotv/src/ui/theme/app_theme.dart';
import 'package:cotv/src/ui/widgets/ph_light_icons.dart';

/// Ticking a task reconciles its reminder through a platform channel that
/// never answers under `flutter_test`, so the write would never resolve.
class _FakeNotificationService extends NotificationService {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> requestPermissions() async {}

  @override
  Future<bool> scheduleReminder({
    required String key,
    required DateTime when,
    required String title,
    required String body,
  }) async =>
      false;

  @override
  Future<void> cancelReminder(String key) async {}
}

/// Stands in for Hive on the tests that write from inside the widget tree —
/// Hive finishes its writes on the real event loop, which the fake-async zone
/// `testWidgets` runs in starves, so a tap would never return.
class _InMemoryTaskRepository implements TaskRepository {
  _InMemoryTaskRepository(List<Task> initial) : _tasks = [...initial];

  final List<Task> _tasks;
  final _changes = StreamController<List<Task>>.broadcast();

  /// Ids passed to [toggleCompleted], in order.
  final List<String> toggled = [];

  void dispose() => _changes.close();

  @override
  Stream<List<Task>> watchAll() async* {
    yield List.unmodifiable(_tasks);
    yield* _changes.stream;
  }

  @override
  List<Task> getAll() => List.unmodifiable(_tasks);

  @override
  Task? getById(String id) => _tasks.where((task) => task.id == id).firstOrNull;

  @override
  Future<void> add(Task task) async {
    _tasks.add(task);
    _changes.add(List.unmodifiable(_tasks));
  }

  @override
  Future<void> update(Task task) async {
    final index = _tasks.indexWhere((existing) => existing.id == task.id);
    _tasks[index] = task;
    _changes.add(List.unmodifiable(_tasks));
  }

  @override
  Future<void> delete(String id) async {
    _tasks.removeWhere((task) => task.id == id);
    _changes.add(List.unmodifiable(_tasks));
  }

  @override
  Future<void> toggleCompleted(String id) async {
    toggled.add(id);
    final index = _tasks.indexWhere((task) => task.id == id);
    if (index == -1) throw StateError('Task "$id" not found.');
    _tasks[index] =
        _tasks[index].copyWith(isCompleted: !_tasks[index].isCompleted);
    _changes.add(List.unmodifiable(_tasks));
  }
}

/// Replaces the seeded sample reminders with a set the test controls.
class _Reminders extends ReminderListController {
  _Reminders(this.seed);

  final List<Reminder> seed;

  @override
  List<Reminder> build() => seed;
}

/// Mid-afternoon on the day everything below is dated, so 09:00 is overdue
/// and 18:00 is still ahead.
final _now = DateTime(2026, 3, 17, 14, 30);

Task _task(String id, String title, {DateTime? due, bool completed = false}) =>
    Task(
      id: id,
      title: title,
      dueDate: due ?? DateTime(2026, 3, 17, 18),
      isCompleted: completed,
      createdAt: DateTime(2026, 3, 1),
    );

Reminder _reminder(String id, String title, {DateTime? due}) => Reminder(
      id: id,
      title: title,
      dueAt: due ?? DateTime(2026, 3, 17, 20),
    );

/// The ring drawn for [entryId], addressed by the key the card puts on it
/// rather than by position, so a reordering test failure names the ordering
/// and not the colour.
BoxDecoration _ring(WidgetTester tester, String entryId) {
  final container = tester.widget<AnimatedContainer>(
    find.byKey(ValueKey('ring-$entryId')),
  );
  return container.decoration! as BoxDecoration;
}

void main() {
  late Directory tempDir;
  late Box<Task> tasks;
  _InMemoryTaskRepository? repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cotv_agenda_test_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapters();
    }
    tasks = await Hive.openBox<Task>(HiveBoxes.tasks);
    await Hive.openBox<Habit>(HiveBoxes.habits);
    await Hive.openBox<UserSettings>(HiveBoxes.userSettings);
  });

  tearDown(() async {
    repository?.dispose();
    repository = null;
    await Hive.deleteFromDisk();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// Pumps the card under an iOS theme with the clock pinned.
  ///
  /// Never `pumpAndSettle`: nothing here animates forever, but the card's
  /// rings run a 320ms `AnimatedContainer` on mount and the explicit pumps
  /// below are what the rest of the suite uses.
  Future<void> pumpAgenda(
    WidgetTester tester, {
    List<Task> seedTasks = const [],
    List<Reminder> seedReminders = const [],
    bool useFakeRepository = false,
    DateTime? now,
    Size? surface,
    double textScale = 1.0,
    List<Override> overrides = const [],
  }) async {
    if (surface != null) {
      tester.view.physicalSize = surface;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    if (useFakeRepository) {
      repository = _InMemoryTaskRepository(seedTasks);
    } else {
      await tester.runAsync(() async {
        for (final task in seedTasks) {
          await tasks.put(task.id, task);
        }
      });
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentMinuteProvider.overrideWithValue(now ?? _now),
          notificationServiceProvider
              .overrideWithValue(_FakeNotificationService()),
          reminderListProvider.overrideWith(() => _Reminders(seedReminders)),
          if (repository != null)
            taskRepositoryProvider.overrideWithValue(repository!),
          ...overrides,
        ],
        child: MaterialApp(
          // The whole point of this file: `HomeCardFrame` reads
          // `context.useLiquidGlass`, which is `ThemeData.platform`.
          theme: buildAppTheme().copyWith(platform: TargetPlatform.iOS),
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: const Scaffold(
                body: SingleChildScrollView(child: AgendaCard()),
              ),
            ),
          ),
        ),
      ),
    );

    // The repository stream yields its first value on a microtask.
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('carries the merged title and one action', (tester) async {
    await pumpAgenda(tester, seedTasks: [_task('a', 'Workout')]);

    expect(find.text('Tasks / Reminders'), findsOneWidget);
    expect(find.byIcon(PhLight.pencilSimple), findsOneWidget);
  });

  testWidgets('an empty day says so rather than showing rows', (tester) async {
    await pumpAgenda(tester);

    expect(find.text('Nothing due today.'), findsOneWidget);
  });

  testWidgets('interleaves both kinds by due time, not by kind',
      (tester) async {
    await pumpAgenda(
      tester,
      seedTasks: [
        _task('a', 'Workout', due: DateTime(2026, 3, 17, 9)),
        _task('b', 'Dissection notes', due: DateTime(2026, 3, 17, 21)),
      ],
      seedReminders: [
        _reminder('r1', "Watch Dr.Tarek's Lecture",
            due: DateTime(2026, 3, 17, 13)),
      ],
    );

    final order = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .toList();

    expect(order.indexOf('Workout'),
        lessThan(order.indexOf("Watch Dr.Tarek's Lecture")));
    expect(order.indexOf("Watch Dr.Tarek's Lecture"),
        lessThan(order.indexOf('Dissection notes')));
  });

  testWidgets('a task ring is FFE100 and a reminder ring is FF0000',
      (tester) async {
    await pumpAgenda(
      tester,
      seedTasks: [_task('a', 'Workout', due: DateTime(2026, 3, 17, 9))],
      seedReminders: [
        _reminder('r1', 'Lecture', due: DateTime(2026, 3, 17, 13)),
      ],
    );

    expect(
      (_ring(tester, 'task-a').border! as Border).top.color,
      const Color(0xFFFFE100),
    );
    expect(
      (_ring(tester, 'reminder-r1').border! as Border).top.color,
      const Color(0xFFFF0000),
    );
  });

  testWidgets('a reminder ring stays red whether or not it is overdue',
      (tester) async {
    await pumpAgenda(
      tester,
      seedReminders: [
        // 09:00 is behind the pinned 14:30; 20:00 is ahead of it.
        _reminder('late', 'Missed it', due: DateTime(2026, 3, 17, 9)),
        _reminder('soon', 'Still ahead', due: DateTime(2026, 3, 17, 20)),
      ],
    );

    for (final id in ['reminder-late', 'reminder-soon']) {
      expect(
        (_ring(tester, id).border! as Border).top.color,
        const Color(0xFFFF0000),
        reason: 'the ring means "reminder", not "late"',
      );
    }
  });

  testWidgets('only an overdue reminder explains itself with a due line',
      (tester) async {
    await pumpAgenda(
      tester,
      seedTasks: [_task('a', 'Workout', due: DateTime(2026, 3, 17, 9))],
      seedReminders: [
        _reminder('late', 'Missed it', due: DateTime(2026, 3, 17, 9)),
        _reminder('soon', 'Still ahead', due: DateTime(2026, 3, 17, 20)),
      ],
    );

    expect(find.byKey(const ValueKey('due-reminder-soon')), findsNothing);
    expect(find.byKey(const ValueKey('due-reminder-late')), findsOneWidget);
    // A task never carries one, overdue or not.
    expect(find.byKey(const ValueKey('due-task-a')), findsNothing);

    final due = tester.widget<Text>(
      find.byKey(const ValueKey('due-reminder-late')),
    );
    expect(due.style?.color, kPalette.reminderRing);
    // One red per row: not the app's generic danger colour.
    expect(due.style?.color, isNot(kPalette.danger));
  });

  testWidgets('ticking a task row writes through to the repository',
      (tester) async {
    await pumpAgenda(
      tester,
      seedTasks: [_task('a', 'Workout')],
      useFakeRepository: true,
    );

    await tester.tap(find.text('Workout'));
    await tester.pump();
    await tester.pump();

    expect(repository!.toggled, ['a']);
    expect(repository!.getById('a')!.isCompleted, isTrue);
  });

  testWidgets('tapping a reminder row opens its form sheet', (tester) async {
    await pumpAgenda(
      tester,
      seedReminders: [_reminder('r1', 'Lecture')],
    );

    expect(find.byType(ReminderFormSheet), findsNothing);

    await tester.tap(find.text('Lecture'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ReminderFormSheet), findsOneWidget);
  });

  testWidgets('past five rows, the rest are counted across both kinds',
      (tester) async {
    await pumpAgenda(
      tester,
      seedTasks: [
        for (var i = 0; i < 4; i++)
          _task('t$i', 'Task $i', due: DateTime(2026, 3, 17, 9 + i)),
      ],
      seedReminders: [
        for (var i = 0; i < 3; i++)
          _reminder('r$i', 'Reminder $i', due: DateTime(2026, 3, 17, 14 + i)),
      ],
    );

    // Five of seven shown, so the two latest reminders are counted instead.
    expect(find.text('+2 more on Tasks'), findsOneWidget);
    expect(find.text('Reminder 2'), findsNothing);
    expect(find.text('Task 0'), findsOneWidget);
  });

  testWidgets('a ticked task fills its ring rather than recolouring it',
      (tester) async {
    await pumpAgenda(
      tester,
      seedTasks: [_task('a', 'Workout')],
      useFakeRepository: true,
    );

    // Open: a ring drawn as an outline only.
    expect(_ring(tester, 'task-a').color, Colors.transparent);

    await tester.tap(find.text('Workout'));
    // Part-way through the 320ms fill, before `TaskFilter.today` drops the
    // completed row on the repository's next event — which is the only window
    // in which the ticked state is ever visible.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Workout'), findsNothing,
        reason: 'a ticked task leaves the Today filter');
  });

  testWidgets('a doubled text scale does not overflow a row', (tester) async {
    await pumpAgenda(
      tester,
      seedTasks: [_task('a', 'A task with a fairly long title on it')],
      seedReminders: [
        _reminder('r1', "Watch Dr.Bassant's Lecture",
            due: DateTime(2026, 3, 17, 9)),
      ],
      // A 393pt phone is the narrowest surface this card ever draws on, and
      // the overdue rows are two-line — the combination that overflows first.
      surface: const Size(393, 852),
      textScale: 2.0,
    );

    expect(tester.takeException(), isNull);
  });
}
