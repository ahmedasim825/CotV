import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A horizontal progress meter: a rounded track with a gradient fill that
/// grows into it.
///
/// Replaces [LinearProgressIndicator] wherever the app is showing a share
/// of a total rather than an indeterminate wait. The gradient is what
/// separates the two visually — a flat bar reads as a system control, a
/// graded one as a measurement — and the track is the same 8% wash the
/// donut rings use, so a bar and a ring on the same card agree about what
/// "empty" looks like.
class MeterBar extends StatelessWidget {
  const MeterBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 6,
    this.radius = 8,
    this.track,
  });

  /// 0..1. Values outside that are clamped.
  final double value;

  /// The fill colour. The gradient runs from a faded version of it to this.
  final Color color;

  final double height;
  final double radius;

  /// Defaults to the palette's `meterTrack`.
  final Color? track;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final corner = BorderRadius.circular(radius);

    return SizedBox(
      height: height,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: corner,
        child: ColoredBox(
          color: track ?? palette.meterTrack,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
            duration: context.motion.base,
            curve: AppMotion.spring,
            builder: (context, filled, _) => Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: filled,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: corner,
                    gradient: LinearGradient(
                      colors: [color.withValues(alpha: 0.55), color],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
