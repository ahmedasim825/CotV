import 'package:flutter/widgets.dart' show IconData;

import '../../models/daily_prayer_times.dart';
import 'ph_light_icons.dart';

/// Thin ultra-light iconography (Phosphor Light) standing in for each
/// prayer's position in the day, from pre-dawn to night.
IconData iconForPrayer(PrayerLabel prayer) {
  switch (prayer) {
    case PrayerLabel.fajr:
      return PhLight.moonStars;
    case PrayerLabel.sunrise:
      return PhLight.sunHorizon;
    case PrayerLabel.dhuhr:
      return PhLight.sun;
    case PrayerLabel.asr:
      return PhLight.sunDim;
    case PrayerLabel.maghrib:
      return PhLight.cloudSun;
    case PrayerLabel.isha:
      return PhLight.moon;
  }
}
