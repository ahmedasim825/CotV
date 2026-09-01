import 'package:flutter/widgets.dart';

/// Ultra-light Phosphor icon glyphs, built directly against the
/// `phosphor_flutter` package's bundled font asset.
///
/// We can't use that package's own `PhosphorIconsLight` class: as of this
/// Flutter SDK, `IconData` is a `final` class, and `phosphor_flutter`
/// 2.1.0 (unmaintained since 2024-05) still subclasses it, so the package
/// fails to compile at all. Its font asset still ships and loads fine —
/// only the Dart wrapper classes are broken — so we construct [IconData]
/// directly against `PhosphorLight`/`phosphor_flutter`, using the same
/// codepoints the package itself defines.
class PhLight {
  const PhLight._();

  static const String _family = 'PhosphorLight';
  static const String _package = 'phosphor_flutter';

  static const IconData arrowClockwise =
      IconData(0xe036, fontFamily: _family, fontPackage: _package);
  static const IconData bellSimple =
      IconData(0xe0d0, fontFamily: _family, fontPackage: _package);
  static const IconData bellSimpleRinging =
      IconData(0xe5ea, fontFamily: _family, fontPackage: _package);
  static const IconData bellSimpleSlash =
      IconData(0xe0d2, fontFamily: _family, fontPackage: _package);
  static const IconData calendarBlank =
      IconData(0xe10a, fontFamily: _family, fontPackage: _package);
  static const IconData calendarCheck =
      IconData(0xe712, fontFamily: _family, fontPackage: _package);
  static const IconData calendarDots =
      IconData(0xe7b4, fontFamily: _family, fontPackage: _package);
  static const IconData caretLeft =
      IconData(0xe138, fontFamily: _family, fontPackage: _package);
  static const IconData caretRight =
      IconData(0xe13a, fontFamily: _family, fontPackage: _package);
  static const IconData check =
      IconData(0xe182, fontFamily: _family, fontPackage: _package);
  static const IconData checkCircle =
      IconData(0xe184, fontFamily: _family, fontPackage: _package);
  static const IconData circle =
      IconData(0xe18a, fontFamily: _family, fontPackage: _package);
  static const IconData clock =
      IconData(0xe19a, fontFamily: _family, fontPackage: _package);
  static const IconData clockCountdown =
      IconData(0xed2c, fontFamily: _family, fontPackage: _package);
  static const IconData cloudSun =
      IconData(0xe540, fontFamily: _family, fontPackage: _package);
  static const IconData crosshairSimple =
      IconData(0xe1d8, fontFamily: _family, fontPackage: _package);
  static const IconData fingerprint =
      IconData(0xe23e, fontFamily: _family, fontPackage: _package);
  static const IconData flagPennant =
      IconData(0xecf0, fontFamily: _family, fontPackage: _package);
  static const IconData listChecks =
      IconData(0xeadc, fontFamily: _family, fontPackage: _package);
  static const IconData lock =
      IconData(0xe2fa, fontFamily: _family, fontPackage: _package);
  static const IconData lockKeyOpen =
      IconData(0xe300, fontFamily: _family, fontPackage: _package);
  static const IconData moon =
      IconData(0xe330, fontFamily: _family, fontPackage: _package);
  static const IconData moonStars =
      IconData(0xe58e, fontFamily: _family, fontPackage: _package);
  static const IconData mosque =
      IconData(0xecee, fontFamily: _family, fontPackage: _package);
  static const IconData notePencil =
      IconData(0xe34c, fontFamily: _family, fontPackage: _package);
  static const IconData pauseCircle =
      IconData(0xe3a0, fontFamily: _family, fontPackage: _package);
  static const IconData playCircle =
      IconData(0xe3d2, fontFamily: _family, fontPackage: _package);
  static const IconData plus =
      IconData(0xe3d4, fontFamily: _family, fontPackage: _package);
  static const IconData sortAscending =
      IconData(0xe444, fontFamily: _family, fontPackage: _package);
  static const IconData sparkle =
      IconData(0xe6a2, fontFamily: _family, fontPackage: _package);
  static const IconData sun =
      IconData(0xe472, fontFamily: _family, fontPackage: _package);
  static const IconData sunDim =
      IconData(0xe474, fontFamily: _family, fontPackage: _package);
  static const IconData sunHorizon =
      IconData(0xe5b6, fontFamily: _family, fontPackage: _package);
  static const IconData tag =
      IconData(0xe478, fontFamily: _family, fontPackage: _package);
  static const IconData textAlignLeft =
      IconData(0xe484, fontFamily: _family, fontPackage: _package);
  static const IconData timer =
      IconData(0xe492, fontFamily: _family, fontPackage: _package);
  static const IconData trash =
      IconData(0xe4a6, fontFamily: _family, fontPackage: _package);
  static const IconData warningCircle =
      IconData(0xe4e2, fontFamily: _family, fontPackage: _package);
  static const IconData x =
      IconData(0xe4f6, fontFamily: _family, fontPackage: _package);
  static const IconData xCircle =
      IconData(0xe4f8, fontFamily: _family, fontPackage: _package);
}
