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
  // The ground itself: what `OrbFieldBackground` paints under the whole app,
  // and what the violet orbs drift over.
  background: Color(0xFF191717),
  surface: Color(0xFF212C36),
  surfaceRaised: Color(0xFF2A3644),
  glassFill: Color(0x14FFFFFF),
  glassBorder: Color(0x40FFFFFF),
  cardFill: Color(0x05FFFFFF),
  glassSpecular: Color(0x3DFFFFFF),
  hairline: Color(0x1AFFFFFF),
  innerHighlight: Color(0x38FFFFFF),
  accent: Color(0xFF7005BB),
  accentBright: Color(0xFFA855F7),
  accentDeep: Color(0xFF4A0378),
  onAccent: Color(0xFFFFFFFF),
  secondary: Color(0xFF22D3EE),
  textPrimary: Color(0xFFFFFFFF),
  textSecondary: Color(0xB3FFFFFF),
  // Opaque, unlike its two siblings. The ground now drifts underneath, and a
  // 45%-white token shimmers as an orb passes below the text.
  textMuted: Color(0xFFA4A4A4),
  danger: Color(0xFFEF4444),
  success: Color(0xFF22C55E),
  // Straight from the mock, and deliberately not `danger`: #EF4444 is the
  // app's "something is wrong" red, while #FF0000 here means "this row is a
  // reminder". Two jobs, two values.
  taskRing: Color(0xFFFFE100),
  reminderRing: Color(0xFFFF0000),
  priorityLow: Color(0xFFA0AAB8),
  priorityMedium: Color(0xFFFFB800),
  priorityHigh: Color(0xFFFF4D4D),
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

  /// Whether to draw the iOS shell: liquid-glass cards, the floating nav pill,
  /// Milo in the home pane rather than the sidebar, a gear in the home header.
  ///
  /// One definition on purpose — `grep useLiquidGlass` finds every gate, and
  /// there are only six, all of them composition decisions. Leaf widgets never
  /// ask the platform: [GlassCard] takes a `glass` flag instead, which is what
  /// keeps this from spreading into the drawing code.
  ///
  /// Reads [ThemeData.platform] rather than `defaultTargetPlatform` because
  /// [buildAppTheme] sets no `platform:`, so under `flutter_test` this is
  /// false and every pre-existing test keeps exercising the Windows path
  /// untouched. An iOS test opts in with
  /// `buildAppTheme().copyWith(platform: TargetPlatform.iOS)` — the same
  /// mechanism `test/milo_orb_test.dart` already uses to fake a platform.
  ///
  /// Costs a dependency on the whole [ThemeData], unlike [palette], which
  /// returns a const.
  ///
  /// Not combined with a width test, deliberately. The phone chrome — the nav
  /// pill, and the header gear it has no room for — needs
  /// `useLiquidGlass && windowSize.isCompact`, and that conjunction belongs at
  /// the call site, where `windowSize` comes from [AdaptiveLayout]'s own
  /// constraints. A getter here could only read [MediaQuery], which is the
  /// screen rather than the pane, and would size an iPad Split View wrong.
  bool get useLiquidGlass => Theme.of(this).platform == TargetPlatform.iOS;

  /// Whether the app draws its own window buttons and drag handle.
  ///
  /// True on Windows, where the runner reports the whole window as client area
  /// (`WM_NCCALCSIZE` in `windows/runner/win32_window.cpp`) and there is no
  /// caption left to move, minimise or close the window with. Every other
  /// platform's window is managed for it.
  ///
  /// Reads the theme rather than `dart:io`'s `Platform.isWindows` for the same
  /// reason [useLiquidGlass] does: `Platform` is true under `flutter_test` on
  /// a Windows machine, which would mount the chrome — and its 32pt inset — in
  /// every widget test that pumps the shell, on a window that does not exist.
  /// The cost is that `tool/ios_preview.dart`, which forces the iOS look onto
  /// a real Windows window, gets no buttons; Alt+F4 closes it.
  bool get useCustomWindowChrome =>
      Theme.of(this).platform == TargetPlatform.windows;
}

/// Builds the app's [ThemeData], carrying [kPalette] and [kTypography].
///
/// [background] overrides the ground. It lands on `scaffoldBackgroundColor`,
/// which [OrbFieldBackground] reads back out through `Theme.of`. The app itself
/// passes nothing — the ground is [AppPalette.background] — but the seam is
/// kept because it is the one place the ground can be swapped without reaching
/// into the background widget, and tests use it.
ThemeData buildAppTheme({Color? background}) {
  const palette = kPalette;
  final base = palette.isDark
      ? ThemeData.dark(useMaterial3: true)
      : ThemeData.light(useMaterial3: true);

  // The flat hover/press overlay every bare InkWell and IconButton falls
  // back to when it sets no color of its own — see `_inkOverlay` below.
  // Kept out of `highlightColor`/`hoverColor` so its two states (press,
  // hover-or-focus) share one definition with `iconButtonTheme`'s.
  Color inkOverlay(Set<WidgetState> states) {
    if (states.contains(WidgetState.pressed)) {
      return palette.accent.withValues(alpha: 0.12);
    }
    if (states.contains(WidgetState.hovered) ||
        states.contains(WidgetState.focused)) {
      return palette.accent.withValues(alpha: 0.08);
    }
    return Colors.transparent;
  }

  return base.copyWith(
    scaffoldBackgroundColor: background ?? palette.background,
    colorScheme: base.colorScheme.copyWith(
      brightness: palette.brightness,
      primary: palette.accent,
      onPrimary: palette.onAccent,
      secondary: palette.secondary,
      // M3 paints a selected `SegmentedButton` segment from these two —
      // unmapped, it falls back to `ThemeData.dark()`'s stock purple-grey
      // rather than the app's own accent.
      secondaryContainer: palette.accent,
      onSecondaryContainer: palette.onAccent,
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
    // The ripple/splash animation stays off everywhere — every card in this
    // app hand-rolls its own hover state (see `GlassCard`'s `MouseRegion` +
    // lift) because a Material splash reads as a foreign gesture against
    // this design. `highlightColor`/`hoverColor` are not part of that: a
    // bare `InkWell` with no `overlayColor` of its own falls back to them
    // (see `ink_well.dart`), and this app has eight of those — sidebar rows,
    // the Milo dock's controls, the home-card pencil, the music widget's
    // transport buttons, the sidebar restore control — with nothing else
    // giving them press/hover feedback. Left transparent (as they were),
    // those eight render nothing under a pointer.
    splashFactory: NoSplash.splashFactory,
    highlightColor: palette.accent.withValues(alpha: 0.12),
    hoverColor: palette.accent.withValues(alpha: 0.08),
    // `IconButton` doesn't fall back to `highlightColor`/`hoverColor` above —
    // Material 3's default `overlayColor` for it is its own
    // `WidgetStateProperty`, independent of those theme fields — so it needs
    // the same overlay mapped here explicitly.
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(overlayColor: WidgetStateProperty.resolveWith(inkOverlay)),
    ),
  );
}
