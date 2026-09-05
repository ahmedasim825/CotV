// Tests for the dashboard's Milo avatar: the tap cycle through its three
// eye states, that every theme renders it, and that reduced motion stops
// the breathing loop.
//
// Nothing here may `pumpAndSettle`: the breathing controller repeats for as
// long as the widget is alive, so settling would time out instead of
// finishing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cotv/src/ui/home/widgets/milo_orb.dart';
import 'package:cotv/src/ui/theme/app_theme.dart';

Widget _host({
  required Widget child,
  AppThemeVariant variant = AppThemeVariant.sanctuary,
  bool reducedMotion = false,
}) {
  return MaterialApp(
    theme: buildAppTheme(variant),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  testWidgets('tapping cycles closed -> open -> thinking -> closed',
      (tester) async {
    final seen = <MiloEyeState>[];

    await tester.pumpWidget(
      _host(child: MiloOrbWidget(onStateChanged: seen.add)),
    );

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byType(MiloOrbWidget));
      await tester.pump(const Duration(milliseconds: 300));
    }

    expect(seen, [
      MiloEyeState.eyesOpen,
      MiloEyeState.thinking,
      MiloEyeState.eyesClosed,
    ]);
  });

  testWidgets('starts in the state it was given', (tester) async {
    final seen = <MiloEyeState>[];

    await tester.pumpWidget(
      _host(
        child: MiloOrbWidget(
          initialState: MiloEyeState.thinking,
          onStateChanged: seen.add,
        ),
      ),
    );

    await tester.tap(find.byType(MiloOrbWidget));
    await tester.pump(const Duration(milliseconds: 300));

    // thinking wraps back round to the start of the cycle.
    expect(seen, [MiloEyeState.eyesClosed]);
  });

  testWidgets('renders under every theme', (tester) async {
    for (final variant in AppThemeVariant.values) {
      await tester.pumpWidget(
        _host(variant: variant, child: const MiloOrbWidget()),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.byType(MiloOrbWidget),
        findsOneWidget,
        reason: 'orb failed to render under ${variant.label}',
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('reduced motion holds the orb still', (tester) async {
    await tester.pumpWidget(
      _host(reducedMotion: true, child: const MiloOrbWidget()),
    );

    // With the breathing loop stopped there is no pending frame, so this
    // settles — which it never would while the controller repeats. That is
    // the assertion: the loop is genuinely off, not merely slower.
    await tester.pumpAndSettle();
    expect(find.byType(MiloOrbWidget), findsOneWidget);
  });
}
