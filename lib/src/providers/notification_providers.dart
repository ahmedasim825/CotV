import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/notification_models.dart';
import '../services/notification_service.dart';
import 'prayer_providers.dart';
import 'settings_providers.dart';

final notificationServiceProvider =
    Provider<NotificationService>((ref) => NotificationService());

/// Drives notification scheduling as an explicit user/system action and
/// exposes its progress as [AsyncValue] — [AsyncLoading] while scheduling,
/// [AsyncData] with the last [NotificationScheduleResult] on success,
/// [AsyncError] (wrapping [NotificationPermissionDeniedException]) on
/// failure.
class NotificationScheduleController
    extends AsyncNotifier<NotificationScheduleResult?> {
  @override
  Future<NotificationScheduleResult?> build() async {
    await ref.read(notificationServiceProvider).initialize();
    return null;
  }

  /// Requests permission (if needed) and schedules Adhan + pre-Adhan
  /// notifications for the next [days] days, replacing anything already
  /// scheduled so location/settings changes don't leave stale alerts.
  Future<void> scheduleDays(int days) async {
    state = const AsyncLoading();
    final service = ref.read(notificationServiceProvider);
    final preAdhanOffset = ref.read(preAdhanOffsetProvider);
    final daysOfTimings = ref.read(upcomingPrayerTimesProvider(days));

    state = await AsyncValue.guard(() async {
      await service.requestPermissions();
      final scheduled = await service.reschedule(
        daysOfTimings,
        preAdhanOffset: preAdhanOffset,
      );
      return NotificationScheduleResult(
        notificationsScheduled: scheduled,
        daysScheduled: days,
      );
    });
  }

  /// Cancels every pending prayer notification without scheduling new ones.
  Future<void> cancelAll() async {
    state = const AsyncLoading();
    final service = ref.read(notificationServiceProvider);
    state = await AsyncValue.guard(() async {
      await service.cancelAllScheduled();
      return null;
    });
  }
}

final notificationScheduleControllerProvider = AsyncNotifierProvider<
    NotificationScheduleController, NotificationScheduleResult?>(
  NotificationScheduleController.new,
);
