import 'calendar_sync_models.dart';
import 'daily_prayer_times.dart';

/// The stretch during which a given prayer may validly be offered: Fajr
/// until Sunrise, Dhuhr until Asr, and so on, with Isha running through to
/// the next day's Fajr.
///
/// Deliberately distinct from [PrayerLockoutWindow], which is the shorter
/// span this app actually blocks the schedule out for. The timeline paints
/// a [PrayerTimeWindow] as a tinted band (context: "you are inside Asr")
/// and a [PrayerLockoutWindow] as a solid read-only block (a commitment
/// that displaces other work).
class PrayerTimeWindow {
  const PrayerTimeWindow({
    required this.prayer,
    required this.start,
    required this.end,
  });

  final PrayerLabel prayer;
  final DateTime start;
  final DateTime end;

  Duration get duration => end.difference(start);

  /// Half-open: `[start, end)`, so back-to-back windows never both claim
  /// the same instant.
  bool contains(DateTime time) =>
      !time.isBefore(start) && time.isBefore(end);

  /// Time left before this window closes. [Duration.zero] once it has.
  Duration remainingAt(DateTime time) {
    final remaining = end.difference(time);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// How far through the window [time] sits, clamped to `0.0..1.0` — drives
  /// the banner's progress arc.
  double progressAt(DateTime time) {
    final total = duration.inSeconds;
    if (total <= 0) return 1;
    final elapsed = time.difference(start).inSeconds;
    return (elapsed / total).clamp(0.0, 1.0);
  }
}

/// A prayer's Adhan moment — the pair the "next prayer" countdown needs.
class AdhanMoment {
  const AdhanMoment({required this.prayer, required this.time});

  final PrayerLabel prayer;
  final DateTime time;
}

/// Everything the schedule UI needs to know about one day's prayers:
/// the raw timings, the validity windows derived from them, and the
/// lockout blocks that get written to the device calendar.
///
/// Built by [DailyPrayerSchedule.from], which needs the *following* day's
/// Fajr to close the Isha window — Isha spans midnight, so a single day's
/// [DailyPrayerTimes] can't express it alone.
class DailyPrayerSchedule {
  const DailyPrayerSchedule({
    required this.timings,
    required this.timeWindows,
    required this.lockoutWindows,
  });

  factory DailyPrayerSchedule.from({
    required DailyPrayerTimes timings,
    required DateTime nextDayFajr,
    required List<PrayerLockoutWindow> lockoutWindows,
  }) {
    return DailyPrayerSchedule(
      timings: timings,
      timeWindows: [
        PrayerTimeWindow(
          prayer: PrayerLabel.fajr,
          start: timings.fajr,
          end: timings.sunrise,
        ),
        PrayerTimeWindow(
          prayer: PrayerLabel.dhuhr,
          start: timings.dhuhr,
          end: timings.asr,
        ),
        PrayerTimeWindow(
          prayer: PrayerLabel.asr,
          start: timings.asr,
          end: timings.maghrib,
        ),
        PrayerTimeWindow(
          prayer: PrayerLabel.maghrib,
          start: timings.maghrib,
          end: timings.isha,
        ),
        PrayerTimeWindow(
          prayer: PrayerLabel.isha,
          start: timings.isha,
          end: nextDayFajr,
        ),
      ],
      lockoutWindows: lockoutWindows,
    );
  }

  final DailyPrayerTimes timings;

  /// The five validity windows, in daily order.
  final List<PrayerTimeWindow> timeWindows;

  /// The five calendar-synced lockout blocks, in daily order. Sourced from
  /// `CalendarSyncService.buildWindows` so the timeline shows exactly what
  /// the device calendar (and therefore any Shortcuts automation keyed off
  /// it) will see.
  final List<PrayerLockoutWindow> lockoutWindows;

  DateTime get date => timings.date;

  /// The validity window [time] falls inside, or null between Sunrise and
  /// Dhuhr — the one gap in the day that belongs to no prayer.
  PrayerTimeWindow? timeWindowAt(DateTime time) {
    for (final window in timeWindows) {
      if (window.contains(time)) return window;
    }
    return null;
  }

  /// The lockout block [time] falls inside, or null if the user is free.
  PrayerLockoutWindow? lockoutAt(DateTime time) {
    for (final window in lockoutWindows) {
      if (!time.isBefore(window.start) && time.isBefore(window.end)) {
        return window;
      }
    }
    return null;
  }

  /// The next obligatory prayer strictly after [time], or null once Isha
  /// has passed — callers should then look at the following day's schedule.
  AdhanMoment? nextAdhanAfter(DateTime time) {
    for (final prayer in obligatoryPrayers) {
      final adhan = timings.timeFor(prayer);
      if (adhan.isAfter(time)) {
        return AdhanMoment(prayer: prayer, time: adhan);
      }
    }
    return null;
  }
}
