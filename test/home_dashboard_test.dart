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
// `Override` is not in flutter_riverpod.dart's own show-list in 3.4.x — it
// only comes through this leaf import.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import 'package:cotv/hive_registrar.g.dart';
import 'package:cotv/src/models/food_models.dart';
import 'package:cotv/src/models/habit.dart';
import 'package:cotv/src/models/reminder.dart';
import 'package:cotv/src/models/study_log.dart';
import 'package:cotv/src/models/subject.dart';
import 'package:cotv/src/models/task.dart';
import 'package:cotv/src/models/user_settings.dart';
import 'package:cotv/src/providers/clock_providers.dart';
import 'package:cotv/src/providers/notification_providers.dart';
import 'package:cotv/src/providers/nutrition_providers.dart';
import 'package:cotv/src/providers/reminder_providers.dart';
import 'package:cotv/src/providers/task_providers.dart';
import 'package:cotv/src/repositories/task_repository.dart';
import 'package:cotv/src/services/notification_service.dart';
import 'package:cotv/src/storage/local_storage.dart';
import 'package:cotv/src/ui/components/glass_card.dart';
import 'package:cotv/src/ui/home/home_screen.dart';
import 'package:cotv/src/ui/home/widgets/focus_tasks_card.dart';
import 'package:cotv/src/ui/home/widgets/home_search_bar.dart';
import 'package:cotv/src/ui/home/widgets/music_widget.dart';
import 'package:cotv/src/ui/home/widgets/nutrition_card.dart';
import 'package:cotv/src/ui/home/widgets/reminders_card.dart';
import 'package:cotv/src/ui/home/widgets/study_breakdown_card.dart';
import 'package:cotv/src/ui/home/widgets/welcome_header.dart';
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
  ///
  /// [now] overrides the pinned instant itself, for the rare test that
  /// needs a different one — Riverpod asserts if `currentMinuteProvider`
  /// were overridden twice, so this can't just be folded into [overrides].
  ///
  /// A bare card gets wrapped in a [SingleChildScrollView] so a card taller
  /// than the test surface overflows into a scroll rather than a render
  /// exception. [HomeScreen] cannot take that wrapper: it is a [ListView]
  /// of its own, and a viewport nested inside another scrollable's unbounded
  /// height throws "Vertical viewport was given unbounded height" before a
  /// frame is even drawn. It goes straight into the Scaffold body instead,
  /// where the bounded constraints a ListView needs are exactly what a
  /// Scaffold already hands its body.
  Future<void> pumpCard(
    WidgetTester tester,
    Widget child, {
    TaskRepository? repository,
    DateTime? now,
    List<Override> overrides = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentMinuteProvider.overrideWithValue(now ?? _now),
          notificationServiceProvider
              .overrideWithValue(_FakeNotificationService()),
          if (repository != null)
            taskRepositoryProvider.overrideWithValue(repository),
          ...overrides,
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: child is HomeScreen
                ? child
                : SingleChildScrollView(child: child),
          ),
        ),
      ),
    );
    // The repository streams yield their first value on a microtask.
    await tester.pump();
    await tester.pump();
    // HomeScreen stages its children behind RevealOnEntrance, each on its
    // own `Future.delayed` (up to 140ms). Left unfired, that Timer is still
    // pending when the test tears down and flutter_test fails the test over
    // it regardless of what the test itself asserted — 200ms clears every
    // delay HomeScreen schedules today with room to spare.
    await tester.pump(const Duration(milliseconds: 200));
  }

  group('focus tasks', () {
    testWidgets('an empty day says so rather than showing rows',
        (tester) async {
      await pumpCard(tester, const FocusTasksCard());

      expect(find.text('No tasks today.'), findsOneWidget);
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
      expect(find.text('No tasks today.'), findsOneWidget);
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

  group('reminders', () {
    testWidgets('the reminders card lists titles with their due labels',
        (tester) async {
      await pumpCard(tester, const RemindersCard());

      expect(find.text('Reminders'), findsOneWidget);
      expect(find.text('Workout'), findsOneWidget);
      expect(find.text("Watch Dr.Bassant's Lecture"), findsOneWidget);
    });

    testWidgets('an overdue reminder is coloured danger', (tester) async {
      // The dashboard's shared `_now` (17 March) predates both sample
      // reminders, which are seeded in late July — against it neither would
      // ever be overdue and this test would pass for the wrong reason. Pin
      // the clock to the same instant `test/reminders_test.dart` uses to
      // exercise `Reminder.isOverdue`, which sits after the "Workout"
      // sample's due time and before "Watch Dr.Bassant's Lecture"'s.
      await pumpCard(
        tester,
        const RemindersCard(),
        now: DateTime(2026, 7, 28, 12, 0),
      );

      // The sample "Workout" is dated in the past.
      final due =
          tester.widget<Text>(find.byKey(const ValueKey('due-sample-1')));
      expect(due.style?.color, kPalette.danger);
    });

    testWidgets('an empty reminder list says so', (tester) async {
      await pumpCard(
        tester,
        const RemindersCard(),
        overrides: [reminderListProvider.overrideWith(_EmptyReminders.new)],
      );

      expect(find.text('No reminders'), findsOneWidget);
    });
  });

  group('bento card frame', () {
    testWidgets('both Tasks and Reminders carry an edit pencil',
        (tester) async {
      for (final card in [const FocusTasksCard(), const RemindersCard()]) {
        await pumpCard(tester, card);
        expect(find.byIcon(PhLight.pencilSimple), findsOneWidget,
            reason: '${card.runtimeType} is missing its pencil');
      }
    });

    testWidgets('every bento card carries a title', (tester) async {
      for (final entry in {
        const FocusTasksCard(): 'Tasks',
        const RemindersCard(): 'Reminders',
        const StudyBreakdownCard(): 'Study time',
        const NutritionCard(): 'Nutrition',
      }.entries) {
        await pumpCard(tester, entry.key);
        expect(find.text(entry.value), findsOneWidget,
            reason: '${entry.key.runtimeType} lost its title');
      }
    });

    // Task 8's reframe onto HomeCardFrame silently dropped three things the
    // pre-reframe cards had: FocusTasksCard's hoverLift (its rows are each
    // their own control, so the card itself should still light up under a
    // pointer), NutritionCard's semanticLabel (a screen reader tapping the
    // card used to hear the calorie total and the affordance) and the
    // trailing divider under the last reminder. The three tests below pin
    // each of those back onto HomeCardFrame's passthrough.

    testWidgets(
        "FocusTasksCard's hoverLift survives the HomeCardFrame passthrough",
        (tester) async {
      await pumpCard(tester, const FocusTasksCard());

      final glassCard = tester.widget<GlassCard>(find.byType(GlassCard));
      expect(glassCard.hoverLift, isTrue,
          reason: 'the rows are individually interactive, so the card '
              'itself should still light up under a pointer');
    });

    testWidgets(
        "NutritionCard's semanticLabel survives the HomeCardFrame passthrough",
        (tester) async {
      await pumpCard(tester, const NutritionCard());

      final glassCard = tester.widget<GlassCard>(find.byType(GlassCard));
      expect(
        glassCard.semanticLabel,
        'Nutrition, 0 of 2000 kilocalories. Open the food logger.',
      );
    });

    testWidgets('no divider renders under the last reminder', (tester) async {
      await pumpCard(tester, const RemindersCard());

      // Two sample reminders, seeded by ReminderListController.build(): one
      // separator between them, and none trailing the last row.
      expect(find.byType(Divider), findsOneWidget);
    });
  });

  testWidgets('the homepage assembles header, search, music and four cards',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpCard(tester, const HomeScreen());

    expect(find.byType(WelcomeHeader), findsOneWidget);
    expect(find.byType(HomeSearchBar), findsOneWidget);
    expect(find.byType(MusicWidget), findsOneWidget);
    expect(find.byType(FocusTasksCard), findsOneWidget);
    expect(find.byType(RemindersCard), findsOneWidget);
    expect(find.byType(StudyBreakdownCard), findsOneWidget);
    expect(find.byType(NutritionCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a narrow window stacks the cards without overflowing',
      (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpCard(tester, const HomeScreen());

    expect(tester.takeException(), isNull);
  });

  // The restyle traded the frosted-glass card for a flat panel that is dim at
  // rest and lights under a pointer. What follows pins the parts of that a
  // human looking at the screen would catch and a widget test otherwise would
  // not: that the glass is actually gone, which card dims, and which way each
  // one grows.
  group('the card material', () {
    testWidgets('nothing on the page blurs its backdrop', (tester) async {
      await pumpCard(tester, const HomeScreen());

      expect(find.byType(BackdropFilter), findsNothing);
      // And so there is nothing left for a BackdropGroup to share.
      expect(find.byType(BackdropGroup), findsNothing);
    });

    testWidgets('a bento card dims at rest and the music card does not',
        (tester) async {
      await pumpCard(tester, const RemindersCard());
      expect(
        tester.widget<GlassCard>(find.byType(GlassCard)).idleOpacity,
        0.4,
        reason: 'a bento card recedes until a pointer finds it',
      );

      await pumpCard(tester, const MusicWidget());
      expect(
        tester.widget<GlassCard>(find.byType(GlassCard)).idleOpacity,
        isNull,
        reason: 'the now-playing card is read at a glance, not hunted for',
      );
    });


  });
}

class _EmptyReminders extends ReminderListController {
  @override
  List<Reminder> build() => const [];
}
