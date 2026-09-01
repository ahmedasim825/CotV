import 'package:flutter/widgets.dart';

/// Maps times on a single calendar day to vertical offsets on the timeline.
///
/// One place owns the time-to-pixels conversion so the hour rules, the
/// blocks and the current-time indicator can never disagree about where a
/// given minute sits.
@immutable
class TimelineGeometry {
  const TimelineGeometry({
    required this.dayStart,
    required this.hourExtent,
    this.gutterWidth = 56,
  });

  /// Midnight of the day being drawn.
  final DateTime dayStart;

  /// Vertical pixels per hour.
  final double hourExtent;

  /// Width of the hour-label column on the left.
  final double gutterWidth;

  static const int hoursPerDay = 24;

  double get pixelsPerMinute => hourExtent / 60;

  /// Full scrollable height of a 24-hour day.
  double get totalExtent => hourExtent * hoursPerDay;

  /// Vertical offset of [time], clamped to the day so a block running past
  /// midnight is pinned to the bottom edge rather than drawn off-canvas.
  double offsetOf(DateTime time) {
    final minutes = time.difference(dayStart).inMinutes.toDouble();
    return (minutes * pixelsPerMinute).clamp(0.0, totalExtent);
  }

  /// Height for a block spanning [start] to [end], floored at
  /// [minimumBlockExtent] so a very short block stays tappable and legible.
  double extentBetween(DateTime start, DateTime end) {
    final raw = offsetOf(end) - offsetOf(start);
    return raw < minimumBlockExtent ? minimumBlockExtent : raw;
  }

  /// Smallest height a block is ever drawn at — roughly a two-line card.
  static const double minimumBlockExtent = 44;
}
