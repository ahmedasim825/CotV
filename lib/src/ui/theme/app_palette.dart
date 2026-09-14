import 'package:flutter/material.dart';

/// The six prayer hues, one per adhan.
@immutable
class PrayerHues {
  const PrayerHues({
    required this.fajr,
    required this.sunrise,
    required this.dhuhr,
    required this.asr,
    required this.maghrib,
    required this.isha,
  });

  final Color fajr;
  final Color sunrise;
  final Color dhuhr;
  final Color asr;
  final Color maghrib;
  final Color isha;
}

/// Every colour the app paints with.
///
/// One instance exists — [kPalette] in `app_theme.dart`. The app used to
/// carry six of these behind a picker; the class survives the collapse so
/// that the ~246 `context.palette.<token>` call sites keep reading a name
/// rather than a literal, which is what keeps the scheme editable in one
/// place.
@immutable
class AppPalette {
  const AppPalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.glassFill,
    required this.glassBorder,
    required this.cardFill,
    required this.glassSpecular,
    required this.hairline,
    required this.innerHighlight,
    required this.accent,
    required this.accentBright,
    required this.accentDeep,
    required this.onAccent,
    required this.secondary,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.danger,
    required this.success,
    required this.taskRing,
    required this.reminderRing,
    required this.priorityLow,
    required this.shadow,
    required this.glowPrimary,
    required this.glowSecondary,
    required this.prayerHues,
  });

  final Brightness brightness;
  final Color background;
  final Color surface;
  final Color surfaceRaised;
  final Color glassFill;
  final Color glassBorder;

  /// The dashboard card's fill: white at 2%. Almost nothing, deliberately —
  /// the card reads as its rim and its contents rather than as a plate, and
  /// the ambient glow behind it comes straight through.
  final Color cardFill;
  final Color glassSpecular;
  final Color hairline;
  final Color innerHighlight;
  final Color accent;
  final Color accentBright;
  final Color accentDeep;
  final Color onAccent;
  final Color secondary;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color danger;
  final Color success;

  /// The ring on a task row in the iOS agenda card.
  ///
  /// Only the agenda card reads these two: in a list that interleaves tasks
  /// and reminders under one title, the ring colour is the only thing saying
  /// which kind a row is, so each gets a hue of its own rather than sharing
  /// [accent]. Neither is a general-purpose token — nothing else should
  /// borrow them.
  final Color taskRing;

  /// The ring on a reminder row in the iOS agenda card. Always this colour,
  /// whether or not the reminder is overdue — lateness is carried by the due
  /// line under the title, not by the ring.
  final Color reminderRing;

  final Color priorityLow;
  final Color shadow;
  final Color glowPrimary;
  final Color glowSecondary;
  final PrayerHues prayerHues;

  bool get isDark => brightness == Brightness.dark;

  Color get accentSoft => accent.withValues(alpha: 0.16);

  Color get meterTrack => textPrimary.withValues(alpha: 0.08);

  Color get heroTint =>
      Color.alphaBlend(accent.withValues(alpha: isDark ? 0.07 : 0.05), surface);

  Color get scrim => isDark ? const Color(0xB3000000) : const Color(0x66000000);
}
