import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The app's type scale.
///
/// Colours default to null on purpose, so text inherits from the enclosing
/// [DefaultTextStyle] rather than being pinned per call site.
///
/// On iOS every method drops Inter and returns a family-less [TextStyle], so
/// the text resolves through the ambient [DefaultTextStyle] to the system face
/// — SF Pro, already on the device, in the optical size iOS picks for the
/// point size. Nothing is bundled and there is no licence question, which both
/// a vendored copy of SF Pro would carry. Inter stays everywhere else.
///
/// The check is [defaultTargetPlatform] rather than `Theme.of(context).platform`
/// because these methods take no context, and threading one through the ~246
/// `context.typography` call sites to gain a per-theme font would buy nothing
/// the app uses. The visible consequence is that `test/ios_shell_test.dart`
/// keeps rendering Inter: it switches platform with
/// `buildAppTheme().copyWith(platform: ...)` rather than
/// `debugDefaultTargetPlatformOverride`, deliberately, and this gate cannot see
/// that. No test asserts on text metrics, so nothing breaks either way.
@immutable
class AppTypography {
  const AppTypography();

  bool get _usesSystemFont => defaultTargetPlatform == TargetPlatform.iOS;

  TextStyle display({
    double size = 56,
    Color? color,
    FontWeight weight = FontWeight.w600,
    double letterSpacing = -1.2,
    double height = 1.0,
  }) {
    if (_usesSystemFont) {
      return TextStyle(
        fontSize: size,
        color: color,
        fontWeight: weight,
        letterSpacing: letterSpacing,
        height: height,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
    }
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
    if (_usesSystemFont) {
      return TextStyle(
        fontSize: size,
        color: color,
        fontWeight: weight,
        letterSpacing: letterSpacing,
        height: height,
      );
    }
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

  /// Stays JetBrains Mono on every platform. SF Mono ships with Xcode rather
  /// than with iOS, so there is no system monospace to fall through to.
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
  ///
  /// Returned untouched on iOS: [ThemeData] already builds this from
  /// `Typography.blackCupertino`/`whiteCupertino` there, whose styles name the
  /// system face. That is also what supplies the family to the family-less
  /// styles the methods above return.
  TextTheme textTheme(TextTheme base) =>
      _usesSystemFont ? base : GoogleFonts.interTextTheme(base);
}
