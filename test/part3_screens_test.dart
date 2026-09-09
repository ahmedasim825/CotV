// Smoke tests for the Part 3 screens: the habit grid, and the settings
// screen's app-lock section.
//
// Follows the same harness as `widget_test.dart`: real Hive backed by a
// temp directory, with the plugin-backed services faked out because
// `flutter_test` has no platform channels to answer them.
//
// Writes go through the repositories inside `tester.runAsync`, never by
// tapping a Save button. Hive's disk I/O completes on the real event loop,
// which the fake-async zone `testWidgets` runs in would otherwise starve —
// a UI-triggered write would leave its future pending forever and the sheet
// stuck on its spinner. So the taps here cover navigation and presentation,
// and the seeded writes cover that a repository change reaches the screen
// on its own.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:local_auth/local_auth.dart';

import 'package:cotv/hive_registrar.g.dart';
import 'package:cotv/main.dart';
import 'package:cotv/src/models/active_study_session.dart';
import 'package:cotv/src/models/chat_message.dart';
import 'package:cotv/src/models/habit.dart';
import 'package:cotv/src/models/reminder.dart';
import 'package:cotv/src/models/study_log.dart';
import 'package:cotv/src/models/subject.dart';
import 'package:cotv/src/models/task.dart';
import 'package:cotv/src/models/user_settings.dart';
import 'package:cotv/src/providers/clock_providers.dart';
import 'package:cotv/src/providers/habit_providers.dart';
import 'package:cotv/src/providers/notification_providers.dart';
import 'package:cotv/src/providers/reminder_providers.dart';
import 'package:cotv/src/providers/security_providers.dart';
import 'package:cotv/src/security/security_service.dart';
import 'package:cotv/src/services/notification_service.dart';
import 'package:cotv/src/providers/chat_session_providers.dart';
import 'package:cotv/src/storage/app_database.dart';
import 'package:cotv/src/storage/local_storage.dart';
import 'package:cotv/src/ui/app_shell.dart';
import 'package:cotv/src/ui/habits/habit_form_sheet.dart';
import 'package:cotv/src/ui/habits/widgets/habit_tile.dart';
import 'package:cotv/src/ui/theme/app_theme.dart';

/// Stands in for every `local_auth` / `flutter_secure_storage` call the
/// security screen makes, reporting a Face ID device with app lock off —
/// the state a first launch is actually in.
class _FakeSecurityService extends SecurityService {
  @override
  Future<bool> isBiometricEnabled() async => false;

  @override
  Future<void> setBiometricEnabled(bool enabled) async {}

  @override
  Future<bool> isDeviceSupported() async => true;

  @override
  Future<bool> canCheckBiometrics() async => true;

  @override
  Future<List<BiometricType>> availableBiometrics() async =>
      const [BiometricType.face];
}

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
    tempDir = await Directory.systemTemp.createTemp('cotv_part3_test_');
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
    await Hive.close();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows can hold the box file briefly after close. This is a temp
        // directory; failing to remove it must not fail the run.
      }
    }
  });

  /// Pumps the app at iPhone 14 Pro size and flushes the lock controller's
  /// microtasks plus the staggered entrance animations.
  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1179, 2556);
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
  /// Used instead of `pumpAndSettle` wherever a form is on screen: an
  /// autofocused text field's cursor blinks forever, so the tree never
  /// settles.
  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition, {
    int maxFrames = 200,
  }) async {
    for (var frame = 0; frame < maxFrames; frame++) {
      if (condition()) return;
      await tester.pump(const Duration(milliseconds: 50));
    }
    fail('Condition still unmet after $maxFrames frames.');
  }

  /// Waits for [condition], then pumps out the remaining route or sheet
  /// transition.
  ///
  /// A sheet is findable from the first frame of its slide-up, when it is
  /// still below the bottom of the screen — tapping anything in it then
  /// misses. The extra frames land it in its resting position.
  Future<void> pumpUntilPresented(
    WidgetTester tester,
    bool Function() condition,
  ) async {
    await pumpUntil(tester, condition);
    await tester.pump(const Duration(milliseconds: 600));
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(AppShell)));

  // Task 3 (the collapsible sidebar) dropped the Habits row from AppShell's
  // navigation. Task 7 restored it as the third segment of the Tasks
  // screen, so these now get there through the Tasks tab and the segmented
  // control rather than a "Habits" tooltip of their own.
  group('habits', () {
    /// [pumpApp] renders at an iPhone 14 Pro's logical size, which is
    /// [WindowSize.compact] — [AppShell] shows the icon-only bottom bar
    /// there, not the sidebar, so `Tasks` is still reachable by tooltip.
    /// (The sidebar's Milo dock renders an orb whose breath controller
    /// never settles; the bottom bar carries no such widget, so
    /// `pumpAndSettle` is safe here the same way it is for the settings
    /// group below.)
    Future<void> openHabitsSegment(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Tasks'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Habits'));
      await tester.pumpAndSettle();
    }

    testWidgets('opens the habit form sheet from the grid', (tester) async {
      await pumpApp(tester);
      await openHabitsSegment(tester);

      expect(
        find.text('No habits yet.\nAdd one and it starts counting from today.'),
        findsOneWidget,
      );

      // The quick-add button. The bar is icon-only, so this no longer
      // has to be told apart from a "Habits" navigation label.
      await tester.tap(find.text('Habit'));
      await pumpUntilPresented(
        tester,
        () => find.byType(HabitFormSheet).evaluate().isNotEmpty,
      );

      expect(find.text('New habit'), findsOneWidget);
      expect(find.text('What do you want to keep up?'), findsOneWidget);
      expect(find.text('Daily'), findsOneWidget);
      expect(find.text('Weekly'), findsOneWidget);
      expect(find.text('Add habit'), findsOneWidget);
    });

    testWidgets('a stored habit renders, and completing it updates the summary',
        (tester) async {
      await pumpApp(tester);
      await openHabitsSegment(tester);

      final habits = containerOf(tester).read(habitListProvider.notifier);
      final habit = Habit(id: 'habit-1', title: 'Dhikr');

      await tester.runAsync(() => habits.addHabit(habit));
      await pumpUntil(tester, () => find.text('Dhikr').evaluate().isNotEmpty);

      // Nothing re-read the box by hand: the write travelled repository ->
      // Hive -> watchAll() -> habitListProvider -> this grid.
      expect(find.text('Dhikr'), findsOneWidget);
      expect(find.text('Every day'), findsOneWidget);
      expect(find.text('0/1'), findsOneWidget);

      await tester.runAsync(
        () => habits.toggleCompletedOn(habit.id, DateTime.now()),
      );
      await pumpUntil(tester, () => find.text('1/1').evaluate().isNotEmpty);

      expect(find.text('1/1'), findsOneWidget);
      // Scoped to the tile: the summary strip renders a bare '1' twice on
      // its own, so an unscoped finder would pass with no badge at all.
      expect(
        find.descendant(
          of: find.byType(HabitTile),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
    });
  });

  group('reminders', () {
    testWidgets(
      'reminder due label reacts to currentMinuteProvider clock, not wall clock',
      (tester) async {
        // A reminder due at 3pm on March 15, 2027 — a date in the future
        // relative to the real wall clock (this suite runs around
        // 2026-09-09). That gap matters for the second half below: it is
        // what makes a reverted `isOverdue(DateTime.now())` disagree with
        // the pinned-clock implementation instead of accidentally agreeing.
        final dueTime = DateTime(2027, 3, 15, 15, 0);

        // First pump: app with clock at before-due time (12pm, same day).
        tester.view.physicalSize = const Size(1179, 2556);
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
              // Before due time: 12pm.
              currentMinuteProvider
                  .overrideWithValue(DateTime(2027, 3, 15, 12, 0)),
            ],
            child: const PrayerLockoutApp(),
          ),
        );
        await tester.pump();

        // Add a reminder due at 3pm.
        final notifier =
            containerOf(tester).read(reminderListProvider.notifier);
        notifier.add(
          Reminder(
            id: 'test-reminder',
            title: 'Test Reminder',
            dueAt: dueTime,
          ),
        );
        await tester.pump();

        // Navigate to reminders segment.
        await tester.tap(find.byTooltip('Tasks'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reminders'));
        await tester.pumpAndSettle();

        // At 12pm, the reminder due at 3pm is NOT yet overdue.
        // Both times are on March 15, so the label format is "Today, 15:00",
        // and the due label renders in the muted (non-overdue) color.
        expect(find.text('Test Reminder'), findsOneWidget);
        expect(find.text('Today, 15:00'), findsOneWidget);
        final beforeLabel = tester.widget<Text>(find.text('Today, 15:00'));
        expect(beforeLabel.style?.color, kPalette.textMuted);

        // Second pump: app with clock at after-due time (4pm, same day).
        // This is the critical half: the _ReminderRow widget watches
        // currentMinuteProvider, so when it changes, the row should rebuild
        // with the new time value and recompute both `isOverdue()` and the
        // due label's color from it — not from the real wall clock, which
        // (being in 2026) would still call this reminder not-yet-due.
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(database),
              securityServiceProvider.overrideWithValue(_FakeSecurityService()),
              notificationServiceProvider
                  .overrideWithValue(_FakeNotificationService()),
              // After due time: 4pm.
              currentMinuteProvider
                  .overrideWithValue(DateTime(2027, 3, 15, 16, 0)),
            ],
            child: const PrayerLockoutApp(),
          ),
        );
        await tester.pump();

        // Navigate to reminders segment.
        await tester.tap(find.byTooltip('Tasks'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reminders'));
        await tester.pumpAndSettle();

        // At 4pm, the reminder due at 3pm is now overdue per the pinned
        // clock. Assert the due label switched to the danger color — the
        // actual signal the row exists to give the user — rather than only
        // re-checking the label text, which stays "Today, 15:00" in both
        // halves and would not by itself catch a clock regression here.
        expect(find.text('Test Reminder'), findsOneWidget);
        expect(find.text('Today, 15:00'), findsOneWidget);
        final afterLabel = tester.widget<Text>(find.text('Today, 15:00'));
        expect(afterLabel.style?.color, kPalette.danger);
      },
    );
  });

  group('settings', () {
    testWidgets('names the device mechanism in the app-lock row',
        (tester) async {
      await pumpApp(tester);

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Require Face ID'),
        250,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('Require Face ID'), findsOneWidget);
      expect(
        find.text('Require Face ID whenever the app is opened or resumed.'),
        findsOneWidget,
      );
      expect(find.text('Lock now'), findsOneWidget);
    });
  });
}
