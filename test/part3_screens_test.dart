// Smoke tests for the Part 3 screens: the habit grid, the journal and its
// full-screen writer, and the settings screen's theme picker and app-lock
// section.
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
import 'package:cotv/src/models/habit.dart';
import 'package:cotv/src/models/journal_entry.dart';
import 'package:cotv/src/models/schedule_item.dart';
import 'package:cotv/src/models/task.dart';
import 'package:cotv/src/models/user_settings.dart';
import 'package:cotv/src/providers/habit_providers.dart';
import 'package:cotv/src/providers/journal_providers.dart';
import 'package:cotv/src/providers/notification_providers.dart';
import 'package:cotv/src/providers/security_providers.dart';
import 'package:cotv/src/providers/theme_providers.dart';
import 'package:cotv/src/providers/user_settings_providers.dart';
import 'package:cotv/src/security/security_service.dart';
import 'package:cotv/src/services/notification_service.dart';
import 'package:cotv/src/storage/local_storage.dart';
import 'package:cotv/src/ui/app_shell.dart';
import 'package:cotv/src/ui/habits/habit_form_sheet.dart';
import 'package:cotv/src/ui/habits/widgets/habit_tile.dart';
import 'package:cotv/src/ui/journal/journal_writer_screen.dart';
import 'package:cotv/src/ui/widgets/ph_light_icons.dart';
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

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cotv_part3_test_');
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
    ]);
  });

  tearDown(() async {
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

  group('habits', () {
    testWidgets('opens the habit form sheet from the grid', (tester) async {
      await pumpApp(tester);

      await tester.tap(find.text('Habits'));
      await tester.pumpAndSettle();

      expect(
        find.text('No habits yet.\nAdd one and it starts counting from today.'),
        findsOneWidget,
      );

      // The quick-add button, not the "Habits" navigation label.
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

      await tester.tap(find.text('Habits'));
      await tester.pumpAndSettle();

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

  group('journal', () {
    testWidgets('lists a stored entry and opens it in the writer',
        (tester) async {
      await pumpApp(tester);

      await tester.tap(find.text('Journal'));
      await tester.pumpAndSettle();

      expect(find.text('Search entries and tags'), findsOneWidget);
      expect(
        find.text('Nothing written yet.\nThe first entry is the hard one.'),
        findsOneWidget,
      );

      final journal = containerOf(tester).read(journalListProvider.notifier);
      final entry = JournalEntry(
        id: 'entry-1',
        date: DateTime(2026, 9, 2),
        content: '# Today\n\nA quiet day. **Alhamdulillah.**',
        mood: JournalMood.good,
        tags: const ['salah'],
      );

      await tester.runAsync(() => journal.addEntry(entry));
      await pumpUntil(
        tester,
        () => find.textContaining('A quiet day.').evaluate().isNotEmpty,
      );

      // The card previews the markdown as plain text — no stray # or **.
      expect(find.text('Today A quiet day. Alhamdulillah.'), findsOneWidget);
      // Twice: on the card, and in the tag filter row the entry has
      // just populated.
      expect(find.text('#salah'), findsNWidgets(2));

      await tester.tap(find.text('Today A quiet day. Alhamdulillah.'));
      await pumpUntilPresented(
        tester,
        () => find.byType(JournalWriterScreen).evaluate().isNotEmpty,
      );

      // The writer opens on the stored entry with the raw markdown back in
      // the editor.
      expect(
        find.text('# Today\n\nA quiet day. **Alhamdulillah.**'),
        findsOneWidget,
      );
      expect(find.text('Save'), findsOneWidget);

      // The mood is read from the preview, not the picker: the picker
      // renders all five labels whatever is selected, so asserting there
      // would pass for any stored mood.
      await tester.tap(find.byIcon(PhLight.eye));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.descendant(
          of: find.byType(JournalWriterScreen),
          matching: find.text('Good'),
        ),
        findsOneWidget,
      );
    });
  });

  group('settings', () {
    testWidgets('offers every theme and applies the stored choice',
        (tester) async {
      await pumpApp(tester);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Theme'), findsOneWidget);
      for (final variant in AppThemeVariant.values) {
        expect(find.text(variant.label), findsOneWidget);
      }

      final container = containerOf(tester);
      expect(container.read(themeVariantProvider), AppThemeVariant.sanctuary);

      await tester.runAsync(
        () => container
            .read(userSettingsControllerProvider.notifier)
            .setThemeId(AppThemeVariant.titanium.id),
      );
      AppSkin? skinInTree() =>
          Theme.of(tester.element(find.byType(AppShell))).extension<AppSkin>();

      // Waits on the tree rather than the provider: MaterialApp cross-fades
      // between themes, so the widgets below it still carry the old palette
      // for the frames the animation is running.
      await pumpUntil(
        tester,
        () => skinInTree()?.variant == AppThemeVariant.titanium,
      );

      // Persisted, so it survives a relaunch...
      expect(
        container.read(themeVariantProvider),
        AppThemeVariant.titanium,
      );
      expect(
        container.read(userSettingsRepositoryProvider).get().themeId,
        'titanium',
      );
      // ...and it reached the widget tree, not just the provider. The
      // variant flips at the cross-fade's halfway point while the colours
      // keep interpolating, so the palette is only exact once it settles.
      expect(skinInTree()?.variant, AppThemeVariant.titanium);
      await tester.pumpAndSettle();
      expect(
        skinInTree()?.palette.background,
        AppThemeVariant.titanium.palette.background,
      );
    });

    testWidgets('names the device mechanism in the app-lock row',
        (tester) async {
      await pumpApp(tester);

      await tester.tap(find.text('Settings'));
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
