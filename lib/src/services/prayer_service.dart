import 'package:adhan/adhan.dart';

import '../models/daily_prayer_times.dart';

/// Computes daily prayer timings using the `adhan` package.
///
/// Stateless and side-effect free: every call takes its own coordinates,
/// method and madhab, so it composes cleanly with Riverpod providers that
/// recompute when location or settings change.
class PrayerService {
  /// Cairo, Egypt — used whenever the caller has no device location yet
  /// (first launch, permission denied, GPS unavailable).
  static final Coordinates fallbackCoordinates = Coordinates(30.0444, 31.2357);

  /// Required default per spec: Egyptian General Authority of Survey.
  static const CalculationMethod defaultMethod = CalculationMethod.egyptian;

  static const Madhab defaultMadhab = Madhab.shafi;

  /// Calculates all six timings (Fajr, Sunrise, Dhuhr, Asr, Maghrib, Isha)
  /// for the given [date] at [coordinates] (falls back to Cairo when null).
  DailyPrayerTimes calculateForDate(
    DateTime date, {
    Coordinates? coordinates,
    CalculationMethod method = defaultMethod,
    Madhab madhab = defaultMadhab,
  }) {
    final resolvedCoordinates = coordinates ?? fallbackCoordinates;

    try {
      final parameters = method.getParameters()..madhab = madhab;
      final components = DateComponents.from(date);
      final times = PrayerTimes(resolvedCoordinates, components, parameters);

      return DailyPrayerTimes(
        date: DateTime(date.year, date.month, date.day),
        coordinates: resolvedCoordinates,
        calculationMethod: method,
        madhab: madhab,
        fajr: times.fajr,
        sunrise: times.sunrise,
        dhuhr: times.dhuhr,
        asr: times.asr,
        maghrib: times.maghrib,
        isha: times.isha,
      );
    } catch (e) {
      throw PrayerCalculationException(
        'Could not calculate prayer times for '
        '${date.toIso8601String().split('T').first} at '
        '(${resolvedCoordinates.latitude}, ${resolvedCoordinates.longitude}).',
        e,
      );
    }
  }

  /// Calculates timings for [days] consecutive days starting at [startDate].
  /// Used to pre-populate the calendar and notifications for a rolling
  /// window (e.g. the next 7 days) in one call.
  List<DailyPrayerTimes> calculateForRange(
    DateTime startDate,
    int days, {
    Coordinates? coordinates,
    CalculationMethod method = defaultMethod,
    Madhab madhab = defaultMadhab,
  }) {
    if (days <= 0) {
      throw ArgumentError.value(days, 'days', 'Must be at least 1.');
    }

    final normalizedStart =
        DateTime(startDate.year, startDate.month, startDate.day);

    return List.generate(
      days,
      (i) => calculateForDate(
        normalizedStart.add(Duration(days: i)),
        coordinates: coordinates,
        method: method,
        madhab: madhab,
      ),
    );
  }
}
