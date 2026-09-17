// The iOS shell, end to end: the redesigned Home pane and the floating glass
// nav pill, pumped as the whole app the way `widget_test.dart` pumps the
// Windows one.
//
// These two files are a matched pair, and several assertions here are the
// deliberate mirror of one there — the orb is absent at 393pt on Windows and
// present at 393pt on iOS; the page blurs nothing on Windows and groups its
// blurs on iOS. Neither file means much without the other, because what is
// being pinned is the *split*, not either side of it.
//
// The platform is switched through the theme — `buildAppTheme().copyWith(
// platform: TargetPlatform.iOS)`, the idiom `test/milo_orb_test.dart` already
// uses — rather than through `debugDefaultTargetPlatformOverride`, which
// flutter_test rejects outright: it verifies that foundation globals are unset
// *before* tearDown runs, so a setUp/tearDown pairing on it fails every test
// in the file. The cost is building the MaterialApp here instead of pumping
// `PrayerLockoutApp`; `AppShell` below is the part under test either way.
//
// Never `pumpAndSettle` anywhere in here: the Milo orb now lives on Home and
// its breathing controller repeats forever, so the tree never settles.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show BackdropFilterLayer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import 'package:cotv/hive_registrar.g.dart';
import 'package:cotv/src/models/active_study_session.dart';
import 'package:cotv/src/models/chat_message.dart';
import 'package:cotv/src/models/reminder.dart';
import 'package:cotv/src/models/study_log.dart';
import 'package:cotv/src/models/subject.dart';
import 'package:cotv/src/models/task.dart';
import 'package:cotv/src/models/user_settings.dart';
import 'package:cotv/src/providers/chat_session_providers.dart';
import 'package:cotv/src/providers/ambient_providers.dart';
import 'package:cotv/src/providers/notification_providers.dart';
import 'package:cotv/src/providers/security_providers.dart';
import 'package:cotv/src/security/security_service.dart';
import 'package:cotv/src/services/notification_service.dart';
import 'package:cotv/src/storage/app_database.dart';
import 'package:cotv/src/storage/local_storage.dart';
import 'package:cotv/src/ui/app_shell.dart';
import 'package:cotv/src/ui/home/home_screen.dart';
import 'package:cotv/src/ui/home/widgets/agenda_card.dart';
import 'package:cotv/src/ui/home/widgets/focus_tasks_card.dart';
import 'package:cotv/src/ui/home/widgets/milo_orb.dart';
import 'package:cotv/src/ui/home/widgets/music_widget.dart';
import 'package:cotv/src/ui/home/widgets/reminders_card.dart';
import 'package:cotv/src/ui/components/liquid_glass.dart';
import 'package:cotv/src/ui/shell/liquid_glass_nav_bar.dart';
import 'package:cotv/src/ui/shell/milo_dock.dart';
import 'package:cotv/src/ui/settings/settings_screen.dart';
import 'package:cotv/src/ui/shell/sidebar.dart';
import 'package:cotv/src/ui/theme/app_theme.dart';
import 'package:cotv/src/ui/widgets/ph_light_icons.dart';

class _FakeSecurityService extends SecurityService {
  @override
  Future<bool> isBiometricEnabled() async => false;
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
    database = AppDatabase.openAt(':memory:');
    tempDir = await Directory.systemTemp.createTemp('cotv_ios_shell_test_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapters();
    }
    await Future.wait([
      Hive.openBox<Task>(HiveBoxes.tasks),
      Hive.openBox<Reminder>(HiveBoxes.reminders),
      Hive.openBox<UserSettings>(HiveBoxes.userSettings),
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

  Future<void> pumpApp(
    WidgetTester tester, {
    Size logicalSize = const Size(393, 852),
    EdgeInsets viewPadding = EdgeInsets.zero,
    List<Override> extraOverrides = const [],
  }) async {
    tester.view.physicalSize = logicalSize * 3.0;
    tester.view.devicePixelRatio = 3.0;
    tester.view.viewPadding = FakeViewPadding(
      bottom: viewPadding.bottom * 3.0,
    );
    tester.view.padding = FakeViewPadding(bottom: viewPadding.bottom * 3.0);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          securityServiceProvider.overrideWithValue(_FakeSecurityService()),
          notificationServiceProvider
              .overrideWithValue(_FakeNotificationService()),
          ambientAnimationProvider.overrideWithValue(false),
          ...extraOverrides,
        ],
        child: MaterialApp(
          theme: buildAppTheme().copyWith(platform: TargetPlatform.iOS),
          home: const AppShell(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
  }

  group('the home pane', () {
    testWidgets('shows the merged card in place of the Tasks/Reminders pair',
        (tester) async {
      await pumpApp(tester, logicalSize: const Size(393, 2400));

      expect(find.byType(AgendaCard), findsOneWidget);
      expect(find.text('Tasks / Reminders'), findsOneWidget);
      expect(find.byType(FocusTasksCard), findsNothing);
      expect(find.byType(RemindersCard), findsNothing);
    });

    testWidgets('drops the music widget the mock does not draw',
        (tester) async {
      await pumpApp(tester, logicalSize: const Size(393, 2400));

      expect(find.byType(MusicWidget), findsNothing);
      // The cards the mock does draw are all still here.
      expect(find.text('Study time'), findsOneWidget);
      expect(find.text('Nutrition'), findsOneWidget);
    });

    testWidgets('carries Milo in the page, where Windows has it in the rail',
        (tester) async {
      await pumpApp(tester, logicalSize: const Size(393, 2400));

      // The mirror of widget_test.dart's "boots into the home dashboard",
      // which asserts findsNothing at this same width on the Windows path.
      expect(find.byType(MiloOrbWidget), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(HomeScreen),
          matching: find.byType(MiloDock),
        ),
        findsOneWidget,
      );
      expect(find.text('Chat >'), findsOneWidget);
    });

    testWidgets('puts a settings gear in the header corner', (tester) async {
      await pumpApp(tester, logicalSize: const Size(393, 2400));

      final gear = find.descendant(
        of: find.byType(HomeScreen),
        matching: find.byTooltip('Settings'),
      );
      expect(gear, findsOneWidget);

      // It is a corner control: clear of the greeting, hard against the
      // trailing edge.
      final greeting = tester.getRect(find.text('Welcome, Ahmed'));
      expect(tester.getRect(gear).left, greaterThanOrEqualTo(greeting.right));

      await tester.tap(gear);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Settings is a destination the pill does not carry, so this gear is
      // the only route to it at this width — the assertion is that it is a
      // real one, not decoration.
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
    });

    testWidgets('groups its backdrop filters instead of running one each',
        (tester) async {
      await pumpApp(tester, logicalSize: const Size(393, 2400));

      // The mirror of home_dashboard_test.dart's "nothing on the page blurs
      // its backdrop", which pins findsNothing on the Windows path.
      expect(
        find.descendant(
          of: find.byType(HomeScreen),
          matching: find.byType(BackdropGroup),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(HomeScreen),
          matching: find.byType(BackdropFilter),
        ),
        findsWidgets,
      );
    });

    testWidgets('leaves no Opacity above a card to break its blur',
        (tester) async {
      await pumpApp(tester, logicalSize: const Size(393, 2400));

      // RevealOnEntrance stands down on this path precisely because its
      // Opacity is a save layer, and a BackdropFilter under one samples that
      // buffer instead of the page.
      expect(
        find.descendant(
          of: find.byType(HomeScreen),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );
    });
  });

  group('the nav pill', () {
    testWidgets('carries the five destinations and nothing else',
        (tester) async {
      await pumpApp(tester);

      for (final label in ['Home', 'Tasks', 'Study', 'Food', 'Prayers']) {
        expect(find.byTooltip(label), findsOneWidget, reason: label);
      }
      // Settings moved to the header gear; Milo moved into the Home pane.
      expect(find.byTooltip('Milo'), findsNothing);
      expect(find.byIcon(PhLight.sparkle), findsNothing);
    });

    testWidgets('is glass, and keeps its own backdrop', (tester) async {
      await pumpApp(tester);

      // Non-vacuity first. This assertion is the whole reason the test is
      // written this way round: the pill used to be a bare `BackdropFilter`,
      // and a finder looking for one now matches nothing at all — so the
      // ancestor check below would pass on an empty set and keep passing if
      // the glass were deleted outright.
      // Scoped to the capsule: the search field is control-layer glass too,
      // so an unscoped finder would match two and this would fail for a
      // reason that has nothing to do with the bar.
      final glass = find.descendant(
        of: find.byType(LiquidGlassNavBar),
        matching: find.byType(LiquidGlass),
      );
      expect(glass, findsOneWidget);

      // The pill's filter must not sit under HomeScreen's BackdropGroup:
      // overlapping filters sharing a backdrop key render as though only one
      // applied, and `extendBody` makes them overlap by definition.
      expect(find.ancestor(of: glass, matching: find.byType(HomeScreen)),
          findsNothing);

      // And the property that actually enforces it. Every card on Home goes
      // through `BackdropFilter.grouped`, so each of their layers carries the
      // group's key; a backdrop layer with no key at all can only be the
      // pill's.
      final ungrouped = tester.layers
          .whereType<BackdropFilterLayer>()
          .where((layer) => layer.backdropKey == null);
      expect(ungrouped, isNotEmpty);
    });

    testWidgets('floats inside the home-indicator strip rather than above it',
        (tester) async {
      await pumpApp(
        tester,
        viewPadding: const EdgeInsets.only(bottom: 34),
      );

      // The nav item fills the capsule's height, so its rect is the capsule's
      // — and unlike a ClipRRect finder it cannot accidentally match a glass
      // card's clip somewhere else in the tree.
      final pill = tester.getRect(find.byTooltip('Home'));
      final screenBottom = tester.getRect(find.byType(AppShell)).bottom;

      // The design's 71pt capsule, less the 1pt the row is inset by at the
      // top and bottom. Comfortably past the 44pt minimum, which is the part
      // that actually matters.
      expect(pill.height, 69);
      // max(10, 34 - 12) = 22, plus that 1pt rim below the item.
      expect(screenBottom - pill.bottom, closeTo(23, 0.5));
    });

    testWidgets('switching destinations still works', (tester) async {
      await pumpApp(tester);

      expect(find.byType(HomeScreen), findsOneWidget);

      await tester.tap(find.byTooltip('Tasks'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(HomeScreen), findsNothing);
      // The Tasks pane's own day heading — always rendered, because the Today
      // section carries the inline add control even when it is empty.
      expect(find.text('Today'), findsWidgets);
    });

    testWidgets('leaves no Opacity between itself and its glass',
        (tester) async {
      await pumpApp(tester);

      // The sibling of the HomeScreen guard above, for the other filter. A
      // save layer anywhere over a backdrop filter leaves it sampling that
      // buffer instead of the page, and the capsule is about to grow fades —
      // which is why its glyphs tween colour rather than cross-fading.
      expect(
        find.descendant(
          of: find.byType(LiquidGlassNavBar),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(LiquidGlassNavBar),
          matching: find.byType(FadeTransition),
        ),
        findsNothing,
      );
    });

    testWidgets('collapses on a downward scroll and comes back on an upward '
        'one', (tester) async {
      await pumpApp(tester, viewPadding: const EdgeInsets.only(bottom: 34));

      double capsuleHeight() =>
          tester.getRect(find.byTooltip('Home')).height;

      final double resting = capsuleHeight();
      expect(resting, 69);

      await tester.fling(find.byType(HomeScreen), const Offset(0, -220), 900);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(capsuleHeight(), lessThan(resting));

      await tester.fling(find.byType(HomeScreen), const Offset(0, 220), 900);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(capsuleHeight(), resting);
    });

    testWidgets('collapsing does not move the padding every pane reads',
        (tester) async {
      await pumpApp(tester, viewPadding: const EdgeInsets.only(bottom: 34));

      double bodyPadding() => MediaQuery.paddingOf(
            tester.element(
              find
                  .descendant(
                    of: find.byType(AppShell),
                    matching: find.byType(SafeArea),
                  )
                  .first,
            ),
          ).bottom;

      // The whole reason the capsule shrinks inside a fixed box. Scaffold
      // republishes the bar's measured height as body padding through a
      // LayoutBuilder, so a footprint that moved mid-animation would rebuild
      // every pane's subtree during layout, once a frame, and jerk anything
      // pinned at its maximum scroll extent.
      final double before = bodyPadding();

      await tester.fling(find.byType(HomeScreen), const Offset(0, -220), 900);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      expect(bodyPadding(), before, reason: 'mid-collapse');

      await tester.pump(const Duration(milliseconds: 400));
      expect(bodyPadding(), before, reason: 'fully collapsed');
    });

    testWidgets('re-tapping the active tab sends the pane back to the top',
        (tester) async {
      await pumpApp(tester);

      final Finder pane = find.descendant(
        of: find.byType(HomeScreen),
        matching: find.byType(Scrollable),
      );
      await tester.drag(pane.first, const Offset(0, -260));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final ScrollPosition scrolled =
          tester.state<ScrollableState>(pane.first).position;
      expect(scrolled.pixels, greaterThan(0), reason: 'did not scroll');

      // The tab it is already on. Apple sends the list home rather than
      // rebuilding the pane you are already looking at.
      await tester.tap(find.byTooltip('Home'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(tester.state<ScrollableState>(pane.first).position.pixels, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('only ever attaches one pane to the shared scroll controller',
        (tester) async {
      await pumpApp(tester);

      // The guard in `_scrollToTop` exists because a ScrollController with two
      // attached positions throws the moment anything reads `.position`. Walk
      // every destination and re-tap it, which is the sequence that would trip
      // it if two panes were ever mounted at once.
      for (final label in ['Home', 'Tasks', 'Study', 'Food', 'Prayers']) {
        await tester.tap(find.byTooltip(label));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        await tester.tap(find.byTooltip(label));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.takeException(), isNull, reason: label);
      }
    });

    testWidgets('every pane clears the pill rather than scrolling under it',
        (tester) async {
      await pumpApp(
        tester,
        viewPadding: const EdgeInsets.only(bottom: 34),
      );

      // Every pane reserves its bottom room out of `MediaQuery.paddingOf` —
      // three read it directly, and Prayers takes it through its own SafeArea.
      // All five therefore depend on one thing: that Scaffold reports the
      // capsule's whole footprint there, which is what `extendBody` buys.
      // Assert that number, not each pane's geometry.
      //
      // Read at the shell's own SafeArea, which sits directly under Scaffold's
      // body builder. Reading lower — at a Scrollable, say — gives zero:
      // `BoxScrollView` strips the padding it has already handed its slivers
      // out of the MediaQuery it passes down.
      final bodyPadding = MediaQuery.paddingOf(
        tester.element(
          find
              .descendant(
                of: find.byType(AppShell),
                matching: find.byType(SafeArea),
              )
              .first,
        ),
      ).bottom;

      // The capsule's 71pt plus the 22pt it floats above the screen edge.
      expect(bodyPadding, greaterThanOrEqualTo(93));

      for (final label in ['Home', 'Tasks', 'Study', 'Food', 'Prayers']) {
        await tester.tap(find.byTooltip(label));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        expect(tester.takeException(), isNull, reason: label);
      }
    });
  });

  group('iPad', () {
    testWidgets('keeps the sidebar and takes no pill', (tester) async {
      await pumpApp(tester, logicalSize: const Size(834, 1194));

      expect(find.byType(Sidebar), findsOneWidget);
      // Five tooltips would mean the pill mounted alongside the rail.
      expect(find.byTooltip('Home'), findsNothing);
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('shows Milo in the pane, not in the sidebar dock',
        (tester) async {
      await pumpApp(tester, logicalSize: const Size(834, 2400));

      expect(find.byType(MiloDock), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Sidebar),
          matching: find.byType(MiloDock),
        ),
        findsNothing,
        reason: 'two orbs breathing at once would read as two Milos',
      );
    });

    testWidgets('leaves Settings to the sidebar gear, not a header one',
        (tester) async {
      await pumpApp(tester, logicalSize: const Size(834, 2400));

      // The sidebar's footer gear is already right there; a second in the
      // header would be two doors to the same room.
      expect(
        find.descendant(
          of: find.byType(HomeScreen),
          matching: find.byTooltip('Settings'),
        ),
        findsNothing,
      );
      expect(find.byTooltip('Settings'), findsOneWidget);
    });
  });
}
