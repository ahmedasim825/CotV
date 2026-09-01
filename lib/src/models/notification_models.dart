/// Thrown when notification permissions are denied by the user.
class NotificationPermissionDeniedException implements Exception {
  NotificationPermissionDeniedException(this.message);

  final String message;

  @override
  String toString() => 'NotificationPermissionDeniedException: $message';
}

/// Outcome of a notification scheduling run — enough detail for the UI to
/// confirm what was scheduled without re-querying the plugin.
class NotificationScheduleResult {
  const NotificationScheduleResult({
    required this.notificationsScheduled,
    required this.daysScheduled,
  });

  final int notificationsScheduled;
  final int daysScheduled;
}
