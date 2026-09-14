import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` is not in flutter_riverpod.dart's own show-list in 3.4.x — it
// only comes through this leaf import.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cotv/src/models/milo_models.dart';
import 'package:cotv/src/models/weather.dart';
import 'package:cotv/src/providers/clock_providers.dart';
import 'package:cotv/src/providers/milo_providers.dart';
import 'package:cotv/src/providers/weather_providers.dart';
import 'package:cotv/src/ui/home/widgets/home_search_bar.dart';
import 'package:cotv/src/ui/home/widgets/welcome_header.dart';
import 'package:cotv/src/ui/theme/app_theme.dart';

/// Pinned so [WelcomeHeader]'s watch of `prayerNowStateProvider` never
/// starts `nowTickerProvider`'s one-second [Stream.periodic] — that ticker
/// is `autoDispose` and would otherwise be left running at teardown.
final _now = DateTime(2026, 3, 17, 14, 30);

Widget _host(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: [currentMinuteProvider.overrideWithValue(_now), ...overrides],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

/// Same as [_host], but with a real end drawer to open — [HomeSearchBar]'s
/// Milo mode calls `Scaffold.of(context).openEndDrawer()`, which is a silent
/// no-op against a `Scaffold` with none configured, the way [_host]'s is.
Widget _searchHost(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          endDrawer: const Drawer(child: Center(child: Text('Milo drawer'))),
          body: SingleChildScrollView(child: child),
        ),
      ),
    );

/// Stands in for [MiloConversationNotifier] so a Milo-mode submit can be
/// checked without reaching the network `send()` would otherwise start —
/// the same reason `shell_test.dart` has one of these for the dock.
class _RecordingMiloConversationNotifier extends MiloConversationNotifier {
  final List<String> sent = [];

  @override
  MiloConversation build() => const MiloConversation();

  @override
  Future<void> send(String rawText) async {
    sent.add(rawText);
  }
}

void main() {
  testWidgets('the greeting names the user and the temperature is Celsius', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const WelcomeHeader(name: 'Ahmed'),
        overrides: [
          weatherProvider.overrideWithValue(
            const WeatherReading(
              celsius: 38,
              condition: WeatherCondition.cloudy,
            ),
          ),
        ],
      ),
    );
    await tester.pump();

    expect(find.text('Welcome, Ahmed'), findsOneWidget);
    expect(find.text('38°C'), findsOneWidget);
    // "Maghrib is at 19:38" — the name is whatever the pinned clock makes
    // next, so the shape is what is asserted.
    expect(
      find.textContaining(RegExp(r'^\w+ is at \d{1,2}:\d{2}')),
      findsOneWidget,
    );
  });

  testWidgets(
    'the greeting is flat white at 70%, dimmer than the line under it',
    (tester) async {
      await tester.pumpWidget(
        _host(
          const WelcomeHeader(),
          overrides: [weatherProvider.overrideWithValue(null)],
        ),
      );
      await tester.pump();

      // It used to ramp violet-to-white through a ShaderMask, which meant the
      // colour on the TextStyle was a stand-in the shader discarded. Now the
      // style carries the real value, so asserting it is worth something.
      final greeting = tester.widget<Text>(find.text('Welcome, Ahmed'));
      expect(greeting.style?.color, kPalette.textSecondary);
      expect(greeting.style?.color, const Color(0xB3FFFFFF));
      expect(find.byType(ShaderMask), findsNothing);

      // The prayer line is the brighter of the two, which is the point of the
      // change: the greeting recedes and the next thing you need reads first.
      final prayer = tester.widget<Text>(
        find.textContaining(RegExp(r'^\w+ is at \d{1,2}:\d{2}')),
      );
      expect(prayer.style?.color, kPalette.textPrimary);
    },
  );

  testWidgets('no reading means no weather chip, not a blank one', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const WelcomeHeader(),
        overrides: [weatherProvider.overrideWithValue(null)],
      ),
    );
    await tester.pump();

    expect(find.textContaining('°C'), findsNothing);
    expect(
      find.textContaining(RegExp(r'^\w+ is at \d{1,2}:\d{2}')),
      findsOneWidget,
    );
  });

  testWidgets(
    'a large text scale at compact width does not overflow the prayer row',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _host(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
            child: const WelcomeHeader(),
          ),
          overrides: [
            weatherProvider.overrideWithValue(
              const WeatherReading(
                celsius: 38,
                condition: WeatherCondition.cloudy,
              ),
            ),
          ],
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the search bar carries the placeholder and the mode', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const HomeSearchBar()));
    await tester.pump();

    expect(find.text('Search..'), findsOneWidget);
    expect(find.text('Search with Milo'), findsOneWidget);
  });

  testWidgets('the dropdown switches to Chrome', (tester) async {
    await tester.pumpWidget(_host(const HomeSearchBar()));
    await tester.pump();

    await tester.tap(find.text('Search with Milo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search on Chrome').last);
    await tester.pumpAndSettle();

    expect(find.text('Search on Chrome'), findsOneWidget);
    expect(find.text('Search with Milo'), findsNothing);
  });

  testWidgets(
    'a Milo-mode submit opens the drawer, reaches the conversation and '
    'clears the field',
    (tester) async {
      final notifier = _RecordingMiloConversationNotifier();

      await tester.pumpWidget(
        _searchHost(
          const HomeSearchBar(),
          overrides: [miloConversationProvider.overrideWith(() => notifier)],
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'when is asr');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(notifier.sent, ['when is asr']);
      expect(find.text('Milo drawer'), findsOneWidget);
      expect(find.text('when is asr'), findsNothing);
    },
  );

  testWidgets(
    'a Chrome-mode submit calls the launcher with the encoded query and '
    'clears the field',
    (tester) async {
      final launched = <Uri>[];
      Future<bool> fakeOpener(
        Uri url, {
        LaunchMode mode = LaunchMode.platformDefault,
      }) async {
        launched.add(url);
        return true;
      }

      await tester.pumpWidget(
        _searchHost(HomeSearchBar(urlOpener: fakeOpener)),
      );
      await tester.pump();

      await tester.tap(find.text('Search with Milo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Search on Chrome').last);
      await tester.pumpAndSettle();

      // "salah & fasting" rather than a plain phrase: a `&` left unescaped
      // in a query value would be read as the start of the next parameter,
      // so this is a query a naive `'...?q=$query'` concatenation would
      // corrupt but a real percent-encode would not.
      await tester.enterText(find.byType(TextField), 'salah & fasting');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(launched, hasLength(1));
      // Round-trips through `Uri`'s own query parser...
      expect(launched.single.queryParameters['q'], 'salah & fasting');
      // ...because the `&` was actually escaped in the URL (`Uri.https`
      // form-encodes the space as `+` and the `&` as `%26`), not passed
      // through raw — a raw `&` here would have split into a second, bogus
      // query parameter instead.
      expect(launched.single.toString(), contains('salah+%26+fasting'));
      expect(launched.single.queryParametersAll.length, 1);
      expect(find.text('salah & fasting'), findsNothing);
    },
  );

  testWidgets('an empty or whitespace-only query submits nothing', (
    tester,
  ) async {
    final notifier = _RecordingMiloConversationNotifier();
    var launcherCalls = 0;
    Future<bool> fakeOpener(
      Uri url, {
      LaunchMode mode = LaunchMode.platformDefault,
    }) async {
      launcherCalls++;
      return true;
    }

    await tester.pumpWidget(
      _searchHost(
        HomeSearchBar(urlOpener: fakeOpener),
        overrides: [miloConversationProvider.overrideWith(() => notifier)],
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(notifier.sent, isEmpty);
    expect(launcherCalls, 0);
  });

  // The search bar is the one thing on the homepage that does not dim with
  // the cards around it, so its resting state carries no signal at all. The
  // halo is what it has instead, and it answers to the caret as well as to
  // the pointer — a bar being typed into is in use whether or not the mouse
  // is still sitting on it.
  testWidgets('the search bar looks the same hovered, focused and at rest', (
    tester,
  ) async {
    await tester.pumpWidget(_searchHost(const HomeSearchBar()));
    await tester.pump();

    BoxDecoration decoration() {
      final box = tester.widget<Container>(
        find.descendant(
          of: find.byType(HomeSearchBar),
          matching: find.byType(Container),
        ),
      );
      return box.decoration! as BoxDecoration;
    }

    // It used to grow a white halo under a pointer and under the caret. Both
    // are gone, and this is the test that asserted they were there — kept as
    // its inverse rather than deleted, because "no state changes anything" is
    // the actual requirement and nothing else would catch a halo coming back.
    void expectTheOneAppearance(String when) {
      final decor = decoration();
      expect(decor.boxShadow, anyOf(isNull, isEmpty), reason: when);
      expect(decor.color, const Color(0x05D9D9D9), reason: when);
      expect(
        (decor.border! as Border).top.color,
        const Color(0x1AFFFFFF),
        reason: when,
      );
      expect(decor.borderRadius, BorderRadius.circular(10), reason: when);
    }

    const away = Offset(400, 500);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: away);
    addTearDown(mouse.removePointer);
    await tester.pump();
    expectTheOneAppearance('at rest');

    await mouse.moveTo(tester.getCenter(find.byType(HomeSearchBar)));
    await tester.pump();
    expectTheOneAppearance('hovered');

    await mouse.moveTo(away);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expectTheOneAppearance('holding the caret');
  });

  testWidgets('the search bar animates nothing', (tester) async {
    await tester.pumpWidget(_searchHost(const HomeSearchBar()));
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(HomeSearchBar),
        matching: find.byType(AnimatedContainer),
      ),
      findsNothing,
      reason: 'a plain Container: there is nothing left to animate between',
    );
  });
}
