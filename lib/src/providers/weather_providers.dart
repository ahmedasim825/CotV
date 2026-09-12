import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/weather.dart';

/// The current conditions, or null when there is no reading.
///
/// A fixed sample for now: this build is frontend only, and there is no
/// weather service, package or API key in the project. Wiring a real source
/// means replacing this one provider with a `FutureProvider` over an HTTP
/// call — `prayerCoordinatesProvider` already holds the coordinates it would
/// need. That is not a drop-in swap, though: the watch site's type moves
/// from `WeatherReading?` to `AsyncValue<WeatherReading?>`, and the one
/// consumer, `welcome_header.dart`, does `ref.watch(weatherProvider)` and
/// branches on `weather != null` directly — it has no loading or error
/// branch, so it would need a `.when(...)` (or `.value`) added before the
/// swap compiles.
final weatherProvider = Provider<WeatherReading?>((ref) {
  return const WeatherReading(celsius: 38, condition: WeatherCondition.cloudy);
});
