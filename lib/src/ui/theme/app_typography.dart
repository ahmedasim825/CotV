import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_palette.dart';

/// Text styles for one theme's [AppTypeface] pairing.
///
/// Reach it from any widget with `context.typography` (see
/// `app_theme.dart`). Colors default to null on purpose: an unstyled color
/// inherits from the ambient [DefaultTextStyle], which
/// [buildAppTheme] points at the active palette's `textPrimary` — so text
/// re-colors itself on a theme switch without every call site naming a
/// color.
@immutable
class AppTypography {
  const AppTypography(this.face);

  final AppTypeface face;

  /// Big editorial numerals — prayer times, hero countdowns, screen titles.
  ///
  /// Figures are tabular: this face carries every number that sits in a
  /// column or ticks down, and proportional digits make those jump sideways
  /// as the value changes.
  TextStyle display({
    double size = 56,
    Color? color,
    FontWeight weight = FontWeight.w500,
    double letterSpacing = -1.2,
    double height = 1.0,
  }) {
    final style = TextStyle(
      fontSize: size,
      color: color,
      fontWeight: weight,
      height: height,
      letterSpacing: letterSpacing,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    switch (face) {
      case AppTypeface.frauncesJakarta:
      case AppTypeface.frauncesDmSans:
        return GoogleFonts.fraunces(textStyle: style);
      case AppTypeface.spaceGroteskInter:
        return GoogleFonts.spaceGrotesk(textStyle: style);
      case AppTypeface.interInter:
        return GoogleFonts.inter(textStyle: style);
    }
  }

  /// General UI text.
  TextStyle ui({
    double size = 15,
    Color? color,
    FontWeight weight = FontWeight.w500,
    double? letterSpacing,
    double? height,
  }) {
    final style = TextStyle(
      fontSize: size,
      color: color,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      height: height,
    );
    switch (face) {
      case AppTypeface.frauncesJakarta:
        return GoogleFonts.plusJakartaSans(textStyle: style);
      case AppTypeface.frauncesDmSans:
        return GoogleFonts.dmSans(textStyle: style);
      case AppTypeface.interInter:
      case AppTypeface.spaceGroteskInter:
        return GoogleFonts.inter(textStyle: style);
    }
  }

  /// Microscopic tracked-out label used above section headings.
  TextStyle eyebrow({Color? color}) => ui(
        size: 10.5,
        color: color,
        weight: FontWeight.w600,
        letterSpacing: 2.4,
      );

  /// Fixed-width, for coordinate readouts and other tabular figures.
  TextStyle mono({
    double size = 12.5,
    Color? color,
    FontWeight weight = FontWeight.w400,
    double? height,
  }) {
    return GoogleFonts.jetBrainsMono(
      textStyle: TextStyle(
        fontSize: size,
        color: color,
        fontWeight: weight,
        height: height,
      ),
    );
  }

  /// The base [TextTheme] the [MaterialApp] installs, so any widget that
  /// does not style its own text still lands on the theme's font.
  TextTheme textTheme(TextTheme base) {
    switch (face) {
      case AppTypeface.frauncesJakarta:
        return GoogleFonts.plusJakartaSansTextTheme(base);
      case AppTypeface.frauncesDmSans:
        return GoogleFonts.dmSansTextTheme(base);
      case AppTypeface.interInter:
      case AppTypeface.spaceGroteskInter:
        return GoogleFonts.interTextTheme(base);
    }
  }
}
