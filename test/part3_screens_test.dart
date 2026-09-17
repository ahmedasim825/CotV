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
import 'package:cotv/src/models/reminder.dart';
import 'package:cotv/src/models/study_log.dart';
import 'package:cotv/src/models/subject.dart';
import 'package:cotv/src/models/task.dart';
import 'package:cotv/src/models/user_settings.dart';
import 'package:cotv/src/providers/ambient_providers.dart';
import 'package:cotv/src/providers/clock_providers.dart';
import 'package:cotv/src/providers/notification_providers.dart';
import 'package:cotv/src/providers/reminder_providers.dart';
import 'package:cotv/src/providers/security_providers.dart';
import 'package:cotv/src/providers/settings_providers.dart';
import 'package:cotv/src/security/security_service.dart';
import 'package:cotv/src/services/notification_service.dart';
import 'package:cotv/src/providers/chat_session_providers.dart';
import 'package:cotv/src/storage/app_database.dart';
import 'package:cotv/src/storage/local_storage.dart';
import 'package:cotv/src/ui/app_shell.dart';
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
      Hive.openBox<Reminder>(HiveBoxes.reminders),
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
          // The orb field animates forever; pumpAndSettle would time out.
          ambientAnimationProvider.overrideWithValue(false),
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
              // The orb field animates forever; pumpAndSettle would time out.
              ambientAnimationProvider.overrideWithValue(false),
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
        // Inside `runAsync`: this reaches a real Hive box now that reminders
        // are persisted, and real file IO cannot complete inside the fake
        // async zone `testWidgets` runs the body in — awaiting it there hangs
        // rather than failing. `agenda_card_test.dart` seeds its tasks the
        // same way.
        await tester.runAsync(() async {
          await notifier.addReminder(
            Reminder(
              id: 'test-reminder',
              title: 'Test Reminder',
              dueAt: dueTime,
            ),
          );
        });
        // Twice: once for the box's change stream to deliver, once for the
        // provider's new state to reach the tree.
        await tester.pump();
        await tester.pump();

        // Navigate to reminders segment.
        await tester.tap(find.byTooltip('Tasks'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reminders'));
        await tester.pumpAndSettle();

        // At 12pm, the reminder due at 3pm is NOT yet overdue.
        // Both times are on March 15, so the label format is
        // "Today at 15:00", and the due line renders in the muted
        // (non-overdue) color.
        expect(find.text('Test Reminder'), findsOneWidget);
        expect(find.text('Today at 15:00'), findsOneWidget);
        final beforeLabel = tester.widget<Text>(find.text('Today at 15:00'));
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
              // The orb field animates forever; pumpAndSettle would time out.
              ambientAnimationProvider.overrideWithValue(false),
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
        // clock. Assert the due line switched to the overdue color — the
        // actual signal the row exists to give the user — rather than only
        // re-checking the text, which stays "Today at 15:00" in both halves
        // and would not by itself catch a clock regression here.
        expect(find.text('Test Reminder'), findsOneWidget);
        expect(find.text('Today at 15:00'), findsOneWidget);
        final afterLabel = tester.widget<Text>(find.text('Today at 15:00'));
        expect(afterLabel.style?.color, kPalette.dueOverdue);
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

    testWidgets(
        'the lockout window row describes the device calendar, and its '
        'picker writes through to the live duration', (tester) async {
      await pumpApp(tester);

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Lockout window'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      // `scrollUntilVisible` stops as soon as the row exists in the tree —
      // which can be true while it's still only within the sliver's cache
      // extent, below the actual viewport — then jumps the scroll offset
      // synchronously. That jump doesn't take visual effect (and the row's
      // hit-test geometry doesn't update) until the next frame, so a pump
      // is required here before anything below can tap it.
      await tester.pump();

      // Honest copy: what this control now drives is the device-calendar
      // block, not the deleted in-app overlay.
      expect(find.textContaining('device calendar'), findsOneWidget);
      expect(find.text('30 minutes'), findsOneWidget);

      await tester.tap(find.text('Lockout window'));
      await pumpUntilPresented(
        tester,
        () => find.text('45 minutes').evaluate().isNotEmpty,
      );

      await tester.tap(find.text('45 minutes').last);
      await tester.pumpAndSettle();

      expect(
        containerOf(tester).read(lockoutDurationProvider),
        const Duration(minutes: 45),
      );
      expect(find.text('45 minutes'), findsOneWidget);
    });
  });
}
