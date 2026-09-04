// Smoke test: verifies the app boots past the security gate into the
// adaptive shell, renders the daily schedule with its prayer bands and
// lockout banner, and can switch destinations.
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
import 'package:cotv/src/models/journal_entry.dart';
import 'package:cotv/src/models/schedule_item.dart';
import 'package:cotv/src/models/study_log.dart';
import 'package:cotv/src/models/subject.dart';
import 'package:cotv/src/models/task.dart';
import 'package:cotv/src/models/user_settings.dart';
import 'package:cotv/src/providers/notification_providers.dart';
import 'package:cotv/src/providers/security_providers.dart';
import 'package:cotv/src/providers/task_providers.dart';
import 'package:cotv/src/security/security_service.dart';
import 'package:cotv/src/services/notification_service.dart';
import 'package:cotv/src/storage/local_storage.dart';
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

  setUp(() async {
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
      Hive.openBox<ScheduleItem>(HiveBoxes.scheduleItems),
      Hive.openBox<JournalEntry>(HiveBoxes.journalEntries),
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
    await Hive.deleteFromDisk();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// Pumps the app and flushes the lock controller's microtasks plus the
  /// staggered entrance animations, so no timers are pending at teardown.
  ///
  /// Sizes the surface to an iPhone 14 Pro (393x852pt) rather than the
  /// 800x600 default, so the compact layout under test is the one the app
  /// actually ships to.
  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
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

  testWidgets('boots into the daily schedule', (tester) async {
    await pumpApp(tester);

    // The bottom navigation destinations. The phone bar is icon-only —
    // seven labels do not fit a 393pt phone — so each destination is
    // addressed by the name it keeps as its tooltip and semantics label
    // rather than by visible text.
    expect(find.byTooltip('Schedule'), findsOneWidget);
    expect(find.byTooltip('Tasks'), findsOneWidget);
    expect(find.byTooltip('Study'), findsOneWidget);
    expect(find.byTooltip('Prayers'), findsOneWidget);

    // The schedule's own controls.
    expect(find.text('Now'), findsOneWidget);
    expect(find.text('TODAY'), findsOneWidget);
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
