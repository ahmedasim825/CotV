import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/ambient_providers.dart';
import '../theme/app_theme.dart';

/// The app's ground: a flat base colour with three soft violet orbs drifting
/// over it.
///
/// Mounted once, in `MaterialApp.builder`, so it sits below the [Navigator] —
/// the ground is continuous across route pushes and drawer opens. Every
/// [Scaffold] in the app sets `backgroundColor: Colors.transparent`, which is
/// what lets it through; that is load-bearing rather than incidental.
///
/// **The orbs are not decoration.** A dashboard card is white at 2% behind a
/// hairline rim, so most of what a resting card shows is whatever the ground
/// paints under it. On iOS the card is glass instead, blurring this field
/// rather than letting it through unchanged — which raises the stakes on the
/// orbs rather than lowering them, since a blurred flat colour is just a flat
/// colour.
///
/// The base used to shift with the hour, cross-fading through four time-of-day
/// windows. It no longer does: the base is one colour and the orbs are one set.
/// What survives from that design is the drift alone.
///
/// This drew its orbs with the `fluid_background` package until profiling on
/// Windows measured the ground holding the app at 9-46fps while idle. What the
/// measurements actually showed, in order: the blur radius was not the cost
/// (sigma 30 to 2 changed nothing), and neither was the [BackdropFilter] that
/// package forced (painting the same orbs directly was no faster). The cost is
/// fill rate — three soft circles covering several times the window's own pixel
/// count, on an integrated GPU running Impeller's OpenGLES backend. So the two
/// things that matter here are how *often* the field repaints
/// ([_repaintInterval]) and how *large* the orbs are; both are tuned down from
/// what the design would otherwise ask for.
///
/// Note what those measurements did *not* find: blur was not the cost. Sigma
/// 30 to 2 changed nothing, and painting without the [BackdropFilter] at all
/// was no faster. It is shading area that hurts. So none of this is evidence
/// against the glass cards on iOS, which blur a far smaller area on a
/// Metal-backed GPU — see `GlassCard.glass`.
class OrbFieldBackground extends ConsumerStatefulWidget {
  const OrbFieldBackground({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<OrbFieldBackground> createState() => _OrbFieldBackgroundState();
}

class _OrbFieldBackgroundState extends ConsumerState<OrbFieldBackground> {
  /// How far through the drift cycle the field is, in `[0, 1)`.
  ///
  /// Advanced by [_ticker] rather than by an [AnimationController], because a
  /// controller notifies every frame and the orbs do not need it: see
  /// [_repaintInterval].
  final ValueNotifier<double> _phase = ValueNotifier<double>(0);

  Timer? _ticker;
  final Stopwatch _elapsed = Stopwatch();

  @override
  void dispose() {
    _ticker?.cancel();
    _phase.dispose();
    super.dispose();
  }

  void _startDrift() {
    if (_ticker != null) return;
    _elapsed.start();
    _ticker = Timer.periodic(_repaintInterval, (_) {
      _phase.value =
          (_elapsed.elapsedMilliseconds / _driftPeriod.inMilliseconds) % 1;
    });
  }

  void _stopDrift() {
    _ticker?.cancel();
    _ticker = null;
    _elapsed.stop();
  }

  @override
  Widget build(BuildContext context) {
    final bool animate =
        ref.watch(ambientAnimationProvider) && !context.motion.isReduced;

    if (animate) {
      _startDrift();
    } else {
      _stopDrift();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Read off the theme rather than written here, so a `buildAppTheme`
        // caller can still override the ground without reaching into this
        // widget.
        ColoredBox(color: Theme.of(context).scaffoldBackgroundColor),
        RepaintBoundary(
          child: CustomPaint(painter: _OrbFieldPainter(phase: _phase)),
        ),
        widget.child,
      ],
    );
  }
}

/// The orbs, in paint order.
///
/// One colour at an eighth alpha, three times over. They differ only by the
/// path each one takes ([_kPaths]); where two overlap the alpha compounds,
/// which is what keeps a single hue from reading as one flat wash.
///
/// Each orb is about `0.175 * longestSide` across and three of them cover most
/// of the window, so alpha here is not a local tint — it sets how violet the
/// whole app looks. This started at half alpha, where the ground read as
/// violet rather than as the near-black it is meant to be, and came down twice
/// from there.
const List<Color> _kOrbColours = <Color>[
  Color(0x207005BB),
  Color(0x207005BB),
  Color(0x207005BB),
];

/// One full pass of the drift. Long enough that no orb appears to be heading
/// anywhere in particular.
const Duration _driftPeriod = Duration(seconds: 120);

/// How often the orb field is repainted.
///
/// Not every frame, deliberately. Filling three circles of `0.6 x longestSide`
/// costs roughly four times the window's own pixel count in overdraw, and
/// profiling on Windows put that at 44-61ms of raster per frame — three times
/// the budget on its own. Over a [_driftPeriod] this long an orb travels about
/// 50 logical pixels a second, so repainting at this rate moves it ~4px a step:
/// below noticing on a soft gradient, and the [RepaintBoundary] above composites
/// the cached texture on the frames in between.
const Duration _repaintInterval = Duration(milliseconds: 83);

/// Per-orb path shape: how many drift cycles each axis completes, the phase
/// that separates the orbs, and the phase of the size breath.
///
/// The frequencies are whole numbers so every orb closes its loop exactly when
/// [_driftPeriod] wraps; they are coprime across orbs so the three never fall
/// into step with each other.
const List<({int fx, int fy, double phase, double sizePhase})> _kPaths = [
  (fx: 1, fy: 2, phase: 0.0, sizePhase: 0.0),
  (fx: 2, fy: 1, phase: 2.1, sizePhase: 1.7),
  (fx: 3, fy: 2, phase: 4.2, sizePhase: 3.4),
];

class _OrbFieldPainter extends CustomPainter {
  _OrbFieldPainter({
    required this.phase,
    // Painting is driven straight off this rather than by rebuilding the
    // widget: nothing above this needs to know the orbs moved.
  }) : super(repaint: phase);

  final ValueListenable<double> phase;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final double v = phase.value;

    // Scaled to the window rather than fixed, and deliberately smaller than it
    // wants to be. Fill cost scales with area, and this is the term that
    // decides whether the ground fits in a frame: at 0.6 the three orbs shaded
    // roughly four times the window's own pixel count per repaint and held the
    // raster thread at 44-61ms. The corners sit closer to flat base colour as a
    // result — that is the trade being made.
    final double base = size.longestSide * 0.35;

    for (int i = 0; i < _kOrbColours.length && i < _kPaths.length; i++) {
      final path = _kPaths[i];
      final double angleX = 2 * math.pi * path.fx * v + path.phase;
      final double angleY = 2 * math.pi * path.fy * v + path.phase;

      final Offset centre = Offset(
        (0.5 + 0.40 * math.sin(angleX)) * size.width,
        (0.5 + 0.40 * math.cos(angleY)) * size.height,
      );

      // The breath that kept the field from reading as three rigid discs.
      final double radius =
          base * 0.5 * (1 + 0.18 * math.sin(2 * math.pi * v + path.sizePhase));

      final Color colour = _kOrbColours[i];
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [colour, colour.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: centre, radius: radius)),
      );
    }
  }

  // The colours and the paths are compile-time constants now, so two painters
  // of this type are always interchangeable; repaints come from `phase` alone.
  @override
  bool shouldRepaint(_OrbFieldPainter old) => false;
}
