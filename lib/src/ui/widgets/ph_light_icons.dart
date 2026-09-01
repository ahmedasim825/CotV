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
  static const IconData bellSimpleRinging =
      IconData(0xe5ea, fontFamily: _family, fontPackage: _package);
  static const IconData calendarCheck =
      IconData(0xe712, fontFamily: _family, fontPackage: _package);
  static const IconData checkCircle =
      IconData(0xe184, fontFamily: _family, fontPackage: _package);
  static const IconData cloudSun =
      IconData(0xe540, fontFamily: _family, fontPackage: _package);
  static const IconData moon =
      IconData(0xe330, fontFamily: _family, fontPackage: _package);
  static const IconData moonStars =
      IconData(0xe58e, fontFamily: _family, fontPackage: _package);
  static const IconData sun =
      IconData(0xe472, fontFamily: _family, fontPackage: _package);
  static const IconData sunDim =
      IconData(0xe474, fontFamily: _family, fontPackage: _package);
  static const IconData sunHorizon =
      IconData(0xe5b6, fontFamily: _family, fontPackage: _package);
  static const IconData warningCircle =
      IconData(0xe4e2, fontFamily: _family, fontPackage: _package);
  static const IconData xCircle =
      IconData(0xe4f8, fontFamily: _family, fontPackage: _package);
}
