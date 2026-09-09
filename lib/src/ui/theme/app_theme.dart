import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'app_typography.dart';

export 'app_palette.dart';
export 'app_typography.dart';

/// The minimum comfortable touch target, in logical pixels. Controls whose
/// painted size is smaller than this pad their hit area out to it rather than
/// growing visually.
const double minTouchTarget = 44;

/// A single custom easing curve (equivalent to CSS
/// `cubic-bezier(0.32, 0.72, 0, 1)`) used for every transition in the app —
/// a quick, weighted departure that settles softly, never linear/easeInOut.
class AppMotion {
  const AppMotion._();

  static const Curve spring = Cubic(0.32, 0.72, 0.0, 1.0);

  /// A pointer-hover lift. Shorter than [fast], and the one transition in
  /// the app that eases out rather than springing: a hover that lags the
  /// cursor reads as the app thinking rather than as the card answering.
  static const Duration hover = Duration(milliseconds: 200);

  static const Duration fast = Duration(milliseconds: 320);
  static const Duration base = Duration(milliseconds: 700);
  static const Duration slow = Duration(milliseconds: 900);

  /// How long a theme switch cross-fades for. Slower than [fast] so the
  /// whole surface reads as one considered change rather than a flicker.
  static const Duration themeSwitch = Duration(milliseconds: 450);
}

/// [AppMotion]'s durations, collapsed to zero when the platform asks for
/// reduced motion.
///
/// Reach it as `context.motion` and use it for every implicit animation, so
/// the accessibility setting is honoured in one place instead of each widget
/// remembering to check. Colour and opacity still change; they just change
/// instantly, which is what the setting asks for.
@immutable
class AppMotionScale {
  const AppMotionScale({required this.isReduced});

  final bool isReduced;

  Duration get hover => isReduced ? Duration.zero : AppMotion.hover;

  Duration get fast => isReduced ? Duration.zero : AppMotion.fast;

  Duration get base => isReduced ? Duration.zero : AppMotion.base;

  Duration get slow => isReduced ? Duration.zero : AppMotion.slow;
}

// ---------------------------------------------------------------------------
// Theme definitions
// ---------------------------------------------------------------------------

/// The app's one palette: deep violet on a slate ground.
const AppPalette kPalette = AppPalette(
  brightness: Brightness.dark,
  background: Color(0xFF1B252E),
  surface: Color(0xFF212C36),
  surfaceRaised: Color(0xFF2A3644),
  glassFill: Color(0x14FFFFFF),
  glassBorder: Color(0x2EFFFFFF),
  glassSurface: Color(0xA6212C36),
  glassSpecular: Color(0x2EFFFFFF),
  hairline: Color(0x1AFFFFFF),
  innerHighlight: Color(0x26FFFFFF),
  accent: Color(0xFF7005BB),
  accentBright: Color(0xFFA855F7),
  accentDeep: Color(0xFF4A0378),
  onAccent: Color(0xFFFFFFFF),
  secondary: Color(0xFF22D3EE),
  textPrimary: Color(0xFFFFFFFF),
  textSecondary: Color(0xB3FFFFFF),
  textMuted: Color(0x73FFFFFF),
  danger: Color(0xFFEF4444),
  success: Color(0xFF22C55E),
  priorityLow: Color(0xFF7FA3B8),
  shadow: Color(0x66000000),
  glowPrimary: Color(0x4D7005BB),
  glowSecondary: Color(0x2622D3EE),
  prayerHues: PrayerHues(
    fajr: Color(0xFF7B8FCB),
    sunrise: Color(0xFFE9B08C),
    dhuhr: Color(0xFFE8C36B),
    asr: Color(0xFFD8A657),
    maghrib: Color(0xFFC97A55),
    isha: Color(0xFF5C6BA8),
  ),
);

const AppTypography kTypography = AppTypography();

// ---------------------------------------------------------------------------
// Theme plumbing
// ---------------------------------------------------------------------------

/// `context.palette` / `context.typography` — the way every widget in the
/// app reaches its design tokens.
extension AppSkinContext on BuildContext {
  AppPalette get palette => kPalette;

  AppTypography get typography => kTypography;

  AppMotionScale get motion =>
      AppMotionScale(isReduced: MediaQuery.maybeDisableAnimationsOf(this) ?? false);
}

/// Builds the app's [ThemeData], carrying [kPalette] and [kTypography].
ThemeData buildAppTheme() {
  const palette = kPalette;
  final base = palette.isDark
      ? ThemeData.dark(useMaterial3: true)
      : ThemeData.light(useMaterial3: true);

  return base.copyWith(
    scaffoldBackgroundColor: palette.background,
    colorScheme: base.colorScheme.copyWith(
      brightness: palette.brightness,
      primary: palette.accent,
      onPrimary: palette.onAccent,
      secondary: palette.secondary,
      surface: palette.surface,
      onSurface: palette.textPrimary,
      // Mapped so a widget reaching through Material rather than
      // `context.palette` — a Flutter-supplied border, a package's card —
      // lands on the same hairline everything else is drawn with.
      outline: palette.hairline,
      error: palette.danger,
    ),
    // Text that names no color of its own inherits from here, which is
    // what lets a theme switch re-color the whole app.
    textTheme: kTypography.textTheme(base.textTheme).apply(
          bodyColor: palette.textPrimary,
          displayColor: palette.textPrimary,
        ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
  );
}
