import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cotv/src/providers/ambient_providers.dart';
import 'package:cotv/src/ui/theme/app_theme.dart';
import 'package:cotv/src/ui/widgets/orb_field_background.dart';

Widget _host({bool animate = false, Size? size}) {
  Widget ground = const OrbFieldBackground(child: SizedBox.shrink());
  if (size != null) {
    ground = MediaQuery(data: MediaQueryData(size: size), child: ground);
  }

  return ProviderScope(
    overrides: [ambientAnimationProvider.overrideWithValue(animate)],
    child: MaterialApp(theme: buildAppTheme(), home: ground),
  );
}

Color _baseOf(WidgetTester tester) => tester
    .widget<ColoredBox>(
      find
          .descendant(
            of: find.byType(OrbFieldBackground),
            matching: find.byType(ColoredBox),
          )
          .first,
    )
    .color;

void main() {
  group('with animation off', () {
    testWidgets('settles, which is what the five app-level suites rely on',
        (tester) async {
      await tester.pumpWidget(_host());

      // The drift ticker repeats forever once started. Every test that builds
      // the real app overrides the flag for this reason: an unsettling tree
      // makes `pumpAndSettle` run to its ten-minute timeout.
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('paints the base and the orb field', (tester) async {
      await tester.pumpWidget(_host());

      // The ground is one fixed colour now — it used to be picked from the
      // hour — and it arrives through the theme rather than being written by
      // the widget, which is what lets `buildAppTheme(background:)` override
      // it without reaching in here.
      expect(_baseOf(tester), const Color(0xFF191717));
      expect(_baseOf(tester), kPalette.background);
      expect(
        find.descendant(
          of: find.byType(OrbFieldBackground),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );
    });

    testWidgets('takes the theme ground, so an override reaches it',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [ambientAnimationProvider.overrideWithValue(false)],
          child: MaterialApp(
            theme: buildAppTheme(background: const Color(0xFF120323)),
            home: const OrbFieldBackground(child: SizedBox.shrink()),
          ),
        ),
      );

      expect(_baseOf(tester), const Color(0xFF120323));
    });
  });

  testWidgets('paints nothing rather than dividing by a zero-sized window',
      (tester) async {
    await tester.pumpWidget(_host(animate: true, size: Size.zero));
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('animates, and tears down clean', (tester) async {
    await tester.pumpWidget(_host(animate: true));
    await tester.pump(const Duration(seconds: 1));

    expect(
      find.descendant(
        of: find.byType(OrbFieldBackground),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );

    // Unmounting is the assertion: a drift timer left running past the tree
    // would trip the pending-timer check at teardown.
    await tester.pumpWidget(const SizedBox.shrink());

    expect(tester.takeException(), isNull);
  });
}
