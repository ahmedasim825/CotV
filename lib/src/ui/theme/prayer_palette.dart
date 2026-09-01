import 'package:flutter/material.dart';

import '../../models/daily_prayer_times.dart';
import '../../models/task.dart';
import 'app_theme.dart';

/// Per-prayer accent colors for the timeline's tinted windows.
///
/// Each hue tracks the sun's actual position through the day — pre-dawn
/// indigo, midday amber, sunset copper, night blue — so the timeline reads
/// as a day passing rather than as six arbitrary category colors. All are
/// desaturated to sit inside the app's warm dark-glass language instead of
/// fighting it.
class PrayerPalette {
  const PrayerPalette._();

  static const Color fajr = Color(0xFF7B7BB5);
  static const Color sunrise = Color(0xFFE0A183);
  static const Color dhuhr = Color(0xFFE8C36B);
  static const Color asr = Color(0xFFD8A657);
  static const Color maghrib = Color(0xFFC97A55);
  static const Color isha = Color(0xFF5C6BA8);

  static Color of(PrayerLabel prayer) {
    switch (prayer) {
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

  /// Fill for a prayer's tinted band behind the timeline. Kept very low
  /// alpha so block text stays legible on top of it.
  static Color bandFill(PrayerLabel prayer) =>
      of(prayer).withValues(alpha: 0.10);

  /// The band's leading edge rule, drawn at the Adhan instant.
  static Color bandEdge(PrayerLabel prayer) =>
      of(prayer).withValues(alpha: 0.45);

  /// Surface tint for a solid prayer lockout block.
  static Color lockoutFill(PrayerLabel prayer) =>
      Color.alphaBlend(of(prayer).withValues(alpha: 0.16), AppPalette.surface);
}

/// Priority accents for task tiles and timeline task blocks. High reads as a
/// warning without being an error state; low stays deliberately quiet.
class PriorityPalette {
  const PriorityPalette._();

  static const Color high = AppPalette.danger;
  static const Color medium = AppPalette.amber;
  static const Color low = Color(0xFF7FA3B8);
}

/// The accent a task carries wherever it appears — list tile, timeline
/// block, or form sheet.
Color accentForPriority(TaskPriority priority) {
  switch (priority) {
    case TaskPriority.high:
      return PriorityPalette.high;
    case TaskPriority.medium:
      return PriorityPalette.medium;
    case TaskPriority.low:
      return PriorityPalette.low;
  }
}
