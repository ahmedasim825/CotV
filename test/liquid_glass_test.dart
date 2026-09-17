// The Liquid Glass material, at the widget level.
//
// Everything optical about it lives in a fragment shader, and a fragment
// shader is exactly the part a widget test cannot see: `flutter_test` runs
// without Impeller, so `ImageFilter.isShaderFilterSupported` is false and
// there is no program to load. That is not a gap in the coverage — it is the
// single most important thing to pin. Every test in this file runs the same
// path an iPhone runs when the shader is missing, and what they assert is
// that the fallback is a deliberate material rather than a hole.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show BackdropFilterLayer;
import 'package:flutter_test/flutter_test.dart';

import 'package:cotv/src/ui/components/liquid_glass.dart';
import 'package:cotv/src/ui/theme/app_theme.dart';

Future<void> pumpGlass(
  WidgetTester tester, {
  Widget? scopeOverride,
  double radius = 28,
}) async {
  final Widget glass = LiquidGlass(
    radius: radius,
    child: const SizedBox(width: 240, height: 56),
  );

  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme().copyWith(platform: TargetPlatform.iOS),
      home: Scaffold(
        body: Center(child: scopeOverride ?? glass),
      ),
    ),
  );
}

void main() {
  group('without a shader', () {
    testWidgets('renders, and takes its child\'s size', (tester) async {
      await pumpGlass(tester);

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(LiquidGlass)), const Size(240, 56));
    });

    testWidgets('still blurs its backdrop', (tester) async {
      await pumpGlass(tester);

      // The blur is not a fallback *for* the shader — it is the shader's own
      // input, and it stands alone when there is no shader to wrap it in. If
      // this ever finds nothing, the material has stopped degrading and
      // started disappearing.
      final backdrops = tester.layers.whereType<BackdropFilterLayer>();
      expect(backdrops, hasLength(1));
      expect(backdrops.single.filter, isNotNull);
    });

    testWidgets('keeps its own backdrop rather than joining a group',
        (tester) async {
      await pumpGlass(tester);

      // A control overlaps scrolling content by definition, and two
      // overlapping filters sharing a backdrop key draw as though only one
      // applied. This surface must never be grouped.
      expect(
        tester.layers.whereType<BackdropFilterLayer>().single.backdropKey,
        isNull,
      );
    });

    testWidgets('draws the bevel the shader would otherwise compute',
        (tester) async {
      await pumpGlass(tester);

      // Two decorations: the fill and rim, plus the lit top edge that stands
      // in for the shader's per-pixel rim specular. With a shader present the
      // second one is not drawn, because a straight lit line laid over a
      // computed rim reads as a seam.
      final decorations = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(LiquidGlass),
              matching: find.byType(DecoratedBox),
            ),
          )
          .toList();

      final foreground = decorations.where(
        (box) => box.position == DecorationPosition.foreground,
      );
      expect(foreground, hasLength(1));

      final border = (foreground.single.decoration as BoxDecoration).border!;
      expect(border.top.color, kPalette.innerHighlight);
      expect(border.bottom, BorderSide.none);
    });
  });

  testWidgets('never clips through a save layer', (tester) async {
    await pumpGlass(tester);

    // `Clip.antiAliasWithSaveLayer` would push the very save layer that stops
    // the filter underneath from seeing the page — the same constraint
    // GlassCard carries, arrived at from the other direction.
    final clip = tester.widget<ClipRRect>(
      find
          .descendant(
            of: find.byType(LiquidGlass),
            matching: find.byType(ClipRRect),
          )
          .first,
    );
    expect(clip.clipBehavior, Clip.antiAlias);
  });

  testWidgets('a scope with no program is the same as no scope at all',
      (tester) async {
    await pumpGlass(
      tester,
      scopeOverride: const LiquidGlassScope(
        program: null,
        child: LiquidGlass(
          radius: 28,
          child: SizedBox(width: 240, height: 56),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      find.descendant(
        of: find.byType(LiquidGlass),
        matching: find.byType(DecoratedBox),
      ),
      findsNWidgets(2),
    );
  });

  test('loading the program asks the engine before it asks the bundle',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();

    // Under `flutter_test` the shader is not in the asset bundle at all, so
    // reaching for it would throw rather than return the null that means
    // "draw the fallback". The support check has to come first, and this is
    // the test that keeps it there: if the order is ever swapped, this fails
    // with a missing-asset exception instead of returning null.
    await expectLater(loadLiquidGlassProgram(), completion(isNull));
  });
}
