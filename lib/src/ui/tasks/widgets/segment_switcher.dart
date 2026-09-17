import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';

/// The Tasks / Reminders switch at the top of the tasks pane.
///
/// A pill slides between the labels and resizes to whichever one it lands on,
/// so the two segments keep their natural widths rather than being forced into
/// equal columns the way `SegmentedButton` forces them.
///
/// Both label widths are measured with a [TextPainter] during build rather
/// than read back off [GlobalKey]s after layout. The pill is positioned
/// arithmetically from those widths, which means it is in the right place on
/// the very first frame — a post-frame measurement would paint one frame with
/// the pill at the origin.
class SegmentSwitcher extends StatelessWidget {
  const SegmentSwitcher({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const double _gap = 6;
  static const double _padH = 14;
  static const double _height = 28;
  static const double _radius = 8;

  TextStyle _labelStyle(BuildContext context) =>
      context.typography.ui(size: 12.5, weight: FontWeight.w600);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final style = _labelStyle(context);

    final widths = [
      for (final label in labels) _measure(label, style, context) + _padH * 2,
    ];

    // Where each pill starts, given the ones before it.
    double leftOf(int index) {
      var left = 0.0;
      for (var i = 0; i < index; i++) {
        left += widths[i] + _gap;
      }
      return left;
    }

    return SizedBox(
      height: _height,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: selectedIndex.toDouble()),
        duration: context.motion.fast,
        // Ease-out, not `AppMotion.spring`. The app reserves `Curves.easeOut`
        // for hover transitions everywhere else; this control is the one
        // deliberate exception, because the design calls for the pill to
        // arrive rather than settle.
        curve: Curves.easeOut,
        builder: (context, position, _) {
          // Interpolated between the two neighbours the animation is
          // currently between, so the pill's width tracks its travel instead
          // of snapping to the destination's width at the start.
          final lower = position.floor().clamp(0, labels.length - 1);
          final upper = position.ceil().clamp(0, labels.length - 1);
          final t = position - lower;
          final left = _lerp(leftOf(lower), leftOf(upper), t);
          final width = _lerp(widths[lower], widths[upper], t);

          return Stack(
            children: [
              Positioned(
                left: left,
                width: width,
                top: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.segmentActive,
                    borderRadius: BorderRadius.circular(_radius),
                  ),
                ),
              ),
              for (var i = 0; i < labels.length; i++)
                Positioned(
                  left: leftOf(i),
                  width: widths[i],
                  top: 0,
                  bottom: 0,
                  child: _Label(
                    label: labels[i],
                    style: style,
                    // Tweened off the same position, so a label brightens as
                    // the pill reaches it rather than at the moment of the
                    // tap.
                    selectedAmount: (1 - (position - i).abs()).clamp(0.0, 1.0),
                    onTap: () {
                      if (i == selectedIndex) return;
                      HapticFeedback.selectionClick();
                      onSelected(i);
                    },
                    isSelected: i == selectedIndex,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  double _measure(String text, TextStyle style, BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return painter.width;
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

class _Label extends StatelessWidget {
  const _Label({
    required this.label,
    required this.style,
    required this.selectedAmount,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final TextStyle style;

  /// 0 when the pill is elsewhere, 1 when it has arrived.
  final double selectedAmount;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: Text(
            label,
            // Colour-lerped rather than cross-faded: an `AnimatedSwitcher`
            // here would push a save layer, and this sits above the nav bar's
            // backdrop filter.
            style: style.copyWith(
              color: Color.lerp(
                palette.textMuted,
                palette.textPrimary,
                selectedAmount,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
