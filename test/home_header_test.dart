import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` is not in flutter_riverpod.dart's own show-list in 3.4.x — it
// only comes through this leaf import.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cotv/src/models/weather.dart';
import 'package:cotv/src/providers/clock_providers.dart';
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
      overrides: [
        currentMinuteProvider.overrideWithValue(_now),
        ...overrides,
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

void main() {
  testWidgets('the greeting names the user and the temperature is Celsius',
      (tester) async {
    await tester.pumpWidget(_host(
      const WelcomeHeader(name: 'Ahmed'),
      overrides: [
        weatherProvider.overrideWithValue(
          const WeatherReading(celsius: 38, condition: WeatherCondition.cloudy),
        ),
      ],
    ));
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

  testWidgets('no reading means no weather chip, not a blank one',
      (tester) async {
    await tester.pumpWidget(_host(
      const WelcomeHeader(),
      overrides: [weatherProvider.overrideWithValue(null)],
    ));
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

    await tester.pumpWidget(_host(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: const WelcomeHeader(),
      ),
      overrides: [
        weatherProvider.overrideWithValue(
          const WeatherReading(celsius: 38, condition: WeatherCondition.cloudy),
        ),
      ],
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('the search bar carries the placeholder and the mode',
      (tester) async {
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
}
