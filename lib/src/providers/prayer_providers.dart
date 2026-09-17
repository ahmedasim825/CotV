import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/daily_prayer_times.dart';
import '../services/prayer_service.dart';
import '../ui/format/time_format.dart';
import 'settings_providers.dart';

final prayerServiceProvider = Provider<PrayerService>((ref) => PrayerService());

/// Prayer timings for an arbitrary day, recomputed whenever location,
/// calculation method or madhab change. Pass a midnight-normalized
/// [DateTime] (see [startOfDay]) so repeated calls for the same day hit
/// the same cached value instead of recomputing on every read.
final dailyPrayerTimesProvider =
    Provider.family<DailyPrayerTimes, DateTime>((ref, date) {
  final service = ref.watch(prayerServiceProvider);
  final coordinates = ref.watch(prayerCoordinatesProvider);
  final method = ref.watch(calculationMethodProvider);
  final madhab = ref.watch(madhabProvider);
  return service.calculateForDate(
    date,
    coordinates: coordinates,
    method: method,
    madhab: madhab,
  );
});

/// The next [days] days of prayer timings starting today — the window the
/// calendar sync and notification services operate over.
final upcomingPrayerTimesProvider =
    Provider.family<List<DailyPrayerTimes>, int>((ref, days) {
  final today = startOfDay(DateTime.now());
  return [
    for (var i = 0; i < days; i++)
      ref.watch(dailyPrayerTimesProvider(today.add(Duration(days: i)))),
  ];
});

/// Today's prayer timings wrapped in [AsyncValue] so the UI gets uniform
/// loading/data/error handling (via `.when(...)`) even though the
/// underlying calculation is synchronous — a calculation failure (e.g. an
/// out-of-range coordinate) surfaces as a normal [AsyncError] instead of
/// crashing the widget tree.
final todayPrayerTimesProvider = FutureProvider<DailyPrayerTimes>((ref) async {
  ref.watch(prayerCoordinatesProvider);
  ref.watch(calculationMethodProvider);
  ref.watch(madhabProvider);
  return ref.watch(dailyPrayerTimesProvider(startOfDay(DateTime.now())));
});
