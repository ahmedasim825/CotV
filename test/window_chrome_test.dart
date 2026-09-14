// The window controls that replace the Windows title bar.
//
// The runner reports the whole window as client area now, so there is no
// caption to move, minimise or close the window with. These pin the two halves
// of the replacement: that the controls mount and call through to the runner,
// and that the strip they sit in is reserved so no pane draws underneath them.
//
// Windows-only chrome, gated on `ThemeData.platform`, so the theme below opts
// in the way `milo_orb_test.dart` does. The default `buildAppTheme()` reports
// Android under flutter_test, which is why every other test file in this suite
// never sees any of this.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import 'package:cotv/hive_registrar.g.dart';
import 'package:cotv/src/models/active_study_session.dart';
import 'package:cotv/src/models/chat_message.dart';
import 'package:cotv/src/models/habit.dart';
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
import 'package:cotv/src/ui/shell/sidebar.dart';
import 'package:cotv/src/ui/shell/window_chrome.dart';
import 'package:cotv/src/ui/theme/app_theme.dart';

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
  }) async => false;

  @override
  Future<void> cancelReminder(String key) async {}
}

void main() {
  const channel = MethodChannel('cotv/window');

  late Directory tempDir;
  late AppDatabase database;
  late List<String> calls;

  /// What the fake runner reports for `isMaximized`.
  late bool maximized;

  setUp(() async {
    calls = <String>[];
    maximized = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          switch (call.method) {
            case 'isMaximized':
              return maximized;
            case 'toggleMaximize':
              maximized = !maximized;
              return maximized;
            default:
              return null;
          }
        });

    database = AppDatabase.openAt(':memory:');
    tempDir = await Directory.systemTemp.createTemp('cotv_chrome_test_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapters();
    }
    await Future.wait([
      Hive.openBox<Task>(HiveBoxes.tasks),
      Hive.openBox<Habit>(HiveBoxes.habits),
      Hive.openBox<UserSettings>(HiveBoxes.userSettings),
      Hive.openBox<Subject>(HiveBoxes.subjects),
      Hive.openBox<StudyLog>(HiveBoxes.studyLogs),
      Hive.openBox<ChatMessage>(HiveBoxes.chatMessages),
      Hive.openBox<ActiveStudySession>(HiveBoxes.activeStudySession),
    ]);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    database.dispose();
    await Hive.deleteFromDisk();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> pumpShell(
    WidgetTester tester, {
    TargetPlatform platform = TargetPlatform.windows,
  }) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          securityServiceProvider.overrideWithValue(_FakeSecurityService()),
          notificationServiceProvider.overrideWithValue(
            _FakeNotificationService(),
          ),
          ambientAnimationProvider.overrideWithValue(false),
        ],
        child: MaterialApp(
          theme: buildAppTheme().copyWith(platform: platform),
          home: const AppShell(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('Windows draws its own controls where the caption was', (
    tester,
  ) async {
    await pumpShell(tester);

    expect(find.byType(WindowChrome), findsOneWidget);
    for (final label in ['Minimize', 'Maximize', 'Close']) {
      expect(find.byTooltip(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('the leading cluster names the app and opens the rail', (
    tester,
  ) async {
    await pumpShell(tester);

    expect(find.text('Milo'), findsWidgets);
    expect(find.byTooltip('Hide sidebar'), findsOneWidget);

    // Left of all three window buttons, and inside the strip.
    final toggle = tester.getRect(find.byTooltip('Hide sidebar'));
    final wordmark = tester.getRect(
      find.descendant(
        of: find.byType(WindowChrome),
        matching: find.text('Milo'),
      ),
    );
    // Wordmark first, then the control, then the three window buttons.
    expect(wordmark.right, lessThanOrEqualTo(toggle.left));
    for (final label in ['Minimize', 'Maximize', 'Close']) {
      expect(
        toggle.right,
        lessThanOrEqualTo(tester.getRect(find.byTooltip(label)).left),
        reason: label,
      );
    }
    expect(toggle.bottom, lessThanOrEqualTo(windowChromeHeight));
  });

  testWidgets('that control closes the rail and opens it again', (
    tester,
  ) async {
    await pumpShell(tester);

    expect(find.byType(Sidebar), findsOneWidget);

    await tester.tap(find.byTooltip('Hide sidebar'));
    await tester.pump();

    expect(find.byType(Sidebar), findsNothing);
    // The control is the only way back, so it has to still be there — and it
    // has to say the other thing.
    expect(find.byTooltip('Show sidebar'), findsOneWidget);

    await tester.tap(find.byTooltip('Show sidebar'));
    await tester.pump();

    expect(find.byType(Sidebar), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('no other platform gets them', (tester) async {
    // The default flutter_test platform, and the one every other file in this
    // suite runs under — which is why none of them see this chrome.
    await pumpShell(tester, platform: TargetPlatform.android);

    expect(find.byType(WindowChrome), findsNothing);
    expect(find.byTooltip('Close'), findsNothing);
  });

  testWidgets('the strip spans the window and sits at the very top', (
    tester,
  ) async {
    await pumpShell(tester);

    final strip = tester.getRect(find.byType(WindowChrome));
    expect(strip.top, 0);
    expect(strip.height, windowChromeHeight);
    expect(strip.width, tester.getRect(find.byType(AppShell)).width);

    // Trailing edge, like the caption buttons it replaces.
    expect(
      tester.getRect(find.byTooltip('Close')).right,
      closeTo(strip.right, 0.5),
    );
  });

  testWidgets('panes are inset so nothing draws under the controls', (
    tester,
  ) async {
    await pumpShell(tester);

    // The inset is published as MediaQuery padding and consumed by the shell's
    // own SafeArea, so no pane has to know the strip exists.
    expect(
      tester.getRect(find.byType(HomeScreen)).top,
      greaterThanOrEqualTo(windowChromeHeight),
    );
  });

  testWidgets('each button calls the runner', (tester) async {
    await pumpShell(tester);
    calls.clear();

    await tester.tap(find.byTooltip('Minimize'));
    await tester.pump();
    expect(calls, contains('minimize'));

    calls.clear();
    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    expect(calls, contains('close'));
  });

  testWidgets('the maximize button becomes Restore once maximized', (
    tester,
  ) async {
    await pumpShell(tester);

    expect(find.byTooltip('Maximize'), findsOneWidget);
    expect(find.byTooltip('Restore'), findsNothing);

    await tester.tap(find.byTooltip('Maximize'));
    await tester.pump();
    await tester.pump();

    expect(calls, contains('toggleMaximize'));
    expect(find.byTooltip('Restore'), findsOneWidget);
    expect(find.byTooltip('Maximize'), findsNothing);
  });

  testWidgets('dragging the empty strip asks the OS to move the window', (
    tester,
  ) async {
    await pumpShell(tester);
    calls.clear();

    // The left end of the strip, clear of the three buttons and below the
    // 8pt resize band that owns the very top of the window.
    await tester.dragFrom(const Offset(200, 20), const Offset(40, 40));
    // Past `kDoubleTapTimeout`: the strip also listens for a double tap to
    // maximize, and that recognizer holds a timer open after every pointer-up
    // waiting for a second tap that is not coming. Left pending, flutter_test
    // fails the test on it whatever the assertions say.
    await tester.pump(const Duration(milliseconds: 400));

    expect(calls, contains('startDrag'));
  });

  testWidgets('every edge and corner has a grab band', (tester) async {
    await pumpShell(tester);

    expect(find.byType(WindowResizeBorders), findsOneWidget);
    for (final edge in [
      'left',
      'right',
      'top',
      'bottom',
      'topLeft',
      'topRight',
      'bottomLeft',
      'bottomRight',
    ]) {
      expect(
        find.byKey(ValueKey('resize-$edge')),
        findsOneWidget,
        reason: edge,
      );
    }
  });

  testWidgets('dragging an edge asks the OS to resize, not to move', (
    tester,
  ) async {
    await pumpShell(tester);
    calls.clear();

    // Mid-way down the left edge, inside the 8pt band.
    await tester.dragFrom(const Offset(3, 400), const Offset(-30, 0));
    await tester.pump(const Duration(milliseconds: 400));

    expect(calls, contains('startResize'));
    expect(calls, isNot(contains('startDrag')));
  });

  testWidgets('the top edge resizes rather than dragging the window', (
    tester,
  ) async {
    await pumpShell(tester);
    calls.clear();

    // Inside the chrome strip's own 32pt height, but in the 8pt the drag
    // handle deliberately leaves unclaimed so the band beneath can have it.
    await tester.dragFrom(const Offset(400, 3), const Offset(0, -30));
    await tester.pump(const Duration(milliseconds: 400));

    expect(calls, contains('startResize'));
    expect(
      calls,
      isNot(contains('startDrag')),
      reason: 'the top 8pt belongs to the resize band, not the handle',
    );
  });

  testWidgets('a drag that starts on a button does not move the window', (
    tester,
  ) async {
    await pumpShell(tester);
    calls.clear();

    await tester.drag(find.byTooltip('Close'), const Offset(40, 40));
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      calls,
      isNot(contains('startDrag')),
      reason: 'the buttons sit beside the handle, not inside it',
    );
  });
}
