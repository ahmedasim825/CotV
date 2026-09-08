// Smoke test: verifies the app boots past the security gate into the
// adaptive shell, renders the home dashboard with its lockout banner,
// and can switch destinations.
//
// The calendar/notification/biometric layers talk to native plugins that
// aren't available under flutter_test, so this deliberately doesn't assert
// on their state — a real device is required to exercise those. Hive is
// real but backed by a temp directory.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import 'package:cotv/hive_registrar.g.dart';
import 'package:cotv/main.dart';
import 'package:cotv/src/models/active_study_session.dart';
import 'package:cotv/src/models/chat_message.dart';
import 'package:cotv/src/models/habit.dart';
import 'package:cotv/src/models/study_log.dart';
import 'package:cotv/src/models/subject.dart';
import 'package:cotv/src/models/task.dart';
import 'package:cotv/src/models/user_settings.dart';
import 'package:cotv/src/providers/notification_providers.dart';
import 'package:cotv/src/providers/security_providers.dart';
import 'package:cotv/src/providers/task_providers.dart';
import 'package:cotv/src/security/security_service.dart';
import 'package:cotv/src/services/notification_service.dart';
import 'package:cotv/src/providers/chat_session_providers.dart';
import 'package:cotv/src/storage/app_database.dart';
import 'package:cotv/src/storage/local_storage.dart';
import 'package:cotv/src/ui/home/widgets/milo_orb.dart';
import 'package:cotv/src/ui/tasks/task_list_view.dart';

/// Avoids touching the real `flutter_secure_storage` platform channel
/// (unavailable under `flutter_test`) by always reporting biometrics as
/// disabled, which is enough for [AppLockController.build] to resolve to
/// [AppLockStatus.unlocked] without any plugin call.
class _FakeSecurityService extends SecurityService {
  @override
  Future<bool> isBiometricEnabled() async => false;
}

/// Saving a task reconciles its reminder through [NotificationService],
/// which reaches a platform channel that never answers under
/// `flutter_test`. The save would then never resolve, leaving the button's
/// spinner animating and `pumpAndSettle` unable to settle. This stands in
/// for the plugin so the write path completes.
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

void main() {
  late Directory tempDir;

  late AppDatabase database;

  setUp(() async {
    // The app opens this in main(); tests get an in-memory one with the
    // same schema, so the chat tables exist without a file to clean up.
    database = AppDatabase.openAt(':memory:');
    // The shell's schedule and task panes read Hive boxes on first build,
    // so they have to exist before the widget tree is pumped.
    tempDir = await Directory.systemTemp.createTemp('cotv_widget_test_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapters();
    }
    await Future.wait([
      Hive.openBox<Task>(HiveBoxes.tasks),
      Hive.openBox<Habit>(HiveBoxes.habits),
      Hive.openBox<UserSettings>(HiveBoxes.userSettings),
      // The shell reconciles a leftover study session on launch, and
      // Milo's context reads the durable transcript, so these have to
      // be open before the tree is pumped too.
      Hive.openBox<Subject>(HiveBoxes.subjects),
      Hive.openBox<StudyLog>(HiveBoxes.studyLogs),
      Hive.openBox<ChatMessage>(HiveBoxes.chatMessages),
      Hive.openBox<ActiveStudySession>(HiveBoxes.activeStudySession),
    ]);
  });

  tearDown(() async {
    database.dispose();
    await Hive.deleteFromDisk();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// Pumps the app and flushes the lock controller's microtasks plus the
  /// staggered entrance animations, so no timers are pending at teardown.
  ///
  /// Sizes the surface to an iPhone 14 Pro (393x852pt) rather than the
  /// 800x600 default, so the compact layout under test is the one the app
  /// actually ships to. [logicalSize] overrides that for a test that needs
  /// the whole scroll extent built at once.
  Future<void> pumpApp(
    WidgetTester tester, {
    Size logicalSize = const Size(393, 852),
  }) async {
    tester.view.physicalSize = logicalSize * 3.0;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          securityServiceProvider.overrideWithValue(_FakeSecurityService()),
          notificationServiceProvider
              .overrideWithValue(_FakeNotificationService()),
        ],
        child: const PrayerLockoutApp(),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
  }

  /// Pumps frames until [condition] holds.
  ///
  /// Used instead of `pumpAndSettle` anywhere the task form is on screen:
  /// it autofocuses its title field, and a focused text field's cursor
  /// blinks forever, so the tree never settles. Pumping in real-time slices
  /// also lets Hive's actual disk writes land, which a fake-clock advance
  /// alone would not wait for.
  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition, {
    int maxFrames = 150,
  }) async {
    for (var frame = 0; frame < maxFrames; frame++) {
      if (condition()) return;
      await tester.pump(const Duration(milliseconds: 50));
    }
    fail('Condition still unmet after $maxFrames frames.');
  }

  testWidgets('boots into the home dashboard', (tester) async {
    await pumpApp(tester);

    // The bottom navigation destinations. The phone bar is icon-only —
    // six labels do not fit a 393pt phone — so each destination is
    // addressed by the name it keeps as its tooltip and semantics label
    // rather than by visible text.
    expect(find.byTooltip('Home'), findsOneWidget);
    expect(find.byTooltip('Tasks'), findsOneWidget);
    expect(find.byTooltip('Study'), findsOneWidget);
    expect(find.byTooltip('Prayers'), findsOneWidget);

    // Schedule and Journal are gone entirely, not merely deselected.
    expect(find.byTooltip('Schedule'), findsNothing);
    expect(find.byTooltip('Journal'), findsNothing);

    // The dashboard's own content, above the fold on a 393x852 phone. The
    // cards below it are covered by the next test, which gives the surface
    // enough height to build all of them at once — a ListView only builds
    // what it can show, and dragging one leaves a ballistic scroll timer
    // that never settles against the orb's endless breathing animation.
    expect(find.byType(MiloOrbWidget), findsOneWidget);
    expect(find.textContaining('Ahmed'), findsOneWidget);
    expect(find.text('NEXT PRAYER'), findsOneWidget);
  });

  testWidgets('the dashboard renders every card', (tester) async {
    // Tall enough for the whole column, so nothing has to be scrolled into
    // existence. Still 393pt wide, so this is the compact single-column
    // layout rather than the two-up one.
    await pumpApp(tester, logicalSize: const Size(393, 2400));

    expect(find.text('NEXT PRAYER'), findsOneWidget);
    expect(find.text("Today's focus"), findsOneWidget);
    expect(find.text('Study today'), findsOneWidget);
    expect(find.text('Nutrition'), findsOneWidget);
    expect(find.text('Quick actions'), findsOneWidget);

    // Nothing has been logged in this fresh profile, so every card that
    // counts something renders its neutral line rather than a number it
    // cannot back. Four zeros in the strip, or four invented values, would
    // both pass a looser assertion than this one.
    expect(find.text('Nothing tracked yet today'), findsOneWidget);
    expect(find.text('No tasks today'), findsOneWidget);
    expect(find.text('Nothing logged today'), findsOneWidget);
    expect(find.text('Nothing logged yet'), findsOneWidget);
    expect(find.text('Talk to Milo'), findsOneWidget);

    // The removed quick action must not have survived anywhere.
    expect(find.textContaining('Journal'), findsNothing);
  });

  testWidgets('the dashboard reflows to two columns when wide', (tester) async {
    // Past the 600pt medium breakpoint, so the rail replaces the bottom bar
    // and the study and nutrition cards pair up. The pairing puts a
    // stretch-aligned Row inside a ListView, where height is unbounded — it
    // throws without the IntrinsicHeight around it, so this asserts the
    // layout actually builds rather than only that the text is present.
    await pumpApp(tester, logicalSize: const Size(1100, 2000));

    expect(tester.takeException(), isNull);
    expect(find.byType(IntrinsicHeight), findsOneWidget);
    expect(find.text('Study today'), findsOneWidget);
    expect(find.text('Nutrition'), findsOneWidget);

    // The rail shows labels the icon-only phone bar does not.
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Prayers'), findsOneWidget);
    expect(find.text('Schedule'), findsNothing);
    expect(find.text('Journal'), findsNothing);
  });

  testWidgets('renders the prayer lockout banner', (tester) async {
    await pumpApp(tester);

    // Either state of the banner names a prayer and offers a focus action.
    expect(
      find.textContaining(RegExp(r'Focus until adhan|Start prayer focus')),
      findsOneWidget,
    );
  });

  testWidgets('switches to the task list and opens the form sheet',
      (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byTooltip('Tasks'));
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsWidgets);
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Priority'), findsWidgets);

    await tester.tap(find.text('Task'));
    await pumpUntil(tester, () => find.text('New task').evaluate().isNotEmpty);

    expect(find.text('New task'), findsOneWidget);
    expect(find.text('What needs doing?'), findsOneWidget);
  });

  testWidgets('task writes flow back into the list reactively',
      (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byTooltip('Tasks'));
    await tester.pumpAndSettle();

    // An undated task lands under Upcoming.
    await tester.tap(find.text('Upcoming'));
    await tester.pumpAndSettle();

    expect(find.text('Read tafsir'), findsNothing);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(TaskListView)),
    );
    final tasks = container.read(taskListProvider.notifier);
    final task = Task(id: 'test-task-1', title: 'Read tafsir');

    // Hive writes to a real file, and that I/O completes on the real event
    // loop — which the fake-async zone `testWidgets` runs in would
    // otherwise starve. `runAsync` steps outside it so the write can land.
    await tester.runAsync(() => tasks.addTask(task));
    await pumpUntil(
      tester,
      () => find.text('Read tafsir').evaluate().isNotEmpty,
    );

    // Nothing re-read the box by hand: the write travelled repository ->
    // Hive -> watchAll() -> visibleTasksProvider -> this list.
    expect(find.text('Read tafsir'), findsOneWidget);

    await tester.runAsync(() => tasks.deleteTask(task.id));
    await pumpUntil(
      tester,
      () => find.text('Read tafsir').evaluate().isEmpty,
    );

    expect(find.text('Read tafsir'), findsNothing);
  });

  testWidgets('switches to the prayers overview', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byTooltip('Prayers'));
    await tester.pumpAndSettle();

    expect(find.text('Prayer times'), findsOneWidget);
    expect(find.text('Fajr'), findsWidgets);
  });
}
