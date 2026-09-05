import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// What Milo's face is doing.
///
/// Ordered as the tap cycle runs, so [next] is just the following value.
enum MiloEyeState {
  /// Curved downward arcs — `◡ ◡`. Milo at rest.
  eyesClosed,

  /// Dual vertical ovals — `• •`. Milo listening.
  eyesOpen,

  /// Asymmetric, slightly tilted ovals. Milo working on something.
  thinking;

  MiloEyeState get next => values[(index + 1) % values.length];

  /// Announced by [MiloOrbWidget]'s [Semantics] so the state is not carried
  /// by the drawing alone.
  String get description {
    switch (this) {
      case MiloEyeState.eyesClosed:
        return 'resting';
      case MiloEyeState.eyesOpen:
        return 'listening';
      case MiloEyeState.thinking:
        return 'thinking';
    }
  }
}

/// Milo's avatar: a breathing radial aura with a painted pair of eyes.
///
/// The aura is built entirely from [AppPalette] tokens rather than a
/// per-theme `switch`, so all six themes are covered by the same code and a
/// seventh would be too. `accent` carries the core, `secondary` the warm rim
/// and `glowPrimary` the falloff, which is exactly the emerald/gold,
/// lamplight-amber, system-blue, brushed-grey, white and pastel readings the
/// themes are each built around.
///
/// Tapping cycles [MiloEyeState] — a preview affordance while the dashboard
/// is still frontend-only. [onStateChanged] reports each change, and
/// [initialState] sets where the cycle starts.
class MiloOrbWidget extends StatefulWidget {
  const MiloOrbWidget({
    super.key,
    this.diameter = 128,
    this.initialState = MiloEyeState.eyesClosed,
    this.onStateChanged,
  });

  final double diameter;
  final MiloEyeState initialState;

  /// Fires after each tap with the state just moved into.
  final ValueChanged<MiloEyeState>? onStateChanged;

  @override
  State<MiloOrbWidget> createState() => _MiloOrbWidgetState();
}

class _MiloOrbWidgetState extends State<MiloOrbWidget>
    with TickerProviderStateMixin {
  /// The slow scale pulse on the aura. Runs forever, so nothing in a test
  /// should `pumpAndSettle` over this widget.
  late final AnimationController _breath;

  /// Drives the shape interpolation between two eye states, so a tap blinks
  /// rather than cuts.
  late final AnimationController _morph;

  late MiloEyeState _state = widget.initialState;
  late MiloEyeState _previous = widget.initialState;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
    _morph = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      value: 1,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery is only readable from here on, and the reduced-motion
    // answer can change while the widget is alive, so this re-runs rather
    // than being decided once in initState.
    if (context.motion.isReduced) {
      _breath.stop();
      _breath.value = 0.5;
    } else if (!_breath.isAnimating) {
      _breath.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    _morph.dispose();
    super.dispose();
  }

  void _cycle() {
    setState(() {
      _previous = _state;
      _state = _state.next;
    });
    if (context.motion.isReduced) {
      _morph.value = 1;
    } else {
      _morph.forward(from: 0);
    }
    widget.onStateChanged?.call(_state);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final size = widget.diameter;

    // On the one light theme the dark-theme alphas read as grime on a warm
    // white ground, so the whole aura is pulled back rather than recoloured.
    final intensity = palette.isDark ? 1.0 : 0.55;

    return Semantics(
      button: true,
      label: 'Milo, ${_state.description}. Tap to change.',
      child: GestureDetector(
        onTap: _cycle,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          // The aura bleeds well past the core, so the box is roomier than
          // the orb itself and the glow is not clipped by a tight parent.
          width: size * 1.6,
          height: size * 1.6,
          child: Center(
            child: AnimatedBuilder(
              animation: Listenable.merge([_breath, _morph]),
              builder: (context, _) {
                final breath = Curves.easeInOut.transform(_breath.value);
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Transform.scale(
                      // A 4% swing: enough to read as breathing across a
                      // 3.2s cycle, small enough not to jostle the layout.
                      scale: 0.96 + breath * 0.08,
                      child: _Aura(
                        diameter: size * 1.55,
                        palette: palette,
                        intensity: intensity,
                      ),
                    ),
                    _Core(
                      diameter: size,
                      palette: palette,
                      state: _state,
                      previous: _previous,
                      morph: Curves.easeOutCubic.transform(_morph.value),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// The soft radial falloff around the orb.
class _Aura extends StatelessWidget {
  const _Aura({
    required this.diameter,
    required this.palette,
    required this.intensity,
  });

  final double diameter;
  final AppPalette palette;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              palette.accent.withValues(alpha: 0.34 * intensity),
              palette.glowPrimary.withValues(
                alpha: palette.glowPrimary.a * 0.9 * intensity,
              ),
              palette.secondary.withValues(alpha: 0.10 * intensity),
              palette.accent.withValues(alpha: 0),
            ],
            stops: const [0.0, 0.36, 0.62, 1.0],
          ),
          boxShadow: [
            BoxShadow(
              color: palette.accent.withValues(alpha: 0.22 * intensity),
              blurRadius: diameter * 0.42,
              spreadRadius: diameter * 0.02,
            ),
            BoxShadow(
              color: palette.secondary.withValues(alpha: 0.12 * intensity),
              blurRadius: diameter * 0.30,
            ),
          ],
        ),
      ),
    );
  }
}

/// The orb body, with the eyes painted on it.
class _Core extends StatelessWidget {
  const _Core({
    required this.diameter,
    required this.palette,
    required this.state,
    required this.previous,
    required this.morph,
  });

  final double diameter;
  final AppPalette palette;
  final MiloEyeState state;
  final MiloEyeState previous;
  final double morph;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          // Lit from above-left, so the sphere reads as a sphere rather
          // than a flat disc.
          center: const Alignment(-0.3, -0.4),
          radius: 1.05,
          colors: [
            Color.alphaBlend(
              palette.accent.withValues(alpha: palette.isDark ? 0.30 : 0.20),
              palette.surfaceRaised,
            ),
            palette.surface,
          ],
        ),
        border: Border.all(
          color: palette.accent.withValues(alpha: palette.isDark ? 0.42 : 0.30),
          width: 1.2,
        ),
      ),
      child: CustomPaint(
        painter: _EyesPainter(
          state: state,
          previous: previous,
          morph: morph,
          color: palette.accentBright,
        ),
      ),
    );
  }
}

/// The three eye shapes, and the interpolation between whichever two a tap
/// moved across.
///
/// Every shape is described by the same four numbers — height, width, tilt
/// and vertical offset, per eye — so a transition is a plain lerp of those
/// rather than a special case per pair.
class _EyesPainter extends CustomPainter {
  const _EyesPainter({
    required this.state,
    required this.previous,
    required this.morph,
    required this.color,
  });

  final MiloEyeState state;
  final MiloEyeState previous;

  /// 0 at [previous], 1 at [state].
  final double morph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final from = _EyeGeometry.of(previous);
    final to = _EyeGeometry.of(state);
    final g = _EyeGeometry.lerp(from, to, morph.clamp(0.0, 1.0));

    final gap = size.width * 0.22;
    final centreY = size.height * 0.5;
    final left = Offset(size.width * 0.5 - gap, centreY + g.leftOffsetY * size.height);
    final right = Offset(size.width * 0.5 + gap, centreY + g.rightOffsetY * size.height);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.075
      ..strokeCap = StrokeCap.round;

    _drawEye(canvas, size, left, paint, g.width, g.leftHeight, g.leftTilt, g.closedness);
    _drawEye(canvas, size, right, paint, g.width, g.rightHeight, g.rightTilt, g.closedness);
  }

  /// One eye, blended between a downward arc (`closedness` 1) and a filled
  /// vertical oval (`closedness` 0).
  void _drawEye(
    Canvas canvas,
    Size size,
    Offset centre,
    Paint stroke,
    double widthFactor,
    double heightFactor,
    double tilt,
    double closedness,
  ) {
    final w = size.width * widthFactor;
    final h = size.height * heightFactor;

    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    if (tilt != 0) canvas.rotate(tilt);

    if (closedness > 0.02) {
      // The closed arc: a shallow smile drawn across the eye's box. Its own
      // opacity carries it out as the oval comes in, so the two never both
      // read at full strength mid-blink.
      final arc = Rect.fromCenter(center: Offset.zero, width: w * 1.6, height: h * 1.9);
      canvas.drawArc(
        arc,
        math.pi * 0.15,
        math.pi * 0.7,
        false,
        Paint()
          ..color = stroke.color.withValues(alpha: closedness)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke.strokeWidth
          ..strokeCap = StrokeCap.round,
      );
    }

    if (closedness < 0.98) {
      final oval = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: w, height: h),
        Radius.circular(w / 2),
      );
      canvas.drawRRect(
        oval,
        Paint()
          ..color = stroke.color.withValues(alpha: 1 - closedness)
          ..style = PaintingStyle.fill,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_EyesPainter old) =>
      old.state != state ||
      old.previous != previous ||
      old.morph != morph ||
      old.color != color;
}

/// The numbers behind one eye state, as fractions of the orb's box.
@immutable
class _EyeGeometry {
  const _EyeGeometry({
    required this.width,
    required this.leftHeight,
    required this.rightHeight,
    required this.leftTilt,
    required this.rightTilt,
    required this.leftOffsetY,
    required this.rightOffsetY,
    required this.closedness,
  });

  final double width;
  final double leftHeight;
  final double rightHeight;

  /// Radians. Positive tilts the top of the eye to the right.
  final double leftTilt;
  final double rightTilt;

  /// Fraction of the orb height each eye sits off centre.
  final double leftOffsetY;
  final double rightOffsetY;

  /// 1 draws the closed arc, 0 the open oval.
  final double closedness;

  static _EyeGeometry of(MiloEyeState state) {
    switch (state) {
      case MiloEyeState.eyesClosed:
        return const _EyeGeometry(
          width: 0.13,
          leftHeight: 0.05,
          rightHeight: 0.05,
          leftTilt: 0,
          rightTilt: 0,
          leftOffsetY: 0,
          rightOffsetY: 0,
          closedness: 1,
        );
      case MiloEyeState.eyesOpen:
        return const _EyeGeometry(
          width: 0.115,
          leftHeight: 0.30,
          rightHeight: 0.30,
          leftTilt: 0,
          rightTilt: 0,
          leftOffsetY: 0,
          rightOffsetY: 0,
          closedness: 0,
        );
      case MiloEyeState.thinking:
        // Asymmetric and tilted: the right eye narrows and rides up, which
        // is what reads as "considering" rather than "staring".
        return const _EyeGeometry(
          width: 0.11,
          leftHeight: 0.30,
          rightHeight: 0.21,
          leftTilt: -0.16,
          rightTilt: 0.22,
          leftOffsetY: 0.015,
          rightOffsetY: -0.035,
          closedness: 0,
        );
    }
  }

  static _EyeGeometry lerp(_EyeGeometry a, _EyeGeometry b, double t) {
    double l(double x, double y) => x + (y - x) * t;
    return _EyeGeometry(
      width: l(a.width, b.width),
      leftHeight: l(a.leftHeight, b.leftHeight),
      rightHeight: l(a.rightHeight, b.rightHeight),
      leftTilt: l(a.leftTilt, b.leftTilt),
      rightTilt: l(a.rightTilt, b.rightTilt),
      leftOffsetY: l(a.leftOffsetY, b.leftOffsetY),
      rightOffsetY: l(a.rightOffsetY, b.rightOffsetY),
      closedness: l(a.closedness, b.closedness),
    );
  }
}
