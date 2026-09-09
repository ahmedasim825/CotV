import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/weather.dart';

/// The current conditions, or null when there is no reading.
///
/// A fixed sample for now: this build is frontend only, and there is no
/// weather service, package or API key in the project. Wiring a real source
/// means replacing this one provider with a `FutureProvider` over an HTTP
/// call — `prayerCoordinatesProvider` already holds the coordinates it would
/// need. Every consumer already handles null, which is what a failed or
/// pending fetch will return.
final weatherProvider = Provider<WeatherReading?>((ref) {
  return const WeatherReading(celsius: 38, condition: WeatherCondition.cloudy);
});
