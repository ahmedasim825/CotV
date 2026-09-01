import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens for the app's visual language: an "Ethereal Glass" surface
/// (deep near-black, frosted glass cards) carrying a warm amber glow instead
/// of the archetype's usual cool purple/emerald — meant to read as lamplight
/// rather than a SaaS dashboard, fitting a prayer app.
class AppPalette {
  const AppPalette._();

  static const Color background = Color(0xFF07070A);
  static const Color surface = Color(0xFF121016);
  static const Color glassFill = Color(0x14FFFFFF);
  static const Color glassBorder = Color(0x1FFFFFFF);
  static const Color hairline = Color(0x14FFFFFF);
  static const Color innerHighlight = Color(0x26FFFFFF);

  static const Color amber = Color(0xFFD8A657);
  static const Color amberBright = Color(0xFFF2C879);
  static const Color amberDeep = Color(0xFF8A5A2A);
  static const Color onAmber = Color(0xFF1D1408);

  static const Color textPrimary = Color(0xFFF6F3EC);
  static const Color textSecondary = Color(0xB3F6F3EC);
  static const Color textMuted = Color(0x73F6F3EC);
  static const Color danger = Color(0xFFE2836B);
  static const Color success = Color(0xFF8FBF9F);
}

/// A single custom easing curve (equivalent to CSS
/// `cubic-bezier(0.32, 0.72, 0, 1)`) used for every transition in the app —
/// a quick, weighted departure that settles softly, never linear/easeInOut.
class AppMotion {
  const AppMotion._();

  static const Curve spring = Cubic(0.32, 0.72, 0.0, 1.0);
  static const Duration fast = Duration(milliseconds: 320);
  static const Duration base = Duration(milliseconds: 700);
  static const Duration slow = Duration(milliseconds: 900);
}

class AppTypography {
  const AppTypography._();

  /// Big editorial numerals — prayer times, hero countdowns.
  static TextStyle display({
    double size = 56,
    Color color = AppPalette.textPrimary,
    FontWeight weight = FontWeight.w500,
  }) {
    return GoogleFonts.fraunces(
      fontSize: size,
      color: color,
      fontWeight: weight,
      height: 1.0,
      letterSpacing: -1.2,
    );
  }

  /// General UI text — a premium geometric grotesk (never Inter/Roboto).
  static TextStyle ui({
    double size = 15,
    Color color = AppPalette.textPrimary,
    FontWeight weight = FontWeight.w500,
    double? letterSpacing,
    double? height,
  }) {
    return GoogleFonts.plusJakartaSans(
      fontSize: size,
      color: color,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  /// Microscopic tracked-out label used above section headings.
  static TextStyle eyebrow({Color color = AppPalette.amber}) {
    return GoogleFonts.plusJakartaSans(
      fontSize: 10.5,
      color: color,
      fontWeight: FontWeight.w600,
      letterSpacing: 2.4,
    );
  }
}

ThemeData buildAppTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AppPalette.background,
    colorScheme: base.colorScheme.copyWith(
      primary: AppPalette.amber,
      onPrimary: AppPalette.onAmber,
      surface: AppPalette.surface,
      error: AppPalette.danger,
    ),
    textTheme: GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(
      bodyColor: AppPalette.textPrimary,
      displayColor: AppPalette.textPrimary,
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
  );
}
