import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The app's ground: a slate fill, a soft white wash falling from the
/// top-left corner, and two out-of-focus violet glow orbs bled in from the
/// corners.
///
/// The wash is an overlay rather than the light end of a background ramp: a
/// literal `#FFFFFF`-to-`#1B252E` gradient across the window would leave the
/// upper half near-white, which is not the design.
///
/// **The orbs are not decoration — they are what makes the glass read as
/// glass.** Every dashboard card is a [GlassCard], and a `BackdropFilter`
/// blurs whatever is painted behind it. Behind a perfectly flat fill it has
/// nothing to sample: blurring one colour returns that same colour, the
/// refraction disappears, and the cards collapse into flat plates with a
/// border. These two orbs give the backdrop the tonal variation the blur
/// needs, so a card sitting over one picks up its bleed and reads as a sheet
/// of glass rather than a painted rectangle.
///
/// They are positioned off-canvas on purpose — only the falloff reaches the
/// content area, so nothing competes with the top-left light source. Painted
/// once as a static backdrop, never inside scrolling content and never
/// re-blurred per frame, so they stay essentially free at runtime.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return DecoratedBox(
      decoration: BoxDecoration(color: palette.background),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Upper right, behind the music widget and the first card row.
          Positioned(
            top: -180,
            right: -140,
            child: _Glow(
              diameter: 460,
              color: palette.accent.withValues(alpha: 0.15),
            ),
          ),
          // Lower left, behind the Milo dock and the second card row. Lighter
          // than its partner so the two read as one source falling off, not
          // as a pair.
          Positioned(
            bottom: -200,
            left: -160,
            child: _Glow(
              diameter: 420,
              color: palette.accentBright.withValues(alpha: 0.09),
            ),
          ),
          // The top-left light source, over the orbs so it stays the brightest
          // thing on the canvas.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.12),
                  Colors.white.withValues(alpha: 0.0),
                ],
                stops: const [0.0, 0.40],
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.diameter, required this.color});

  final double diameter;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
