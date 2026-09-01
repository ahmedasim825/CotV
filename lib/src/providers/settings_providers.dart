import 'package:adhan/adhan.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/calendar_sync_service.dart';
import '../services/notification_service.dart';
import '../services/prayer_service.dart';

/// Calculation method used for all prayer time math. Defaults to the
/// Egyptian General Authority of Survey per spec; exposed as a Notifier so
/// the UI can switch it later without touching the calculation code.
class CalculationMethodNotifier extends Notifier<CalculationMethod> {
  @override
  CalculationMethod build() => PrayerService.defaultMethod;

  void set(CalculationMethod method) => state = method;
}

final calculationMethodProvider =
    NotifierProvider<CalculationMethodNotifier, CalculationMethod>(
  CalculationMethodNotifier.new,
);

/// Madhab used for Asr calculation.
class MadhabNotifier extends Notifier<Madhab> {
  @override
  Madhab build() => PrayerService.defaultMadhab;

  void set(Madhab madhab) => state = madhab;
}

final madhabProvider =
    NotifierProvider<MadhabNotifier, Madhab>(MadhabNotifier.new);

/// Coordinates used for prayer calculation. Defaults to Cairo until a
/// device location fix is supplied (location acquisition itself is outside
/// this layer's scope — call `.set()` once it's available).
class PrayerCoordinatesNotifier extends Notifier<Coordinates> {
  @override
  Coordinates build() => PrayerService.fallbackCoordinates;

  void set(Coordinates coordinates) => state = coordinates;
}

final prayerCoordinatesProvider =
    NotifierProvider<PrayerCoordinatesNotifier, Coordinates>(
  PrayerCoordinatesNotifier.new,
);

/// How long each non-Fajr lockout window stays open after its Adhan time.
class LockoutDurationNotifier extends Notifier<Duration> {
  @override
  Duration build() => CalendarSyncService.defaultLockoutDuration;

  void set(Duration duration) => state = duration;
}

final lockoutDurationProvider =
    NotifierProvider<LockoutDurationNotifier, Duration>(
  LockoutDurationNotifier.new,
);

/// How far ahead of each Adhan the pre-Adhan reminder fires. Set to
/// [Duration.zero] to disable pre-Adhan reminders entirely.
class PreAdhanOffsetNotifier extends Notifier<Duration> {
  @override
  Duration build() => NotificationService.defaultPreAdhanOffset;

  void set(Duration duration) => state = duration;
}

final preAdhanOffsetProvider =
    NotifierProvider<PreAdhanOffsetNotifier, Duration>(
  PreAdhanOffsetNotifier.new,
);
