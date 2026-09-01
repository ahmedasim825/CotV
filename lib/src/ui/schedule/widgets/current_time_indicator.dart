import 'package:flutter/material.dart';

import '../../format/time_format.dart';
import '../../theme/app_theme.dart';

/// The "now" line drawn across the timeline: a labelled bead on the left,
/// a hairline rule across the day.
///
/// The line's position is animated by the caller ([AnimatedPositioned]); the
/// pulse here is a slow, low-amplitude breath on the bead only, so the
/// indicator reads as live without becoming a distraction on a screen the
/// user may leave open.
class CurrentTimeIndicator extends StatefulWidget {
  const CurrentTimeIndicator({
    super.key,
    required this.now,
    required this.gutterWidth,
  });

  final DateTime now;
  final double gutterWidth;

  @override
  State<CurrentTimeIndicator> createState() => _CurrentTimeIndicatorState();
}

class _CurrentTimeIndicatorState extends State<CurrentTimeIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Row(
        children: [
          SizedBox(
            width: widget.gutterWidth,
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppPalette.amber,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  formatClock(widget.now),
                  style: AppTypography.ui(
                    size: 10.5,
                    weight: FontWeight.w700,
                    color: AppPalette.onAmber,
                  ),
                ),
              ),
            ),
          ),
          FadeTransition(
            opacity: Tween<double>(begin: 0.45, end: 1.0).animate(_pulse),
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: AppPalette.amberBright,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppPalette.amber.withValues(alpha: 0.6),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 1.5,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppPalette.amber.withValues(alpha: 0.9),
                    AppPalette.amber.withValues(alpha: 0.05),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
