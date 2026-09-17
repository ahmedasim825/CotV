import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/calendar_sync_models.dart';
import '../models/daily_prayer_times.dart';
import '../models/prayer_window.dart';
import '../ui/format/time_format.dart';
import 'calendar_providers.dart';
import 'clock_providers.dart';
import 'prayer_providers.dart';
import 'settings_providers.dart';

/// The full prayer picture for one day: validity windows plus the lockout
/// blocks that get synced to the device calendar.
///
/// The lockout blocks come from [CalendarSyncService.buildWindows] rather
/// than being recomputed here, so what the app draws and what a
/// Shortcuts automation reads off the calendar can never drift apart.
///
/// Pass a midnight-normalized date (see [startOfDay]).
final dailyPrayerScheduleProvider =
    Provider.autoDispose.family<DailyPrayerSchedule, DateTime>((ref, date) {
  final timings = ref.watch(dailyPrayerTimesProvider(date));
  final nextDay = ref.watch(
    dailyPrayerTimesProvider(startOfDay(date.add(const Duration(days: 1)))),
  );
  final lockoutDuration = ref.watch(lockoutDurationProvider);
  final syncService = ref.watch(calendarSyncServiceProvider);

  return DailyPrayerSchedule.from(
    timings: timings,
    nextDayFajr: nextDay.fajr,
    lockoutWindows: syncService.buildWindows(
      timings,
      lockoutDuration: lockoutDuration,
    ),
  );
});

/// Live prayer status for *right now*. This is what the lockout banner
/// renders from.
///
/// [activeLockout] is non-null only while the user is inside a lockout
/// block; [activeWindow] is the (longer) validity window, non-null except in
/// the Sunrise-to-Dhuhr gap. [nextAdhan] is never null — it rolls over to
/// tomorrow's Fajr once today's Isha has passed.
class PrayerNowState {
  const PrayerNowState({
    required this.now,
    required this.activeWindow,
    required this.activeLockout,
    required this.nextAdhan,
  });

  final DateTime now;
  final PrayerTimeWindow? activeWindow;
  final PrayerLockoutWindow? activeLockout;
  final AdhanMoment nextAdhan;

  /// True while a prayer lockout is underway — the banner's prominent state.
  bool get isLockedOut => activeLockout != null;

  /// Time until the current lockout ends, or until the next Adhan when the
  /// user is free. Never negative.
  Duration get countdown {
    final target = activeLockout?.end ?? nextAdhan.time;
    final remaining = target.difference(now);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Fraction of the active lockout already elapsed, or null when free.
  double? get lockoutProgress {
    final lockout = activeLockout;
    if (lockout == null) return null;
    final total = lockout.end.difference(lockout.start).inSeconds;
    if (total <= 0) return 1;
    return (now.difference(lockout.start).inSeconds / total).clamp(0.0, 1.0);
  }
}

/// Recomputed every minute from [currentMinuteProvider]; the second-by-second
/// countdown digits are rendered from [nowTickerProvider] at the leaf widget
/// so this heavier derivation doesn't rerun 60 times a minute.
final prayerNowStateProvider = Provider.autoDispose<PrayerNowState>((ref) {
  final now = ref.watch(currentMinuteProvider);
  final today = startOfDay(now);
  final schedule = ref.watch(dailyPrayerScheduleProvider(today));

  final nextAdhan = schedule.nextAdhanAfter(now) ??
      AdhanMoment(
        // Past Isha, so the next Adhan is tomorrow's Fajr.
        prayer: PrayerLabel.fajr,
        time: ref
            .watch(dailyPrayerTimesProvider(
              startOfDay(today.add(const Duration(days: 1))),
            ))
            .fajr,
      );

  // Isha's validity window runs past midnight into the next day's Fajr, so
  // in the small hours the window the user is actually inside belongs to
  // *yesterday's* schedule, not today's.
  var activeWindow = schedule.timeWindowAt(now);
  if (activeWindow == null && now.isBefore(schedule.timings.fajr)) {
    activeWindow = ref
        .watch(dailyPrayerScheduleProvider(
          startOfDay(today.subtract(const Duration(days: 1))),
        ))
        .timeWindowAt(now);
  }

  return PrayerNowState(
    now: now,
    activeWindow: activeWindow,
    activeLockout: schedule.lockoutAt(now),
    nextAdhan: nextAdhan,
  );
});
