import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/calendar_sync_models.dart';
import '../services/calendar_sync_service.dart';
import 'prayer_providers.dart';
import 'settings_providers.dart';

final calendarSyncServiceProvider =
    Provider<CalendarSyncService>((ref) => CalendarSyncService());

/// Drives calendar sync as an explicit user/system action and exposes its
/// progress as [AsyncValue] — [AsyncLoading] while syncing, [AsyncData]
/// with the last [CalendarSyncResult] on success, [AsyncError] (wrapping
/// [CalendarPermissionDeniedException] or [CalendarSyncException]) on
/// failure. The UI should catch the permission-denied case specifically to
/// point the user at Settings.
class CalendarSyncController extends AsyncNotifier<CalendarSyncResult?> {
  @override
  Future<CalendarSyncResult?> build() async => null;

  /// Syncs just today onto the "Milo" calendar.
  Future<void> syncToday() => syncDays(1);

  /// Syncs the next [days] days onto the "Milo" calendar,
  /// clearing out any of our own stale events in each day's range first.
  Future<void> syncDays(int days) async {
    state = const AsyncLoading();
    final service = ref.read(calendarSyncServiceProvider);
    final lockoutDuration = ref.read(lockoutDurationProvider);
    final daysOfTimings = ref.read(upcomingPrayerTimesProvider(days));

    state = await AsyncValue.guard(
      () => service.syncRange(daysOfTimings, lockoutDuration: lockoutDuration),
    );
  }
}

final calendarSyncControllerProvider =
    AsyncNotifierProvider<CalendarSyncController, CalendarSyncResult?>(
  CalendarSyncController.new,
);
