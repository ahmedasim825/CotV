import 'package:adhan/adhan.dart';

/// The five daily prayers plus sunrise (a boundary marker, not itself prayed).
enum PrayerLabel { fajr, sunrise, dhuhr, asr, maghrib, isha }

extension PrayerLabelX on PrayerLabel {
  /// Human-readable name shown in the UI and used verbatim in calendar
  /// event titles and notification content.
  String get displayName {
    switch (this) {
      case PrayerLabel.fajr:
        return 'Fajr';
      case PrayerLabel.sunrise:
        return 'Sunrise';
      case PrayerLabel.dhuhr:
        return 'Dhuhr';
      case PrayerLabel.asr:
        return 'Asr';
      case PrayerLabel.maghrib:
        return 'Maghrib';
      case PrayerLabel.isha:
        return 'Isha';
    }
  }

  /// Stable lowercase key used in calendar event metadata and notification
  /// payloads. Automation tools (iOS Shortcuts, Jomo) should match on this
  /// rather than [displayName], which may be localized later.
  String get key {
    switch (this) {
      case PrayerLabel.fajr:
        return 'fajr';
      case PrayerLabel.sunrise:
        return 'sunrise';
      case PrayerLabel.dhuhr:
        return 'dhuhr';
      case PrayerLabel.asr:
        return 'asr';
      case PrayerLabel.maghrib:
        return 'maghrib';
      case PrayerLabel.isha:
        return 'isha';
    }
  }
}

/// The five obligatory prayers, in daily order. Excludes [PrayerLabel.sunrise],
/// which marks the end of the Fajr window but has no lockout/adhan of its own.
const List<PrayerLabel> obligatoryPrayers = [
  PrayerLabel.fajr,
  PrayerLabel.dhuhr,
  PrayerLabel.asr,
  PrayerLabel.maghrib,
  PrayerLabel.isha,
];

/// Thrown when [PrayerTimes] calculation fails (e.g. invalid coordinates,
/// or a location/date combination the underlying solar math can't resolve).
class PrayerCalculationException implements Exception {
  PrayerCalculationException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'PrayerCalculationException: $message'
      : 'PrayerCalculationException: $message (caused by $cause)';
}

/// Immutable result of a prayer time calculation for a single calendar day,
/// at a specific location and with a specific calculation method. This is
/// the shared value type consumed by the calendar sync and notification
/// services, so it carries everything they need without re-deriving it.
class DailyPrayerTimes {
  const DailyPrayerTimes({
    required this.date,
    required this.coordinates,
    required this.calculationMethod,
    required this.madhab,
    required this.fajr,
    required this.sunrise,
    required this.dhuhr,
    required this.asr,
    required this.maghrib,
    required this.isha,
  });

  /// Midnight-normalized local date this calculation is for.
  final DateTime date;
  final Coordinates coordinates;
  final CalculationMethod calculationMethod;
  final Madhab madhab;

  final DateTime fajr;
  final DateTime sunrise;
  final DateTime dhuhr;
  final DateTime asr;
  final DateTime maghrib;
  final DateTime isha;

  /// Local start time for the given prayer (or sunrise).
  DateTime timeFor(PrayerLabel label) {
    switch (label) {
      case PrayerLabel.fajr:
        return fajr;
      case PrayerLabel.sunrise:
        return sunrise;
      case PrayerLabel.dhuhr:
        return dhuhr;
      case PrayerLabel.asr:
        return asr;
      case PrayerLabel.maghrib:
        return maghrib;
      case PrayerLabel.isha:
        return isha;
    }
  }

  /// All six timings keyed by [PrayerLabel], in daily order.
  Map<PrayerLabel, DateTime> asMap() => {
        PrayerLabel.fajr: fajr,
        PrayerLabel.sunrise: sunrise,
        PrayerLabel.dhuhr: dhuhr,
        PrayerLabel.asr: asr,
        PrayerLabel.maghrib: maghrib,
        PrayerLabel.isha: isha,
      };

  @override
  String toString() =>
      'DailyPrayerTimes(${date.toIso8601String().split('T').first}: '
      'fajr=$fajr, sunrise=$sunrise, dhuhr=$dhuhr, asr=$asr, '
      'maghrib=$maghrib, isha=$isha)';
}
