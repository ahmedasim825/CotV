import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The deep-black canvas with two soft, out-of-focus amber glow orbs —
/// painted once as a static backdrop (never inside scrolling content, and
/// never re-blurred per frame) so it stays essentially free at runtime.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: context.palette.background),
        Positioned(
          top: -140,
          right: -100,
          child: _Glow(diameter: 360, color: context.palette.accentDeep.withValues(alpha: 0.35)),
        ),
        Positioned(
          bottom: -160,
          left: -120,
          child: _Glow(diameter: 320, color: context.palette.accent.withValues(alpha: 0.16)),
        ),
        child,
      ],
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
