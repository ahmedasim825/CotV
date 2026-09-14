import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The app's type scale.
///
/// Colours default to null on purpose, so text inherits from the enclosing
/// [DefaultTextStyle] rather than being pinned per call site.
@immutable
class AppTypography {
  const AppTypography();

  TextStyle display({
    double size = 56,
    Color? color,
    FontWeight weight = FontWeight.w600,
    double letterSpacing = -1.2,
    double height = 1.0,
  }) {
    return GoogleFonts.inter(
      fontSize: size,
      color: color,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      height: height,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  TextStyle ui({
    double size = 15,
    Color? color,
    FontWeight weight = FontWeight.w500,
    double? letterSpacing,
    double? height,
  }) {
    return GoogleFonts.inter(
      fontSize: size,
      color: color,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  TextStyle eyebrow({Color? color}) =>
      ui(size: 10.5, color: color, weight: FontWeight.w600, letterSpacing: 2.4);

  TextStyle mono({
    double size = 12.5,
    Color? color,
    FontWeight weight = FontWeight.w400,
    double? height,
  }) {
    return GoogleFonts.jetBrainsMono(
      fontSize: size,
      color: color,
      fontWeight: weight,
      height: height,
    );
  }

  /// The base [TextTheme] the [MaterialApp] installs, so any widget that
  /// does not style its own text still lands on the theme's font.
  TextTheme textTheme(TextTheme base) => GoogleFonts.interTextTheme(base);
}
