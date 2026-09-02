import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'app_typography.dart';

export 'app_palette.dart';
export 'app_typography.dart';

/// A single custom easing curve (equivalent to CSS
/// `cubic-bezier(0.32, 0.72, 0, 1)`) used for every transition in the app —
/// a quick, weighted departure that settles softly, never linear/easeInOut.
class AppMotion {
  const AppMotion._();

  static const Curve spring = Cubic(0.32, 0.72, 0.0, 1.0);
  static const Duration fast = Duration(milliseconds: 320);
  static const Duration base = Duration(milliseconds: 700);
  static const Duration slow = Duration(milliseconds: 900);

  /// How long a theme switch cross-fades for. Slower than [fast] so the
  /// whole surface reads as one considered change rather than a flicker.
  static const Duration themeSwitch = Duration(milliseconds: 450);
}

// ---------------------------------------------------------------------------
// Theme definitions
// ---------------------------------------------------------------------------

/// The house theme: deep slate, emerald accents, warm gold highlights.
const AppPalette _sanctuary = AppPalette(
  brightness: Brightness.dark,
  background: Color(0xFF080D0F),
  surface: Color(0xFF101719),
  surfaceRaised: Color(0xFF182124),
  glassFill: Color(0x14FFFFFF),
  glassBorder: Color(0x1FFFFFFF),
  hairline: Color(0x14FFFFFF),
  innerHighlight: Color(0x26FFFFFF),
  accent: Color(0xFF34D399),
  accentBright: Color(0xFF6EE7B7),
  accentDeep: Color(0xFF0E5C46),
  onAccent: Color(0xFF04140E),
  secondary: Color(0xFFE5B769),
  textPrimary: Color(0xFFEAF2F0),
  textSecondary: Color(0xB3EAF2F0),
  textMuted: Color(0x73EAF2F0),
  danger: Color(0xFFEF8674),
  success: Color(0xFF34D399),
  priorityLow: Color(0xFF7FA3B8),
  shadow: Color(0x59000000),
  glowPrimary: Color(0x4D107054),
  glowSecondary: Color(0x26E5B769),
  prayerHues: PrayerHues(
    fajr: Color(0xFF7B8FCB),
    sunrise: Color(0xFFE9B08C),
    dhuhr: Color(0xFFE8C36B),
    asr: Color(0xFFD8A657),
    maghrib: Color(0xFFC97A55),
    isha: Color(0xFF5C6BA8),
  ),
  typeface: AppTypeface.frauncesJakarta,
);

/// The "Ethereal Glass" lamplight theme Parts 1 and 2 were built in, kept
/// selectable so the earlier look is not lost.
const AppPalette _etherealAmber = AppPalette(
  brightness: Brightness.dark,
  background: Color(0xFF07070A),
  surface: Color(0xFF121016),
  surfaceRaised: Color(0xFF1B1820),
  glassFill: Color(0x14FFFFFF),
  glassBorder: Color(0x1FFFFFFF),
  hairline: Color(0x14FFFFFF),
  innerHighlight: Color(0x26FFFFFF),
  accent: Color(0xFFD8A657),
  accentBright: Color(0xFFF2C879),
  accentDeep: Color(0xFF8A5A2A),
  onAccent: Color(0xFF1D1408),
  secondary: Color(0xFFE0A183),
  textPrimary: Color(0xFFF6F3EC),
  textSecondary: Color(0xB3F6F3EC),
  textMuted: Color(0x73F6F3EC),
  danger: Color(0xFFE2836B),
  success: Color(0xFF8FBF9F),
  priorityLow: Color(0xFF7FA3B8),
  shadow: Color(0x40000000),
  glowPrimary: Color(0x598A5A2A),
  glowSecondary: Color(0x29D8A657),
  prayerHues: PrayerHues(
    fajr: Color(0xFF7B7BB5),
    sunrise: Color(0xFFE0A183),
    dhuhr: Color(0xFFE8C36B),
    asr: Color(0xFFD8A657),
    maghrib: Color(0xFFC97A55),
    isha: Color(0xFF5C6BA8),
  ),
  typeface: AppTypeface.frauncesJakarta,
);

/// True black with iOS system colors — the reference "Apple Minimal" board.
const AppPalette _appleMinimal = AppPalette(
  brightness: Brightness.dark,
  background: Color(0xFF000000),
  surface: Color(0xFF1C1C1E),
  surfaceRaised: Color(0xFF2C2C2E),
  glassFill: Color(0x14FFFFFF),
  glassBorder: Color(0x1FFFFFFF),
  hairline: Color(0x1AFFFFFF),
  innerHighlight: Color(0x1FFFFFFF),
  accent: Color(0xFF0A84FF),
  accentBright: Color(0xFF4DA3FF),
  accentDeep: Color(0xFF0A4F99),
  onAccent: Color(0xFFFFFFFF),
  secondary: Color(0xFFFFD60A),
  textPrimary: Color(0xFFF5F5F7),
  textSecondary: Color(0xFFAEAEB2),
  textMuted: Color(0xFF98989D),
  danger: Color(0xFFFF453A),
  success: Color(0xFF30D158),
  priorityLow: Color(0xFF64D2FF),
  shadow: Color(0x66000000),
  glowPrimary: Color(0x330A84FF),
  glowSecondary: Color(0x1AFFD60A),
  prayerHues: PrayerHues(
    fajr: Color(0xFF5E5CE6),
    sunrise: Color(0xFFFF9F0A),
    dhuhr: Color(0xFFFFD60A),
    asr: Color(0xFFFFB340),
    maghrib: Color(0xFFFF6B4A),
    isha: Color(0xFF0A84FF),
  ),
  typeface: AppTypeface.interInter,
);

/// Brushed near-black greys with a cool cast and no chromatic accent —
/// state is carried by brightness and contrast instead of hue.
const AppPalette _titanium = AppPalette(
  brightness: Brightness.dark,
  background: Color(0xFF090A0B),
  surface: Color(0xFF141517),
  surfaceRaised: Color(0xFF222427),
  glassFill: Color(0x12FFFFFF),
  glassBorder: Color(0x1FFFFFFF),
  hairline: Color(0x14FFFFFF),
  innerHighlight: Color(0x24FFFFFF),
  accent: Color(0xFFB8BCC3),
  accentBright: Color(0xFFE7E7E9),
  accentDeep: Color(0xFF4A4D52),
  onAccent: Color(0xFF090A0B),
  secondary: Color(0xFF8B8D91),
  textPrimary: Color(0xFFE7E7E9),
  textSecondary: Color(0xFFB8BCC3),
  textMuted: Color(0xFF8B8D91),
  danger: Color(0xFFD98878),
  success: Color(0xFF9FC0A8),
  priorityLow: Color(0xFF7F868E),
  shadow: Color(0x73000000),
  glowPrimary: Color(0x1FB8BCC3),
  glowSecondary: Color(0x14E7E7E9),
  prayerHues: PrayerHues(
    fajr: Color(0xFF6E7378),
    sunrise: Color(0xFFA9AEB4),
    dhuhr: Color(0xFFC8CCD1),
    asr: Color(0xFFB8BCC3),
    maghrib: Color(0xFF8E9297),
    isha: Color(0xFF5D6166),
  ),
  typeface: AppTypeface.spaceGroteskInter,
);

/// Almost zero color: pure neutral steps, state read through brightness,
/// blur and typography.
const AppPalette _monochrome = AppPalette(
  brightness: Brightness.dark,
  background: Color(0xFF080808),
  surface: Color(0xFF141414),
  surfaceRaised: Color(0xFF202020),
  glassFill: Color(0x12FFFFFF),
  glassBorder: Color(0x1FFFFFFF),
  hairline: Color(0x14FFFFFF),
  innerHighlight: Color(0x24FFFFFF),
  accent: Color(0xFFF1F1F1),
  accentBright: Color(0xFFFFFFFF),
  accentDeep: Color(0xFF3A3A3A),
  onAccent: Color(0xFF080808),
  secondary: Color(0xFFC5C5C5),
  textPrimary: Color(0xFFF1F1F1),
  textSecondary: Color(0xFFC5C5C5),
  textMuted: Color(0xFF8A8A8A),
  // Kept barely chromatic rather than pure grey: a destructive action still
  // has to read as one at a glance.
  danger: Color(0xFFC08C82),
  success: Color(0xFF8FA894),
  priorityLow: Color(0xFF6E6E6E),
  shadow: Color(0x73000000),
  glowPrimary: Color(0x1AFFFFFF),
  glowSecondary: Color(0x0FFFFFFF),
  prayerHues: PrayerHues(
    fajr: Color(0xFF5A5A5A),
    sunrise: Color(0xFF9A9A9A),
    dhuhr: Color(0xFFE0E0E0),
    asr: Color(0xFFC5C5C5),
    maghrib: Color(0xFF8A8A8A),
    isha: Color(0xFF6E6E6E),
  ),
  typeface: AppTypeface.interInter,
);

/// The one light theme: a slightly warm white rather than a clinical one,
/// with a periwinkle accent.
const AppPalette _pearl = AppPalette(
  brightness: Brightness.light,
  background: Color(0xFFFAF9F6),
  surface: Color(0xFFFFFFFF),
  surfaceRaised: Color(0xFFF0EFEB),
  // On a light ground the glass tokens invert: a dark wash and dark
  // hairlines, with white as the inset highlight.
  glassFill: Color(0x0A000000),
  glassBorder: Color(0x14000000),
  hairline: Color(0x14000000),
  innerHighlight: Color(0xCCFFFFFF),
  accent: Color(0xFF8C9EFF),
  accentBright: Color(0xFFA9B6FF),
  accentDeep: Color(0xFF5566D6),
  onAccent: Color(0xFFFFFFFF),
  secondary: Color(0xFFE0A96D),
  textPrimary: Color(0xFF1D1D1F),
  textSecondary: Color(0xFF5A5A5C),
  textMuted: Color(0xFF858585),
  danger: Color(0xFFD9544D),
  success: Color(0xFF3F9E6B),
  priorityLow: Color(0xFF6E8CA8),
  shadow: Color(0x14000000),
  glowPrimary: Color(0x2E8C9EFF),
  glowSecondary: Color(0x1FE0A96D),
  prayerHues: PrayerHues(
    fajr: Color(0xFF7C86D6),
    sunrise: Color(0xFFE2A06E),
    dhuhr: Color(0xFFD9A441),
    asr: Color(0xFFC98F4A),
    maghrib: Color(0xFFC4715A),
    isha: Color(0xFF5E6BB5),
  ),
  typeface: AppTypeface.frauncesDmSans,
);

/// Every theme the picker offers.
///
/// [id] is what gets persisted — a stable string rather than an enum index,
/// so reordering or removing a variant can never silently repoint a saved
/// preference at a different theme.
enum AppThemeVariant {
  sanctuary(
    id: 'sanctuary',
    label: 'Sanctuary',
    tagline: 'Deep slate, emerald, warm gold',
    palette: _sanctuary,
  ),
  etherealAmber(
    id: 'ethereal_amber',
    label: 'Ethereal',
    tagline: 'Lamplight amber on near-black',
    palette: _etherealAmber,
  ),
  appleMinimal(
    id: 'apple_minimal',
    label: 'Apple Minimal',
    tagline: 'True black, iOS system blue',
    palette: _appleMinimal,
  ),
  titanium(
    id: 'titanium',
    label: 'Titanium',
    tagline: 'Brushed grey, no strong accent',
    palette: _titanium,
  ),
  monochrome(
    id: 'monochrome',
    label: 'Monochrome',
    tagline: 'Almost zero color',
    palette: _monochrome,
  ),
  pearl(
    id: 'pearl',
    label: 'Pearl',
    tagline: 'Warm white, calm and clean',
    palette: _pearl,
  );

  const AppThemeVariant({
    required this.id,
    required this.label,
    required this.tagline,
    required this.palette,
  });

  final String id;
  final String label;
  final String tagline;
  final AppPalette palette;

  AppSkin get skin => AppSkin(variant: this, palette: palette);

  /// Used whenever nothing has been chosen yet, and whenever a persisted
  /// [id] no longer matches a known theme.
  static const AppThemeVariant fallback = AppThemeVariant.sanctuary;

  static AppThemeVariant fromId(String? id) {
    for (final variant in values) {
      if (variant.id == id) return variant;
    }
    return fallback;
  }
}

// ---------------------------------------------------------------------------
// Theme plumbing
// ---------------------------------------------------------------------------

/// Carries the active [AppPalette] (and the typography that goes with it)
/// down the tree as a [ThemeExtension].
///
/// Going through the theme rather than a Riverpod provider means every
/// plain [StatelessWidget] can read the palette from its [BuildContext],
/// and Flutter animates the switch between two themes for free.
@immutable
class AppSkin extends ThemeExtension<AppSkin> {
  const AppSkin({required this.variant, required this.palette});

  final AppThemeVariant variant;
  final AppPalette palette;

  AppTypography get typography => AppTypography(palette.typeface);

  @override
  AppSkin copyWith({AppThemeVariant? variant, AppPalette? palette}) {
    return AppSkin(
      variant: variant ?? this.variant,
      palette: palette ?? this.palette,
    );
  }

  @override
  AppSkin lerp(covariant ThemeExtension<AppSkin>? other, double t) {
    if (other is! AppSkin) return this;
    return AppSkin(
      variant: t < 0.5 ? variant : other.variant,
      palette: AppPalette.lerp(palette, other.palette, t),
    );
  }
}

/// `context.palette` / `context.typography` — the way every widget in the
/// app reaches its design tokens.
extension AppSkinContext on BuildContext {
  AppSkin get skin =>
      Theme.of(this).extension<AppSkin>() ?? AppThemeVariant.fallback.skin;

  AppPalette get palette => skin.palette;

  AppTypography get typography => skin.typography;
}

/// Builds the [ThemeData] for [variant], with the palette attached as an
/// [AppSkin] extension.
ThemeData buildAppTheme(AppThemeVariant variant) {
  final palette = variant.palette;
  final typography = AppTypography(palette.typeface);
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
      error: palette.danger,
    ),
    // Text that names no color of its own inherits from here, which is
    // what lets a theme switch re-color the whole app.
    textTheme: typography.textTheme(base.textTheme).apply(
          bodyColor: palette.textPrimary,
          displayColor: palette.textPrimary,
        ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    extensions: <ThemeExtension<dynamic>>[
      AppSkin(variant: variant, palette: palette),
    ],
  );
}
