import 'package:flutter/material.dart';

import '../../models/daily_prayer_times.dart';
import '../../models/task.dart';
import 'app_palette.dart';

/// Per-prayer and per-priority accents, resolved against the active theme.
///
/// The six prayer hues live on [AppPalette.prayerHues] rather than as
/// global constants: in a chromatic theme they track the sun's actual
/// position through the day (pre-dawn indigo, midday amber, sunset copper,
/// night blue), while a monochrome theme supplies six neutral steps instead
/// so the timeline still reads without introducing color it has ruled out.
extension PrayerPaletteX on AppPalette {
  Color prayerHue(PrayerLabel prayer) {
    switch (prayer) {
      case PrayerLabel.fajr:
        return prayerHues.fajr;
      case PrayerLabel.sunrise:
        return prayerHues.sunrise;
      case PrayerLabel.dhuhr:
        return prayerHues.dhuhr;
      case PrayerLabel.asr:
        return prayerHues.asr;
      case PrayerLabel.maghrib:
        return prayerHues.maghrib;
      case PrayerLabel.isha:
        return prayerHues.isha;
    }
  }

  /// Fill for a prayer's tinted band behind the timeline. Kept very low
  /// alpha so block text stays legible on top of it.
  Color prayerBandFill(PrayerLabel prayer) =>
      prayerHue(prayer).withValues(alpha: 0.10);

  /// The band's leading edge rule, drawn at the Adhan instant.
  Color prayerBandEdge(PrayerLabel prayer) =>
      prayerHue(prayer).withValues(alpha: 0.45);

  /// The accent a task or reminder carries wherever it appears — list row,
  /// timeline block, form sheet or badge. High reads as a warning without
  /// being an error state; low stays deliberately quiet.
  ///
  /// Each step now resolves to a priority token of its own. High used to
  /// return [AppPalette.danger] and medium [AppPalette.secondary], which tied
  /// the scale to the error red and the app's cyan: retuning priority meant
  /// restyling every failure state and every secondary accent with it.
  Color priorityColor(TaskPriority priority) {
    switch (priority) {
      case TaskPriority.none:
        // No token of its own, because none has no colour identity: every
        // surface that draws a priority draws nothing at all for this one.
        // The muted grey is what a caller gets if it ignores that and paints
        // anyway.
        return textMuted;
      case TaskPriority.high:
        return priorityHigh;
      case TaskPriority.medium:
        return priorityMedium;
      case TaskPriority.low:
        return priorityLow;
    }
  }
}
