import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart' show Color;

import '../models/calendar_sync_models.dart';
import '../models/daily_prayer_times.dart';

/// Creates and maintains a dedicated local iOS calendar ("Prayer Lockout")
/// with one event per obligatory prayer window each day, so that iOS
/// Shortcuts automations and the Jomo app can key off calendar activity
/// to trigger focus/lockout modes.
///
/// Event metadata is deliberately stable and machine-parseable: the title
/// always starts with [calendarName], and the description carries
/// `key:value` lines (`type`, `prayer`, `start`, `end`) that a Shortcuts
/// "Find Calendar Events" + "Get Text from Input" automation can match on
/// without depending on display text or locale.
class CalendarSyncService {
  CalendarSyncService({DeviceCalendarPlugin? plugin})
      : _plugin = plugin ?? DeviceCalendarPlugin();

  final DeviceCalendarPlugin _plugin;

  static const String calendarName = 'Prayer Lockout';
  static const String automationTag = 'prayer_lockout';
  static const Duration defaultLockoutDuration = Duration(minutes: 30);

  /// `device_calendar` ships iOS and Android implementations only. Without
  /// this check every call on the Windows build would surface as a raw
  /// MissingPluginException, which tells the user nothing they can act on.
  ///
  /// Only the plugin-backed methods are gated. [buildWindows] is pure
  /// computation and stays available everywhere, which is what lets the
  /// timeline draw lockout blocks on a platform that cannot sync them.
  static bool get isSupported =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;

  /// Requests calendar read/write permissions if not already granted.
  ///
  /// Throws [CalendarPermissionDeniedException] if the user denies access
  /// or the OS restricts it (e.g. Screen Time). Callers should catch this
  /// specifically to show a "how to enable in Settings" prompt.
  Future<void> requestPermissions() async {
    if (!isSupported) {
      throw CalendarSyncException(
        'Calendar sync runs on iOS and Android only. The Prayer Lockout '
        'calendar exists for iOS Shortcuts to key off, so there is nothing '
        'for it to do on this platform.',
      );
    }

    final existing = await _plugin.hasPermissions();
    if (existing.isSuccess && existing.data == true) return;

    final requested = await _plugin.requestPermissions();
    if (!requested.isSuccess || requested.data != true) {
      throw CalendarPermissionDeniedException(
        'Calendar access was denied or restricted. Enable calendar '
        'permissions for this app in Settings > Privacy & Security > '
        'Calendars to sync prayer windows.',
      );
    }
  }

  /// Finds the existing "Prayer Lockout" calendar or creates it if it
  /// doesn't exist yet. Returns the calendar's native ID.
  Future<String> findOrCreateLockoutCalendar() async {
    final calendarsResult = await _plugin.retrieveCalendars();
    if (!calendarsResult.isSuccess) {
      throw CalendarSyncException(
        'Failed to read device calendars: '
        '${_errorText(calendarsResult.errors)}',
      );
    }

    final match = calendarsResult.data?.where(
      (c) => c.name == calendarName && c.isReadOnly != true,
    );
    if (match != null && match.isNotEmpty) {
      return match.first.id!;
    }

    final createResult = await _plugin.createCalendar(
      calendarName,
      calendarColor: const Color(0xFF1B7340),
      localAccountName: calendarName,
    );
    if (!createResult.isSuccess ||
        createResult.data == null ||
        createResult.data!.isEmpty) {
      throw CalendarSyncException(
        'Failed to create the "$calendarName" calendar: '
        '${_errorText(createResult.errors)}',
      );
    }
    return createResult.data!;
  }

  /// Builds the five lockout windows for a day's timings. Sunrise is
  /// excluded — it isn't a prayer, it only marks the end of the Fajr
  /// window.
  List<PrayerLockoutWindow> buildWindows(
    DailyPrayerTimes timings, {
    Duration lockoutDuration = defaultLockoutDuration,
  }) {
    return [
      PrayerLockoutWindow(
        prayer: PrayerLabel.fajr,
        start: timings.fajr,
        end: timings.sunrise,
      ),
      for (final prayer in const [
        PrayerLabel.dhuhr,
        PrayerLabel.asr,
        PrayerLabel.maghrib,
        PrayerLabel.isha,
      ])
        PrayerLockoutWindow(
          prayer: prayer,
          start: timings.timeFor(prayer),
          end: timings.timeFor(prayer).add(lockoutDuration),
        ),
    ];
  }

  /// Syncs one day's prayer windows onto the "Prayer Lockout" calendar.
  ///
  /// Idempotent: any of our own events already in that day's range are
  /// removed first (matched by [automationTag] in the description, not by
  /// title, so a renamed calendar entry still gets cleaned up), then fresh
  /// events are created from [timings]. Safe to call repeatedly for the
  /// same day, e.g. after a location change.
  Future<CalendarSyncResult> syncDay(
    DailyPrayerTimes timings, {
    Duration lockoutDuration = defaultLockoutDuration,
  }) async {
    await requestPermissions();
    final calendarId = await findOrCreateLockoutCalendar();

    final dayStart = timings.date;
    final dayEnd = dayStart.add(const Duration(days: 1));
    final removed = await _clearExistingEvents(calendarId, dayStart, dayEnd);

    final windows = buildWindows(timings, lockoutDuration: lockoutDuration);
    var created = 0;
    for (final window in windows) {
      final event = Event(
        calendarId,
        title: '$calendarName – ${window.prayer.displayName}',
        description: _describeWindow(window),
        start: window.start,
        end: window.end,
      );

      final result = await _plugin.createOrUpdateEvent(event);
      if (result == null || !result.isSuccess) {
        throw CalendarSyncException(
          'Failed to create the ${window.prayer.displayName} event: '
          '${_errorText(result?.errors ?? const [])}',
        );
      }
      created++;
    }

    return CalendarSyncResult(
      calendarId: calendarId,
      syncedDate: dayStart,
      eventsCreated: created,
      eventsRemoved: removed,
    );
  }

  /// Syncs every day in [daysOfTimings] and returns the last result. Used
  /// to keep a rolling window (e.g. next 7 days) up to date in one call.
  Future<CalendarSyncResult> syncRange(
    List<DailyPrayerTimes> daysOfTimings, {
    Duration lockoutDuration = defaultLockoutDuration,
  }) async {
    if (daysOfTimings.isEmpty) {
      throw ArgumentError.value(
        daysOfTimings,
        'daysOfTimings',
        'Must contain at least one day.',
      );
    }

    CalendarSyncResult? last;
    for (final timings in daysOfTimings) {
      last = await syncDay(timings, lockoutDuration: lockoutDuration);
    }
    return last!;
  }

  Future<int> _clearExistingEvents(
    String calendarId,
    DateTime start,
    DateTime end,
  ) async {
    final result = await _plugin.retrieveEvents(
      calendarId,
      RetrieveEventsParams(startDate: start, endDate: end),
    );
    if (!result.isSuccess) return 0;

    final ours = (result.data ?? const Iterable<Event>.empty())
        .where((e) => (e.description ?? '').contains('type:$automationTag'))
        .toList();

    for (final event in ours) {
      if (event.eventId != null) {
        await _plugin.deleteEvent(calendarId, event.eventId);
      }
    }
    return ours.length;
  }

  String _describeWindow(PrayerLockoutWindow window) => [
        'type:$automationTag',
        'prayer:${window.prayer.key}',
        'start:${window.start.toIso8601String()}',
        'end:${window.end.toIso8601String()}',
      ].join('\n');

  String _errorText(Iterable<ResultError> errors) => errors.isEmpty
      ? 'unknown error'
      : errors.map((e) => e.errorMessage).join('; ');
}
