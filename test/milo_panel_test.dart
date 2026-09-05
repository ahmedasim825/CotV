// The Milo panel end to end: launcher, empty state, and a turn streaming
// into the routing rail.
//
// Same harness as the other widget tests — real Hive in a temp directory,
// plugin-backed services faked — plus two Milo-specific overrides: the
// secrets (so no Keychain channel is needed) and the HTTP client (so the
// real GroqClient runs against a scripted event stream).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:local_auth/local_auth.dart';

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
import 'package:cotv/src/security/security_service.dart';
import 'package:cotv/src/services/milo/milo_credentials.dart';
import 'package:cotv/src/services/notification_service.dart';
import 'package:cotv/src/storage/local_storage.dart';
import 'package:cotv/src/ui/app_shell.dart';
import 'package:cotv/src/ui/milo/milo_assistant_screen.dart';

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

String _groqFrame(String text) =>
    'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': text},
            },
          ],
        })}\n\n';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cotv_milo_test_');
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
    await Hive.close();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows can hold the box file briefly after close.
      }
    }
  });

  Future<void> pumpApp(WidgetTester tester, http.Client client) async {
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
          miloHttpClientProvider.overrideWithValue(client),
          miloSecretsProvider.overrideWith(
            (ref) async => const MiloSecrets(groqApiKey: 'gsk_test'),
          ),
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
  /// Settling is not an option on this screen: the schedule tab behind the
  /// panel holds the one-second clock ticker open, so a frame is always
  /// scheduled and the tree never comes to rest.
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

  /// Taps the launcher and waits for the drawer to finish sliding in — it
  /// is findable from the first frame of the slide, when it is still off
  /// the right edge and nothing inside it can be tapped.
  Future<void> openPanel(WidgetTester tester) async {
    await tester.tap(find.text('Milo'));
    await pumpUntil(
      tester,
      () => find.byType(MiloAssistantScreen).evaluate().isNotEmpty,
    );
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('the launcher opens the panel on its empty state',
      (tester) async {
    await pumpApp(tester, MockClient((request) async => http.Response('', 500)));

    // The launcher sits opposite each screen's own quick-add pill.
    expect(find.text('Milo'), findsOneWidget);

    await openPanel(tester);

    expect(find.byType(MiloAssistantScreen), findsOneWidget);
    expect(find.text('Ask Milo.'), findsOneWidget);
    // One example per route, so the empty panel explains what Milo reaches.
    expect(find.text("What's my next prayer?"), findsOneWidget);
    expect(find.text('Open Spotify on my PC'), findsOneWidget);
    expect(
      find.text('Plan a study block around Maghrib tonight'),
      findsOneWidget,
    );
  });

  testWidgets('a reply streams in under the badge of the engine that ran',
      (tester) async {
    final client = MockClient.streaming((request, bodyStream) async {
      await bodyStream.bytesToString();
      return http.StreamedResponse(
        Stream.fromIterable(
          [_groqFrame('Asr, at 16:12.'), 'data: [DONE]\n\n'].map(utf8.encode),
        ),
        200,
        headers: const {'content-type': 'text/event-stream'},
      );
    });

    await pumpApp(tester, client);
    await openPanel(tester);

    // Sent through runAsync rather than by tapping the example chip: a reply
    // is a chain of async generators (SSE frames -> client -> service), and
    // the fake-async zone testWidgets runs in starves that chain partway
    // through. Same reason the other widget tests seed their writes this
    // way. The tap path itself is covered by the empty-state test above.
    final container =
        ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    await tester.runAsync(
      () => container
          .read(miloConversationProvider.notifier)
          .send("What's my next prayer?"),
    );
    await pumpUntil(
      tester,
      () => find.text('Asr, at 16:12.').evaluate().isNotEmpty,
    );

    // The prompt is echoed as the user's turn, and the reply carries the
    // badge of the engine that actually ran.
    expect(find.text("What's my next prayer?"), findsOneWidget);
    expect(find.text('Asr, at 16:12.'), findsOneWidget);
    expect(find.text('GROQ INSTANT'), findsOneWidget);
    // The engine that did not run stays an unlabelled ring.
    expect(find.text('GEMINI DEEP'), findsNothing);
    expect(find.text('DONE ON PC'), findsNothing);
  });

  testWidgets('a rejected key is reported on the turn, not swallowed',
      (tester) async {
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode({
          'error': {'message': 'Invalid API Key'},
        }),
        401,
      ),
    );

    await pumpApp(tester, client);
    await openPanel(tester);

    await tester.tap(find.text("What's my next prayer?"));
    await pumpUntil(
      tester,
      () => find
          .textContaining('Groq rejected the API key')
          .evaluate()
          .isNotEmpty,
    );

    expect(
      find.textContaining('Check it in Milo settings.'),
      findsOneWidget,
    );
  });
}
