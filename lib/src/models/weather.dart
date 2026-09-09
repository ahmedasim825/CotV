import 'package:flutter/widgets.dart';

import '../ui/widgets/ph_light_icons.dart';

/// The conditions the header has a glyph for.
enum WeatherCondition {
  clear,
  partlyCloudy,
  cloudy,
  rain,
  snow,
  storm,
  fog;

  IconData get icon {
    switch (this) {
      case WeatherCondition.clear:
        return PhLight.sun;
      case WeatherCondition.partlyCloudy:
        return PhLight.cloudSun;
      case WeatherCondition.cloudy:
        return PhLight.cloud;
      case WeatherCondition.rain:
        return PhLight.cloudRain;
      case WeatherCondition.snow:
        return PhLight.cloudSnow;
      case WeatherCondition.storm:
        return PhLight.cloudLightning;
      case WeatherCondition.fog:
        return PhLight.cloudFog;
    }
  }
}

/// One current-conditions reading. Celsius, because that is what the header
/// displays and converting at the edge would only invite a second unit.
@immutable
class WeatherReading {
  const WeatherReading({required this.celsius, required this.condition});

  final double celsius;
  final WeatherCondition condition;

  /// "38°C" — rounded, because the header has no room for a decimal and no
  /// use for one.
  String get label => '${celsius.round()}°C';
}
