import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/daily_prayer_times.dart';
import '../models/focus_session.dart';
import 'prayer_window_providers.dart';

/// The focus session currently running, or null when none is.
///
/// Intentionally in-memory only: a focus session is a "right now" state, and
/// resurrecting a stale one from disk after a relaunch would be wrong.
class FocusSessionController extends Notifier<FocusSession?> {
  @override
  FocusSession? build() => null;

  /// Starts a session for [prayer] running until [endsAt]. Starting one
  /// while another is running replaces it.
  void start({required PrayerLabel prayer, required DateTime endsAt}) {
    final now = DateTime.now();
    state = FocusSession(
      prayer: prayer,
      startedAt: now,
      // Guard against a window that has already closed, which would
      // otherwise create a session that is finished the moment it starts.
      endsAt: endsAt.isAfter(now) ? endsAt : now.add(const Duration(minutes: 10)),
    );
  }

  /// Starts a session matching the prayer state right now: for the rest of
  /// the active lockout if one is underway, otherwise a short session ahead
  /// of the next Adhan.
  void startFromCurrentPrayerState(PrayerNowState prayerState) {
    final lockout = prayerState.activeLockout;
    if (lockout != null) {
      start(prayer: lockout.prayer, endsAt: lockout.end);
      return;
    }
    start(
      prayer: prayerState.nextAdhan.prayer,
      endsAt: prayerState.nextAdhan.time,
    );
  }

  void end() => state = null;
}

final focusSessionProvider =
    NotifierProvider<FocusSessionController, FocusSession?>(
  FocusSessionController.new,
);

/// Whether a focus session is currently running — the flag the app shell
/// watches to decide whether to lay the focus overlay over everything.
final isFocusSessionActiveProvider = Provider<bool>((ref) {
  return ref.watch(focusSessionProvider) != null;
});
