// The search pill on the iOS path.
//
// `home_header_test.dart` pins the Windows shape — magnifier, "Search..", the
// mode spelled out beside the caret, and a 10pt-cornered slab. This file pins
// the mock's shape, and the place the two paths deliberately diverge: the
// field is a control, so on iOS it wears the control layer's material rather
// than Windows' cut-out rectangle.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cotv/src/providers/clock_providers.dart';
import 'package:cotv/src/ui/components/liquid_glass.dart';
import 'package:cotv/src/ui/home/widgets/home_search_bar.dart';
import 'package:cotv/src/ui/theme/app_theme.dart';
import 'package:cotv/src/ui/widgets/ph_light_icons.dart';

final _now = DateTime(2026, 3, 17, 14, 30);

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [currentMinuteProvider.overrideWithValue(_now)],
      child: MaterialApp(
        theme: buildAppTheme().copyWith(platform: TargetPlatform.iOS),
        home: const Scaffold(
          endDrawer: Drawer(child: Text('Milo drawer')),
          body: Center(child: HomeSearchBar()),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('the mode is the placeholder, not a label beside the caret', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Search with Milo'), findsOneWidget);
    expect(find.text('Search..'), findsNothing);
  });

  testWidgets('the magnifier is gone and the caret is the only control', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.byIcon(PhLight.magnifyingGlass), findsNothing);
    expect(find.byIcon(PhLight.caretDown), findsOneWidget);
  });

  testWidgets('the caret keeps a full touch target without a label', (
    tester,
  ) async {
    await _pump(tester);

    final caret = tester.getSize(
      find
          .ancestor(
            of: find.byIcon(PhLight.caretDown),
            matching: find.byType(SizedBox),
          )
          .first,
    );

    expect(caret.width, greaterThanOrEqualTo(minTouchTarget));
    expect(caret.height, greaterThanOrEqualTo(minTouchTarget));
  });

  testWidgets('switching the mode moves the placeholder with it', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.byIcon(PhLight.caretDown));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('Search on Chrome').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The hint is the only thing naming the mode now, so it has to follow it.
    expect(find.text('Search on Chrome'), findsOneWidget);
    expect(find.text('Search with Milo'), findsNothing);
  });

  testWidgets('the pill takes the control material rather than the Windows '
      'slab', (tester) async {
    await _pump(tester);

    // This assertion used to say the opposite — that iOS kept no appearance
    // of its own and the pill was one set of values on both paths. That was
    // right while the app had one material. It has two now: a search field is
    // something you operate, so it goes in the control layer with the nav
    // capsule, and a 10pt-cornered rectangle is the one shape iOS 26 does not
    // put on a home screen. Windows keeps the slab; `home_header_test.dart`
    // still pins it there.
    expect(
      find.descendant(
        of: find.byType(HomeSearchBar),
        matching: find.byType(LiquidGlass),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(HomeSearchBar),
        matching: find.byType(Container),
      ),
      findsNothing,
    );

    // A capsule, which on a 48pt field means a 24pt radius.
    final glass = tester.widget<LiquidGlass>(find.byType(LiquidGlass));
    final Size size = tester.getSize(find.byType(LiquidGlass));
    expect(size.height, 48);
    expect(glass.radius, size.height / 2);
  });

  testWidgets('the pill still looks the same focused as at rest',
      (tester) async {
    await _pump(tester);

    BoxDecoration fill() => tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(LiquidGlass),
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((box) => box.decoration as BoxDecoration)
        .firstWhere((decoration) => decoration.color != null);

    final BoxDecoration resting = fill();
    expect(resting.boxShadow, anyOf(isNull, isEmpty));

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The halo is long gone and the glass does not light under a caret
    // either: the field reads as the same object whether or not it has focus.
    expect(fill().color, resting.color);
    expect(fill().boxShadow, anyOf(isNull, isEmpty), reason: 'no halo');
  });
}
