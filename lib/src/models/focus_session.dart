import 'daily_prayer_times.dart';

/// An in-app focus session started from the prayer lockout banner.
///
/// This is the app's own quiet-mode overlay. It deliberately does not try to
/// drive iOS Focus modes directly — no public API allows that. The path to
/// real system-level lockout is the "Milo" calendar written by
/// `CalendarSyncService`, which an iOS Shortcuts automation (or Jomo) can
/// watch to flip a Focus mode. This session is what the app itself shows
/// while that is happening.
class FocusSession {
  const FocusSession({
    required this.prayer,
    required this.startedAt,
    required this.endsAt,
  });

  /// The prayer this session was started for.
  final PrayerLabel prayer;

  final DateTime startedAt;

  /// When the session is scheduled to end — normally the end of the prayer
  /// window that triggered it.
  final DateTime endsAt;

  Duration get plannedDuration => endsAt.difference(startedAt);

  bool isFinishedAt(DateTime now) => !now.isBefore(endsAt);

  /// Time left in the session, floored at zero.
  Duration remainingAt(DateTime now) {
    final remaining = endsAt.difference(now);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Progress through the session, clamped to `0.0..1.0`.
  double progressAt(DateTime now) {
    final total = plannedDuration.inSeconds;
    if (total <= 0) return 1;
    return (now.difference(startedAt).inSeconds / total).clamp(0.0, 1.0);
  }
}
