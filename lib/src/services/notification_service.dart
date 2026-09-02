import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/daily_prayer_times.dart';
import '../models/notification_models.dart';

/// Schedules local notifications for each Adhan and an optional pre-Adhan
/// reminder, using exact, timezone-aware scheduling so alerts stay correct
/// even as the underlying prayer times shift day to day.
///
/// Notification IDs are derived deterministically from
/// `(date, prayer, isPreAdhan)` — see [_notificationId] — so rescheduling
/// the same day always overwrites the same slots instead of piling up
/// duplicates, without needing to persist a lookup table.
class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  static const String _adhanChannelId = 'prayer_adhan_channel';
  static const String _adhanChannelName = 'Prayer Adhan Alerts';
  static const String _adhanChannelDescription =
      'Notification at the exact start of each prayer time.';

  static const String _reminderChannelId = 'prayer_reminder_channel';
  static const String _reminderChannelName = 'Pre-Adhan Reminders';
  static const String _reminderChannelDescription =
      'Advance notice before each prayer time.';

  /// Default lead time for the pre-Adhan reminder when none is specified.
  static const Duration defaultPreAdhanOffset = Duration(minutes: 15);

  /// Windows addresses a toast to an app identity rather than to a running
  /// process, so the plugin needs the same AUMID the MSIX package declares
  /// plus a stable GUID for the activation callback. Both are fixed on
  /// purpose: changing either orphans notifications already sitting in the
  /// Action Center, and breaks the ones scheduled for later today.
  static const WindowsInitializationSettings windowsSettings =
      WindowsInitializationSettings(
    appName: 'Prayer Lockout',
    appUserModelId: 'AhmedAsim.PrayerLockout',
    guid: '5D2F3BD4-F0A6-4342-9639-C9D2A9F00B30',
  );

  /// Sets up the timezone database and the plugin. Safe to call more than
  /// once — subsequent calls are a no-op. Does not request permissions;
  /// call [requestPermissions] explicitly so the OS prompt appears at a
  /// time of your choosing rather than on cold start.
  Future<void> initialize() async {
    if (_initialized) return;

    tzdata.initializeTimeZones();
    tz.setLocalLocation(_resolveLocalTimeZone());

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
        windows: windowsSettings,
      ),
    );

    _initialized = true;
  }

  /// Requests Alert/Sound/Badge permission on iOS, or POST_NOTIFICATIONS on
  /// Android 13+. Throws [NotificationPermissionDeniedException] if denied.
  Future<void> requestPermissions() async {
    await initialize();

    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      if (granted != true) {
        throw NotificationPermissionDeniedException(
          'Notification permissions were denied. Enable Alerts, Sounds and '
          'Badges for this app in Settings > Notifications to receive '
          'prayer alerts.',
        );
      }
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      if (granted == false) {
        throw NotificationPermissionDeniedException(
          'Notification permissions were denied.',
        );
      }

      // We schedule with AndroidScheduleMode.exactAllowWhileIdle, which on
      // Android 12+ requires the user to separately grant "Alarms &
      // reminders". This doesn't block scheduling (it silently falls back
      // to inexact timing if refused), so failures here aren't fatal.
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestExactAlarmsPermission();
    }
  }

  /// Schedules the Adhan notification (and, if [preAdhanOffset] is
  /// positive, a pre-Adhan reminder) for every obligatory prayer in
  /// [timings] whose time hasn't already passed today.
  ///
  /// Returns how many notifications were scheduled.
  Future<int> scheduleForDay(
    DailyPrayerTimes timings, {
    Duration preAdhanOffset = defaultPreAdhanOffset,
  }) async {
    await initialize();
    final now = DateTime.now();
    var scheduled = 0;

    for (final prayer in obligatoryPrayers) {
      final adhanTime = timings.timeFor(prayer);

      if (adhanTime.isAfter(now)) {
        await _scheduleOne(
          id: _notificationId(timings.date, prayer, isPreAdhan: false),
          when: adhanTime,
          title: '${prayer.displayName} — Adhan',
          body: 'It is now time for ${prayer.displayName} prayer.',
          channelId: _adhanChannelId,
          channelName: _adhanChannelName,
          channelDescription: _adhanChannelDescription,
        );
        scheduled++;
      }

      if (preAdhanOffset > Duration.zero) {
        final reminderTime = adhanTime.subtract(preAdhanOffset);
        if (reminderTime.isAfter(now)) {
          final minutes = preAdhanOffset.inMinutes;
          await _scheduleOne(
            id: _notificationId(timings.date, prayer, isPreAdhan: true),
            when: reminderTime,
            title: '${prayer.displayName} in $minutes min',
            body: '${prayer.displayName} begins at '
                '${_formatTime(adhanTime)}.',
            channelId: _reminderChannelId,
            channelName: _reminderChannelName,
            channelDescription: _reminderChannelDescription,
          );
          scheduled++;
        }
      }
    }

    return scheduled;
  }

  /// Schedules notifications for every day in [daysOfTimings].
  Future<int> scheduleForRange(
    List<DailyPrayerTimes> daysOfTimings, {
    Duration preAdhanOffset = defaultPreAdhanOffset,
  }) async {
    var total = 0;
    for (final timings in daysOfTimings) {
      total += await scheduleForDay(timings, preAdhanOffset: preAdhanOffset);
    }
    return total;
  }

  /// Cancels the Adhan and pre-Adhan notifications for one specific day,
  /// without touching notifications scheduled for other days.
  Future<void> cancelForDate(DateTime date) async {
    for (final prayer in obligatoryPrayers) {
      await _plugin.cancel(id: _notificationId(date, prayer, isPreAdhan: false));
      await _plugin.cancel(id: _notificationId(date, prayer, isPreAdhan: true));
    }
  }

  /// Cancels every pending prayer notification. Use this before
  /// rescheduling after a location or settings change so stale times don't
  /// linger alongside the new ones.
  ///
  /// Task reminders are left alone: they live in a disjoint ID range (see
  /// [_reminderId]), so a prayer resync can't silently destroy them.
  Future<void> cancelAllScheduled() async {
    final pending = await _plugin.pendingNotificationRequests();
    for (final request in pending) {
      if (request.id < _reminderIdBase) {
        await _plugin.cancel(id: request.id);
      }
    }
  }

  /// Schedules a one-off reminder identified by an arbitrary string [key]
  /// (a task's UUID, in practice).
  ///
  /// Deliberately key-based rather than typed against the task model, so
  /// this service stays independent of the task layer. Rescheduling the
  /// same key overwrites its slot, and a [when] already in the past cancels
  /// the reminder rather than scheduling one that can never fire.
  ///
  /// Returns whether a notification is now scheduled for [key].
  Future<bool> scheduleReminder({
    required String key,
    required DateTime when,
    required String title,
    required String body,
  }) async {
    await initialize();
    await cancelReminder(key);

    if (!when.isAfter(DateTime.now())) return false;

    await _scheduleOne(
      id: _reminderId(key),
      when: when,
      title: title,
      body: body,
      channelId: _reminderChannelId,
      channelName: _reminderChannelName,
      channelDescription: _reminderChannelDescription,
    );
    return true;
  }

  /// Cancels the reminder previously scheduled for [key]. A no-op if none
  /// was scheduled.
  Future<void> cancelReminder(String key) =>
      _plugin.cancel(id: _reminderId(key));

  /// Start of the ID range reserved for keyed reminders. Prayer IDs are
  /// built from a date and so always fall below this.
  static const int _reminderIdBase = 100000000;
  static const int _reminderIdSpan = 1000000000;

  /// Maps an arbitrary [key] to a stable notification ID inside the
  /// reminder range.
  ///
  /// Uses FNV-1a rather than [String.hashCode], which Dart does not
  /// guarantee to be stable across runs — a per-launch hash would strand
  /// notifications that could never be cancelled.
  int _reminderId(String key) {
    var hash = 0x811c9dc5;
    for (final unit in key.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return _reminderIdBase + (hash % _reminderIdSpan);
  }

  /// Convenience for "settings changed" flows: clears every pending prayer
  /// notification, then reschedules from [daysOfTimings].
  Future<int> reschedule(
    List<DailyPrayerTimes> daysOfTimings, {
    Duration preAdhanOffset = defaultPreAdhanOffset,
  }) async {
    await cancelAllScheduled();
    return scheduleForRange(daysOfTimings, preAdhanOffset: preAdhanOffset);
  }

  Future<void> _scheduleOne({
    required int id,
    required DateTime when,
    required String title,
    required String body,
    required String channelId,
    required String channelName,
    required String channelDescription,
  }) {
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBadge: true,
        interruptionLevel: InterruptionLevel.active,
      ),
    );

    return _plugin.zonedSchedule(
      id: id,
      scheduledDate: tz.TZDateTime.from(when, tz.local),
      title: title,
      body: body,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  /// Deterministic notification ID from `(date, prayer, isPreAdhan)`,
  /// e.g. 2026-09-01 Dhuhr Adhan -> 26090120. Keeps IDs small, stable and
  /// human-debuggable, well within the platform's 32-bit signed int range.
  int _notificationId(
    DateTime date,
    PrayerLabel prayer, {
    required bool isPreAdhan,
  }) {
    final prayerIndex = obligatoryPrayers.indexOf(prayer);
    return (date.year % 100) * 1000000 +
        date.month * 10000 +
        date.day * 100 +
        prayerIndex * 10 +
        (isPreAdhan ? 1 : 0);
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// Best-effort resolution of the device's local IANA timezone.
  ///
  /// This package only ships the tz database, not a way to read the
  /// device's timezone name — that requires a platform channel (e.g. the
  /// `flutter_timezone` package), which is out of scope for this layer.
  /// Instead we match the device's current UTC offset against the tz
  /// database and fall back to Africa/Cairo (matching
  /// [PrayerService.fallbackCoordinates]) if nothing matches. This is
  /// correct for most zones most of the time, but can pick the wrong zone
  /// among ones that share an offset (e.g. during DST transitions). Call
  /// [setLocalTimeZone] with a real IANA name once device location/timezone
  /// data is available to get exact results.
  tz.Location _resolveLocalTimeZone() {
    final deviceOffset = DateTime.now().timeZoneOffset;
    for (final location in tz.timeZoneDatabase.locations.values) {
      if (location.currentTimeZone.offset == deviceOffset) {
        return location;
      }
    }
    return tz.getLocation('Africa/Cairo');
  }

  /// Explicitly sets the local timezone by IANA name (e.g. "Europe/London").
  /// Overrides the best-effort guess made in [initialize].
  void setLocalTimeZone(String ianaTimeZoneName) {
    tz.setLocalLocation(tz.getLocation(ianaTimeZoneName));
  }
}
