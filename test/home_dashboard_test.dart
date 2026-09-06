// Tests for the dashboard cards now that they read providers rather than
// the mock constants they used to declare.
//
// Two things are being pinned. First, that absence renders as the neutral
// line rather than as a fiction — this is the regression that matters,
// because the failure mode it replaces (four invented tasks, a 12-day
// streak nobody earned) looked entirely healthy. Second, that a tick on the
// dashboard reaches the repository, so Home and the Tasks screen cannot
// disagree about what is done.
//
// Hive is real, backed by a temp directory, so these exercise the actual
// provider graph rather than a stand-in for it. Every write from inside a
// test body goes through `tester.runAsync`: Hive's I/O completes on the
// real event loop, which the fake-async zone `testWidgets` runs in would
// otherwise starve, and the await would simply never return.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import 'package:cotv/hive_registrar.g.dart';
import 'package:cotv/src/models/food_models.dart';
import 'package:cotv/src/models/habit.dart';
import 'package:cotv/src/models/study_log.dart';
import 'package:cotv/src/models/subject.dart';
import 'package:cotv/src/models/task.dart';
import 'package:cotv/src/models/user_settings.dart';
import 'package:cotv/src/providers/clock_providers.dart';
import 'package:cotv/src/providers/notification_providers.dart';
import 'package:cotv/src/providers/nutrition_providers.dart';
import 'package:cotv/src/providers/task_providers.dart';
import 'package:cotv/src/repositories/task_repository.dart';
import 'package:cotv/src/services/notification_service.dart';
import 'package:cotv/src/storage/local_storage.dart';
import 'package:cotv/src/ui/home/widgets/focus_tasks_card.dart';
import 'package:cotv/src/ui/home/widgets/nutrition_card.dart';
import 'package:cotv/src/ui/home/widgets/streak_bar.dart';
import 'package:cotv/src/ui/home/widgets/study_breakdown_card.dart';
import 'package:cotv/src/ui/theme/app_theme.dart';

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

/// Stands in for Hive on the one test that writes from inside the widget
/// tree.
///
/// A tap on a row starts its write inside `testWidgets`' fake-async zone,
/// and Hive finishes that write on the real event loop — which the fake
/// zone starves, so the tap never returns. Everything else here uses real
/// boxes, because their writes happen before the tree is pumped and can be
/// wrapped in `runAsync`; this one cannot.
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
  Task? getById(String id) =>
      _tasks.where((task) => task.id == id).firstOrNull;

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
    _tasks[index] = _tasks[index].copyWith(
      isCompleted: !_tasks[index].isCompleted,
    );
    _changes.add(List.unmodifiable(_tasks));
  }
}

/// Mid-afternoon, so a task due at 18:00 is still ahead and one at 09:00 is
/// overdue — both of which the Today filter keeps.
final _now = DateTime(2026, 3, 17, 14, 30);

Task _task(
  String id,
  String title, {
  DateTime? due,
  TaskPriority priority = TaskPriority.medium,
}) =>
    Task(
      id: id,
      title: title,
      dueDate: due ?? DateTime(2026, 3, 17, 18),
      priority: priority,
      createdAt: DateTime(2026, 3, 1),
    );

void main() {
  late Directory tempDir;
  late Box<Task> tasks;
  late Box<StudyLog> studyLogs;
  late Box<Subject> subjects;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cotv_home_test_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapters();
    }
    tasks = await Hive.openBox<Task>(HiveBoxes.tasks);
    studyLogs = await Hive.openBox<StudyLog>(HiveBoxes.studyLogs);
    subjects = await Hive.openBox<Subject>(HiveBoxes.subjects);
    await Hive.openBox<Habit>(HiveBoxes.habits);
    await Hive.openBox<UserSettings>(HiveBoxes.userSettings);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// Pumps [child] with the clock pinned, so nothing here depends on the
  /// wall clock and no one-second ticker is left running at teardown.
  Future<void> pumpCard(
    WidgetTester tester,
    Widget child, {
    TaskRepository? repository,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentMinuteProvider.overrideWithValue(_now),
          notificationServiceProvider
              .overrideWithValue(_FakeNotificationService()),
          if (repository != null)
            taskRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          theme: buildAppTheme(AppThemeVariant.sanctuary),
          home: Scaffold(
            body: SingleChildScrollView(child: child),
          ),
        ),
      ),
    );
    // The repository streams yield their first value on a microtask.
    await tester.pump();
    await tester.pump();
  }

  group('focus tasks', () {
    testWidgets('an empty day says so rather than showing rows',
        (tester) async {
      await pumpCard(tester, const FocusTasksCard());

      expect(find.text('No tasks today'), findsOneWidget);
      expect(find.text('All clear'), findsOneWidget);
    });

    testWidgets("renders today's tasks, highest priority first",
        (tester) async {
      await tester.runAsync(
        () => tasks.putAll({
          'a': _task('a', 'Review pathology', priority: TaskPriority.low),
          'b': _task('b', 'Dissection notes', priority: TaskPriority.high),
          // Tomorrow: outside Today, so it must not appear.
          'c': _task('c', 'Book the rotation', due: DateTime(2026, 3, 18, 10)),
        }),
      );
      await pumpCard(tester, const FocusTasksCard());

      expect(find.text('Dissection notes'), findsOneWidget);
      expect(find.text('Review pathology'), findsOneWidget);
      expect(find.text('Book the rotation'), findsNothing);
      expect(find.text('2 left'), findsOneWidget);

      final titles = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .toList();
      expect(
        titles.indexOf('Dissection notes') < titles.indexOf('Review pathology'),
        isTrue,
        reason: 'high priority should sort above low',
      );
    });

    testWidgets('ticking a row writes through to the repository',
        (tester) async {
      final repository =
          _InMemoryTaskRepository([_task('a', 'Dissection notes')]);
      addTearDown(repository.dispose);

      await pumpCard(tester, const FocusTasksCard(), repository: repository);
      expect(find.text('Dissection notes'), findsOneWidget);

      await tester.tap(find.text('Dissection notes'));
      await tester.pump();
      await tester.pump();

      expect(repository.toggled, ['a']);
      expect(repository.getById('a')!.isCompleted, isTrue);
      // And the card followed the repository rather than holding its own
      // copy of what is done: a completed task leaves the Today filter.
      expect(find.text('Dissection notes'), findsNothing);
      expect(find.text('No tasks today'), findsOneWidget);
    });

    testWidgets('past the shortlist, the rest are counted not listed',
        (tester) async {
      await tester.runAsync(
        () => tasks.putAll({
          for (var i = 0; i < 7; i++) 't$i': _task('t$i', 'Task number $i'),
        }),
      );
      await pumpCard(tester, const FocusTasksCard());

      expect(find.text('+2 more on Tasks'), findsOneWidget);
      expect(find.text('7 left'), findsOneWidget);
      expect(find.text('Task number 6'), findsNothing);
    });
  });

  group('study breakdown', () {
    testWidgets('a day with no sessions shows a zero ring and says so',
        (tester) async {
      await pumpCard(tester, const StudyBreakdownCard());

      expect(find.text('Nothing logged today'), findsOneWidget);
      expect(find.text('0m'), findsOneWidget);
    });

    testWidgets('a logged session names its subject and its minutes',
        (tester) async {
      await tester.runAsync(() async {
        await subjects.put(
          's1',
          Subject(id: 's1', name: 'Anatomy', colorValue: 0xFF7B8FCB),
        );
        await studyLogs.put(
          'l1',
          StudyLog(
            id: 'l1',
            subjectId: 's1',
            subjectName: 'Anatomy',
            durationMinutes: 90,
            timestamp: _now,
          ),
        );
      });
      await pumpCard(tester, const StudyBreakdownCard());

      expect(find.text('Nothing logged today'), findsNothing);
      expect(find.text('Anatomy'), findsOneWidget);
      // Once in the ring, once on the subject row.
      expect(find.text('1h 30m'), findsNWidgets(2));
    });
  });

  group('streak strip', () {
    testWidgets('four zeros collapse into one line', (tester) async {
      await pumpCard(tester, const StreakBar());

      expect(find.text('Nothing tracked yet today'), findsOneWidget);
      expect(find.text('day streak'), findsNothing);
    });

    testWidgets('one real number brings the cells back', (tester) async {
      await tester.runAsync(
        () => studyLogs.put(
          'l1',
          StudyLog(
            id: 'l1',
            subjectId: 's1',
            subjectName: 'Anatomy',
            durationMinutes: 45,
            timestamp: _now,
          ),
        ),
      );
      await pumpCard(tester, const StreakBar());

      expect(find.text('Nothing tracked yet today'), findsNothing);
      expect(find.text('45m'), findsOneWidget);
      expect(find.text('studied'), findsOneWidget);
      // The water cell is gone, not blanked.
      expect(find.text('water'), findsNothing);
    });
  });

  group('nutrition', () {
    testWidgets('an unlogged day says so under the ring', (tester) async {
      await pumpCard(tester, const NutritionCard());

      expect(find.text('Nothing logged yet'), findsOneWidget);
    });

    testWidgets('a logged meal replaces the line with the totals',
        (tester) async {
      await pumpCard(tester, const NutritionCard());

      // Written through the notifier rather than the box: the food log is
      // in-memory plus optional Supabase sync, with no Hive box behind it.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(NutritionCard)),
      );
      await container.read(dailyNutritionProvider.notifier).log(
            LoggedFood(
              id: 'f1',
              name: 'Oats',
              meal: MealSlot.breakfast,
              servings: 1,
              grams: 100,
              totals: const NutritionTotals(
                calories: 380,
                protein: 13,
                carbs: 67,
                fat: 7,
                sodium: 0,
                potassium: 0,
              ),
              loggedAt: _now,
            ),
          );
      await tester.pump();

      expect(find.text('Nothing logged yet'), findsNothing);
      expect(find.text('380'), findsOneWidget);
    });
  });
}
