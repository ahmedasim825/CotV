// Smoke test: verifies the app boots past the security gate into the
// adaptive shell, renders the home dashboard, and can switch destinations.
//
// The calendar/notification/biometric layers talk to native plugins that
// aren't available under flutter_test, so this deliberately doesn't assert
// on their state — a real device is required to exercise those. Hive is
// real but backed by a temp directory.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
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
import 'package:cotv/src/providers/milo_providers.dart';
import 'package:cotv/src/providers/notification_providers.dart';
import 'package:cotv/src/providers/security_providers.dart';
import 'package:cotv/src/providers/task_providers.dart';
import 'package:cotv/src/security/security_service.dart';
import 'package:cotv/src/services/milo/milo_credentials.dart';
import 'package:cotv/src/services/notification_service.dart';
import 'package:cotv/src/providers/chat_session_providers.dart';
import 'package:cotv/src/storage/app_database.dart';
import 'package:cotv/src/storage/local_storage.dart';
import 'package:cotv/src/ui/home/widgets/milo_orb.dart';
import 'package:cotv/src/ui/milo/milo_assistant_screen.dart';
import 'package:cotv/src/ui/shell/sidebar.dart';
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
  /// the whole scroll extent built at once. [extraOverrides] adds to, rather
  /// than replaces, the three overrides every test in this file needs —
  /// for a test that also has to touch a Milo provider.
  Future<void> pumpApp(
    WidgetTester tester, {
    Size logicalSize = const Size(393, 852),
    List<Override> extraOverrides = const [],
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
          ...extraOverrides,
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
    //
    // The orb itself lives in the sidebar dock, which only mounts past the
    // navigation-rail breakpoint and so is absent at this compact width.
    // The greeting is a different story: WelcomeHeader is wired into every
    // layout HomeScreen renders, compact included, so it has to be on
    // screen here too. This is the assertion DashboardHeader carried before
    // Task 5 deleted it, restored now against the widget that replaced it.
    expect(find.byType(MiloOrbWidget), findsNothing);
    expect(find.text('Welcome, Ahmed'), findsOneWidget);
  });

  testWidgets('the dashboard renders every card', (tester) async {
    // Tall enough for the whole column, so nothing has to be scrolled into
    // existence. Still 393pt wide, so this is the compact single-column
    // layout rather than the two-up one.
    await pumpApp(tester, logicalSize: const Size(393, 2400));

    expect(find.text('Welcome, Ahmed'), findsOneWidget);
    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('Reminders'), findsOneWidget);
    expect(find.text('Study time'), findsOneWidget);
    expect(find.text('Nutrition'), findsOneWidget);

    // Nothing has been logged in this fresh profile, so every card that
    // counts something renders its neutral line rather than a number it
    // cannot back. A logged value here, or an invented one, would both pass
    // a looser assertion than this one.
    expect(find.text('No tasks today'), findsOneWidget);
    expect(find.text('Nothing logged today'), findsOneWidget);
    expect(find.text('Nothing logged yet'), findsOneWidget);
  });

  testWidgets('the dashboard reflows to two columns when wide', (tester) async {
    // Past the 600pt medium breakpoint, so the rail replaces the bottom bar
    // and the bento pairs up into its 2x2: Tasks with Reminders, Study time
    // with Nutrition. Each pairing puts a stretch-aligned Row inside a
    // ListView, where height is unbounded — it throws without the
    // IntrinsicHeight around it, so this asserts the layout actually builds
    // rather than only that the text is present.
    await pumpApp(tester, logicalSize: const Size(1100, 2000));

    expect(tester.takeException(), isNull);
    expect(find.byType(IntrinsicHeight), findsNWidgets(2));
    expect(find.text('Study time'), findsOneWidget);
    expect(find.text('Nutrition'), findsOneWidget);

    // The rail shows labels the icon-only phone bar does not.
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Prayers'), findsOneWidget);
    expect(find.text('Schedule'), findsNothing);
    expect(find.text('Journal'), findsNothing);
  });

  testWidgets('no floating Milo pill is left on any destination',
      (tester) async {
    // The launcher used to be Positioned in the shell's Stack, so it sat
    // over the bottom-left corner of every screen, not just Home. It is
    // addressed by its bare "Milo" label — the type is gone, and the
    // drawer it opened is still there, so neither is a witness that it was
    // removed. At this compact width the sidebar dock that legitimately
    // carries that label today has not mounted either, so the absence here
    // still means what it always has.
    //
    // Tall enough to build the whole dashboard, so this also covers the
    // quick-action pill that used to replace the launcher — it is gone too,
    // superseded by the sidebar's Milo dock, and left nothing bearing the
    // bare label behind.
    await pumpApp(tester, logicalSize: const Size(393, 2400));

    expect(find.text('Milo'), findsNothing);

    // And on a destination that never had a launcher or a quick action to
    // replace it.
    await tester.tap(find.byTooltip('Tasks'));
    await tester.pumpAndSettle();

    expect(find.text('Milo'), findsNothing);
  });

  testWidgets(
      "the compact bar's Milo launcher opens the end drawer",
      (tester) async {
    // MiloDock — the sidebar's own entry point — mounts only past the
    // navigation-rail breakpoint, so at this compact (393pt) width the
    // bottom bar's own launcher is the only way in. miloSecretsProvider is
    // overridden so MiloAssistantScreen's build doesn't reach the Keychain
    // platform channel, unavailable under flutter_test — the same reason
    // milo_panel_test.dart overrides it.
    await pumpApp(
      tester,
      extraOverrides: [
        miloSecretsProvider.overrideWith(
          (ref) async => const MiloSecrets(groqApiKey: 'gsk_test'),
        ),
      ],
    );

    expect(find.byType(MiloAssistantScreen), findsNothing);
    expect(find.byTooltip('Milo'), findsOneWidget);

    await tester.tap(find.byTooltip('Milo'));
    // One frame, not pumpAndSettle or a multi-frame wait: the drawer's
    // content mounts on the very first frame of its open animation (it is
    // merely translated offscreen before that finishes), so one pump is
    // enough to find it — and the orb's breath controller repeats forever,
    // so a widget tree that ever grows to contain it would hang under
    // pumpAndSettle. A longer wait here isn't just unnecessary: at this
    // compact width WelcomeHeader is a known pre-existing overflow risk a
    // few hundred milliseconds in (unrelated to Milo — see the report), so
    // the minimal pump also sidesteps that.
    await tester.pump();

    expect(find.byType(MiloAssistantScreen), findsOneWidget);
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

  group('sidebar collapse and hide', () {
    // Past the navigation-rail breakpoint, same width
    // "the dashboard reflows to two columns when wide" uses — the sidebar
    // (and its Milo dock, orb included) mounts only here. `pump()`, never
    // `pumpAndSettle`: the orb's breath controller repeats forever.

    testWidgets('collapsing drops the labels but keeps the icons',
        (tester) async {
      await pumpApp(tester, logicalSize: const Size(1100, 2000));

      expect(find.text('Home'), findsOneWidget);
      expect(find.byTooltip('Home'), findsNothing);

      await tester.tap(find.byTooltip('Collapse sidebar'));
      await tester.pump();

      expect(find.text('Home'), findsNothing);
      expect(find.byTooltip('Home'), findsOneWidget);
    });

    testWidgets(
        'hiding removes the sidebar and shows the restore control, which '
        'brings it back', (tester) async {
      await pumpApp(tester, logicalSize: const Size(1100, 2000));

      expect(find.byType(Sidebar), findsOneWidget);
      expect(find.byTooltip('Show sidebar'), findsNothing);

      await tester.tap(find.byTooltip('Hide sidebar'));
      await tester.pump();

      expect(find.byType(Sidebar), findsNothing);
      expect(find.byTooltip('Show sidebar'), findsOneWidget);

      await tester.tap(find.byTooltip('Show sidebar'));
      await tester.pump();

      expect(find.byType(Sidebar), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
    });
  });
}
