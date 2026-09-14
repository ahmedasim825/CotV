// The search pill on the iOS path.
//
// `home_header_test.dart` pins the Windows shape — magnifier, "Search..", and
// the mode spelled out beside the caret. This file pins the mock's shape, and
// the one structural rule both share: exactly one AnimatedContainer, because
// that is what the halo assertion addresses by type.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cotv/src/providers/clock_providers.dart';
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

  testWidgets('the pill is the same shape and fill the Windows path uses', (
    tester,
  ) async {
    await _pump(tester);

    // Two tests used to live here: one pinning a single AnimatedContainer for
    // the halo assertion to address by type, and one checking the halo lit
    // under the caret. The halo and the animation are both gone, so what is
    // worth pinning now is that iOS did not keep its own appearance — the pill
    // is one set of values on both paths.
    final box = tester.widget<Container>(
      find.descendant(
        of: find.byType(HomeSearchBar),
        matching: find.byType(Container),
      ),
    );
    final decor = box.decoration! as BoxDecoration;

    expect(decor.boxShadow, anyOf(isNull, isEmpty));
    expect(decor.color, const Color(0x05D9D9D9));
    expect((decor.border! as Border).top.color, const Color(0x1AFFFFFF));
    expect(decor.borderRadius, BorderRadius.circular(10));

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final lit =
        tester
                .widget<Container>(
                  find.descendant(
                    of: find.byType(HomeSearchBar),
                    matching: find.byType(Container),
                  ),
                )
                .decoration!
            as BoxDecoration;
    expect(lit.boxShadow, anyOf(isNull, isEmpty), reason: 'no halo any more');
  });
}
