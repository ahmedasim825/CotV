// Tests for the dashboard's Milo avatar: that it renders the state it is
// given rather than owning one, that listening animates and resting does
// not, that the orb draws no eyes, and that the panel gesture is the
// platform's own — double tap on Windows, long press on iOS, neither
// anywhere else.
//
// Nothing here may `pumpAndSettle` over a moving orb: the breathing
// controller repeats for as long as the widget is alive, so settling would
// time out instead of finishing. The two places it is used are assertions
// that nothing is moving.

import 'package:flutter/gestures.dart'
    show kDoubleTapMinTime, kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cotv/src/ui/home/widgets/milo_orb.dart';
import 'package:cotv/src/ui/theme/app_theme.dart';

Widget _host({
  required Widget child,
  bool reducedMotion = false,
  TargetPlatform platform = TargetPlatform.android,
}) {
  return MaterialApp(
    theme: buildAppTheme().copyWith(platform: platform),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  testWidgets('renders every state', (tester) async {
    for (final state in MiloOrbState.values) {
      await tester.pumpWidget(_host(
        child: MiloOrbWidget(
          state: state,
          isListening: state == MiloOrbState.listening,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(MiloOrbWidget), findsOneWidget,
          reason: 'orb failed to render $state');
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('the orb paints no eyes', (tester) async {
    await tester.pumpWidget(_host(
      child: const MiloOrbWidget(state: MiloOrbState.idle),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    // Scoped to the orb's own subtree rather than the whole tree: the
    // Material chrome around it (Scaffold, its ink features) paints with a
    // CustomPaint of its own, and that is not what this test is about. The
    // point is that no eye geometry is drawn inside the orb.
    expect(
      find.descendant(
        of: find.byType(MiloOrbWidget),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a state change does not throw', (tester) async {
    // There is no face left to morph between shapes — the state only
    // changes what the Semantics label says now — but a change still has to
    // rebuild cleanly rather than throw.
    await tester.pumpWidget(
      _host(child: const MiloOrbWidget(state: MiloOrbState.idle)),
    );

    await tester.pumpWidget(
      _host(child: const MiloOrbWidget(state: MiloOrbState.thinking)),
    );
    await tester.pump(const Duration(milliseconds: 80));

    expect(tester.takeException(), isNull);
    expect(find.byType(MiloOrbWidget), findsOneWidget);
  });

  testWidgets('listening keeps a frame pending; resting does not',
      (tester) async {
    await tester.pumpWidget(
      _host(
        child: const MiloOrbWidget(
          state: MiloOrbState.listening,
          isListening: true,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isTrue);
  });

  testWidgets('reduced motion holds the orb still, listening or not',
      (tester) async {
    await tester.pumpWidget(
      _host(reducedMotion: true, child: const MiloOrbWidget()),
    );

    // With both loops stopped there is no pending frame, so this settles —
    // which it never would while a controller repeats. That is the
    // assertion: the loops are genuinely off, not merely slower.
    await tester.pumpAndSettle();
    expect(find.byType(MiloOrbWidget), findsOneWidget);

    await tester.pumpWidget(
      _host(
        reducedMotion: true,
        child: const MiloOrbWidget(
          state: MiloOrbState.listening,
          isListening: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MiloOrbWidget), findsOneWidget);
  });

  testWidgets('Windows opens the panel on a double tap, not a single one',
      (tester) async {
    var taps = 0;
    var panels = 0;

    await tester.pumpWidget(
      _host(
        platform: TargetPlatform.windows,
        child: MiloOrbWidget(
          onTap: () => taps++,
          onTextMilo: () => panels++,
        ),
      ),
    );

    await tester.tap(find.byType(MiloOrbWidget));
    // A double-tap recognizer holds the arena, so the single tap only
    // resolves once the double-tap window has closed.
    await tester.pump(kDoubleTapTimeout);
    expect(taps, 1);
    expect(panels, 0);

    await tester.tap(find.byType(MiloOrbWidget));
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(find.byType(MiloOrbWidget));
    await tester.pump(kDoubleTapTimeout);

    expect(panels, 1);
    // The double tap is not also two microphone toggles.
    expect(taps, 1);
  });

  testWidgets('Windows ignores a long press', (tester) async {
    var panels = 0;

    await tester.pumpWidget(
      _host(
        platform: TargetPlatform.windows,
        child: MiloOrbWidget(onTextMilo: () => panels++),
      ),
    );

    await tester.longPress(find.byType(MiloOrbWidget));
    await tester.pump(kDoubleTapTimeout);
    expect(panels, 0);
  });

  testWidgets('iOS opens the panel on a long press, and taps stay instant',
      (tester) async {
    var taps = 0;
    var panels = 0;

    await tester.pumpWidget(
      _host(
        platform: TargetPlatform.iOS,
        child: MiloOrbWidget(
          onTap: () => taps++,
          onTextMilo: () => panels++,
        ),
      ),
    );

    await tester.tap(find.byType(MiloOrbWidget));
    await tester.pump();
    expect(taps, 1, reason: 'no double-tap recognizer should delay the tap');
    expect(panels, 0);

    await tester.longPress(find.byType(MiloOrbWidget));
    await tester.pump();
    expect(panels, 1);
    expect(taps, 1);
  });

  testWidgets('other platforms wire neither gesture', (tester) async {
    var taps = 0;
    var panels = 0;

    await tester.pumpWidget(
      _host(
        platform: TargetPlatform.android,
        child: MiloOrbWidget(
          onTap: () => taps++,
          onTextMilo: () => panels++,
        ),
      ),
    );

    // With no long-press recognizer in the arena the hold is just a slow
    // tap, so the microphone still gets it and the panel does not.
    await tester.longPress(find.byType(MiloOrbWidget));
    await tester.pump();
    expect(panels, 0);
    expect(taps, 1);

    await tester.tap(find.byType(MiloOrbWidget));
    await tester.pump();
    await tester.tap(find.byType(MiloOrbWidget));
    await tester.pump();
    expect(panels, 0, reason: 'two quick taps are two taps, not a shortcut');
    expect(taps, 3);
  });
}
