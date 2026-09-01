import 'daily_prayer_times.dart';

/// Thrown when calendar permissions are denied or restricted by the user
/// or the OS (e.g. Screen Time / parental controls on iOS).
class CalendarPermissionDeniedException implements Exception {
  CalendarPermissionDeniedException(this.message);

  final String message;

  @override
  String toString() => 'CalendarPermissionDeniedException: $message';
}

/// Thrown for any other calendar read/write failure (calendar not found,
/// native plugin error, invalid event data, etc).
class CalendarSyncException implements Exception {
  CalendarSyncException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'CalendarSyncException: $message'
      : 'CalendarSyncException: $message (caused by $cause)';
}

/// A single prayer's lockout window on the device calendar, e.g.
/// "Fajr, 04:32–05:58" or "Dhuhr, 12:15–12:45".
class PrayerLockoutWindow {
  const PrayerLockoutWindow({
    required this.prayer,
    required this.start,
    required this.end,
  });

  final PrayerLabel prayer;
  final DateTime start;
  final DateTime end;
}

/// Outcome of syncing one day's prayer windows to the "Prayer Lockout"
/// calendar — enough detail for the UI to show a meaningful success state.
class CalendarSyncResult {
  const CalendarSyncResult({
    required this.calendarId,
    required this.syncedDate,
    required this.eventsCreated,
    required this.eventsRemoved,
  });

  final String calendarId;
  final DateTime syncedDate;
  final int eventsCreated;
  final int eventsRemoved;
}
