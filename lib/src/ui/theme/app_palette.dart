import 'package:flutter/material.dart';

/// The six per-prayer accent hues a theme carries, ordered as the day runs.
///
/// Kept on the palette rather than as global constants so a monochrome
/// theme can render the timeline in neutral steps while a chromatic one
/// tracks the sun's actual position through the day.
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

  static PrayerHues lerp(PrayerHues a, PrayerHues b, double t) {
    return PrayerHues(
      fajr: Color.lerp(a.fajr, b.fajr, t)!,
      sunrise: Color.lerp(a.sunrise, b.sunrise, t)!,
      dhuhr: Color.lerp(a.dhuhr, b.dhuhr, t)!,
      asr: Color.lerp(a.asr, b.asr, t)!,
      maghrib: Color.lerp(a.maghrib, b.maghrib, t)!,
      isha: Color.lerp(a.isha, b.isha, t)!,
    );
  }
}

/// Which font pairing a theme uses. Resolved to concrete Google Fonts
/// families by [AppTypography] — an enum rather than a family-name string,
/// so a typo is a compile error instead of a runtime font-fetch failure.
enum AppTypeface {
  /// Editorial serif numerals over a geometric grotesk. The house pairing.
  frauncesJakarta,

  /// A single neutral grotesk throughout — the iOS system-font look.
  interInter,

  /// Technical display face over a neutral grotesk.
  spaceGroteskInter,

  /// Editorial serif over a soft humanist sans, for light themes.
  frauncesDmSans,
}

/// Every color token the app draws with, as an immutable value rather than
/// a set of compile-time constants, so the whole surface can be swapped at
/// runtime by the theme picker.
///
/// Reach it from any widget with `context.palette` (see `app_theme.dart`).
/// It travels as a [ThemeExtension], so plain [StatelessWidget]s pick it up
/// without a Riverpod dependency and Flutter cross-fades between themes.
@immutable
class AppPalette {
  const AppPalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.glassFill,
    required this.glassBorder,
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
    required this.priorityLow,
    required this.shadow,
    required this.glowPrimary,
    required this.glowSecondary,
    required this.prayerHues,
    required this.typeface,
  });

  /// Drives status-bar icon color and the light/dark decisions a few
  /// widgets still have to make for themselves.
  final Brightness brightness;

  /// The page canvas, behind everything.
  final Color background;

  /// Default card and sheet fill.
  final Color surface;

  /// A step above [surface], for a card sitting on a card.
  final Color surfaceRaised;

  /// Translucent fill for chips, inputs and the outer glass shell.
  final Color glassFill;

  /// The outer glass shell's border.
  final Color glassBorder;

  /// One-pixel dividers and card borders.
  final Color hairline;

  /// The bright top edge that reads as an inset highlight on a card.
  final Color innerHighlight;

  final Color accent;
  final Color accentBright;
  final Color accentDeep;

  /// Text and icons drawn on top of [accent].
  final Color onAccent;

  /// The warm secondary highlight — streak badges, medium priority.
  final Color secondary;

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  final Color danger;
  final Color success;

  /// Low-priority accent. High and medium map to [danger] and [secondary].
  final Color priorityLow;

  /// Card drop-shadow color, already carrying its alpha.
  final Color shadow;

  /// The two out-of-focus orbs behind the app, already carrying alpha.
  final Color glowPrimary;
  final Color glowSecondary;

  final PrayerHues prayerHues;
  final AppTypeface typeface;

  bool get isDark => brightness == Brightness.dark;

  /// A tinted plate for an accent-colored icon chip.
  Color get accentSoft => accent.withValues(alpha: 0.16);

  /// Tint for the hero card, which sits a shade off the default surface.
  Color get heroTint =>
      Color.alphaBlend(accent.withValues(alpha: isDark ? 0.07 : 0.05), surface);

  /// Scrim behind modal sheets and full-screen overlays.
  Color get scrim =>
      isDark ? const Color(0xB3000000) : const Color(0x66000000);

  AppPalette copyWith({
    Brightness? brightness,
    Color? background,
    Color? surface,
    Color? surfaceRaised,
    Color? glassFill,
    Color? glassBorder,
    Color? hairline,
    Color? innerHighlight,
    Color? accent,
    Color? accentBright,
    Color? accentDeep,
    Color? onAccent,
    Color? secondary,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? danger,
    Color? success,
    Color? priorityLow,
    Color? shadow,
    Color? glowPrimary,
    Color? glowSecondary,
    PrayerHues? prayerHues,
    AppTypeface? typeface,
  }) {
    return AppPalette(
      brightness: brightness ?? this.brightness,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      glassFill: glassFill ?? this.glassFill,
      glassBorder: glassBorder ?? this.glassBorder,
      hairline: hairline ?? this.hairline,
      innerHighlight: innerHighlight ?? this.innerHighlight,
      accent: accent ?? this.accent,
      accentBright: accentBright ?? this.accentBright,
      accentDeep: accentDeep ?? this.accentDeep,
      onAccent: onAccent ?? this.onAccent,
      secondary: secondary ?? this.secondary,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      danger: danger ?? this.danger,
      success: success ?? this.success,
      priorityLow: priorityLow ?? this.priorityLow,
      shadow: shadow ?? this.shadow,
      glowPrimary: glowPrimary ?? this.glowPrimary,
      glowSecondary: glowSecondary ?? this.glowSecondary,
      prayerHues: prayerHues ?? this.prayerHues,
      typeface: typeface ?? this.typeface,
    );
  }

  /// Cross-fades two palettes. [brightness] and [typeface] cannot be
  /// interpolated, so they snap at the halfway point.
  static AppPalette lerp(AppPalette a, AppPalette b, double t) {
    Color c(Color x, Color y) => Color.lerp(x, y, t)!;
    return AppPalette(
      brightness: t < 0.5 ? a.brightness : b.brightness,
      background: c(a.background, b.background),
      surface: c(a.surface, b.surface),
      surfaceRaised: c(a.surfaceRaised, b.surfaceRaised),
      glassFill: c(a.glassFill, b.glassFill),
      glassBorder: c(a.glassBorder, b.glassBorder),
      hairline: c(a.hairline, b.hairline),
      innerHighlight: c(a.innerHighlight, b.innerHighlight),
      accent: c(a.accent, b.accent),
      accentBright: c(a.accentBright, b.accentBright),
      accentDeep: c(a.accentDeep, b.accentDeep),
      onAccent: c(a.onAccent, b.onAccent),
      secondary: c(a.secondary, b.secondary),
      textPrimary: c(a.textPrimary, b.textPrimary),
      textSecondary: c(a.textSecondary, b.textSecondary),
      textMuted: c(a.textMuted, b.textMuted),
      danger: c(a.danger, b.danger),
      success: c(a.success, b.success),
      priorityLow: c(a.priorityLow, b.priorityLow),
      shadow: c(a.shadow, b.shadow),
      glowPrimary: c(a.glowPrimary, b.glowPrimary),
      glowSecondary: c(a.glowSecondary, b.glowSecondary),
      prayerHues: PrayerHues.lerp(a.prayerHues, b.prayerHues, t),
      typeface: t < 0.5 ? a.typeface : b.typeface,
    );
  }
}
