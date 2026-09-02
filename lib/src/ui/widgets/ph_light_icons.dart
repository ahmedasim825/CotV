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
///
/// Generated from the package's `phosphor_icons_light.dart` table; add a
/// glyph by copying its codepoint from there rather than guessing one.
class PhLight {
  const PhLight._();

  static const String _family = 'PhosphorLight';
  static const String _package = 'phosphor_flutter';

  static const IconData arrowClockwise =
      IconData(0xe036, fontFamily: _family, fontPackage: _package);
  static const IconData arrowLeft =
      IconData(0xe058, fontFamily: _family, fontPackage: _package);
  static const IconData bellSimple =
      IconData(0xe0d0, fontFamily: _family, fontPackage: _package);
  static const IconData bellSimpleRinging =
      IconData(0xe5ea, fontFamily: _family, fontPackage: _package);
  static const IconData bellSimpleSlash =
      IconData(0xe0d2, fontFamily: _family, fontPackage: _package);
  static const IconData bookOpen =
      IconData(0xe0e6, fontFamily: _family, fontPackage: _package);
  static const IconData brain =
      IconData(0xe74e, fontFamily: _family, fontPackage: _package);
  static const IconData calendarBlank =
      IconData(0xe10a, fontFamily: _family, fontPackage: _package);
  static const IconData calendarCheck =
      IconData(0xe712, fontFamily: _family, fontPackage: _package);
  static const IconData calendarDots =
      IconData(0xe7b4, fontFamily: _family, fontPackage: _package);
  static const IconData caretDown =
      IconData(0xe136, fontFamily: _family, fontPackage: _package);
  static const IconData caretLeft =
      IconData(0xe138, fontFamily: _family, fontPackage: _package);
  static const IconData caretRight =
      IconData(0xe13a, fontFamily: _family, fontPackage: _package);
  static const IconData chartLineUp =
      IconData(0xe156, fontFamily: _family, fontPackage: _package);
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
  static const IconData code =
      IconData(0xe1bc, fontFamily: _family, fontPackage: _package);
  static const IconData compass =
      IconData(0xe1c8, fontFamily: _family, fontPackage: _package);
  static const IconData crosshairSimple =
      IconData(0xe1d8, fontFamily: _family, fontPackage: _package);
  static const IconData desktopTower =
      IconData(0xe562, fontFamily: _family, fontPackage: _package);
  static const IconData eye =
      IconData(0xe220, fontFamily: _family, fontPackage: _package);
  static const IconData eyeSlash =
      IconData(0xe224, fontFamily: _family, fontPackage: _package);
  static const IconData fingerprint =
      IconData(0xe23e, fontFamily: _family, fontPackage: _package);
  static const IconData fire =
      IconData(0xe242, fontFamily: _family, fontPackage: _package);
  static const IconData flagPennant =
      IconData(0xecf0, fontFamily: _family, fontPackage: _package);
  static const IconData floppyDisk =
      IconData(0xe248, fontFamily: _family, fontPackage: _package);
  static const IconData gear =
      IconData(0xe270, fontFamily: _family, fontPackage: _package);
  static const IconData globeHemisphereEast =
      IconData(0xe28a, fontFamily: _family, fontPackage: _package);
  static const IconData info =
      IconData(0xe2ce, fontFamily: _family, fontPackage: _package);
  static const IconData key =
      IconData(0xe2d6, fontFamily: _family, fontPackage: _package);
  static const IconData lightning =
      IconData(0xe2de, fontFamily: _family, fontPackage: _package);
  static const IconData link =
      IconData(0xe2e2, fontFamily: _family, fontPackage: _package);
  static const IconData listBullets =
      IconData(0xe2f2, fontFamily: _family, fontPackage: _package);
  static const IconData listChecks =
      IconData(0xeadc, fontFamily: _family, fontPackage: _package);
  static const IconData listNumbers =
      IconData(0xe2f6, fontFamily: _family, fontPackage: _package);
  static const IconData lock =
      IconData(0xe2fa, fontFamily: _family, fontPackage: _package);
  static const IconData lockKeyOpen =
      IconData(0xe300, fontFamily: _family, fontPackage: _package);
  static const IconData magnifyingGlass =
      IconData(0xe30c, fontFamily: _family, fontPackage: _package);
  static const IconData mapPin =
      IconData(0xe316, fontFamily: _family, fontPackage: _package);
  static const IconData moon =
      IconData(0xe330, fontFamily: _family, fontPackage: _package);
  static const IconData moonStars =
      IconData(0xe58e, fontFamily: _family, fontPackage: _package);
  static const IconData mosque =
      IconData(0xecee, fontFamily: _family, fontPackage: _package);
  static const IconData notePencil =
      IconData(0xe34c, fontFamily: _family, fontPackage: _package);
  static const IconData palette =
      IconData(0xe6c8, fontFamily: _family, fontPackage: _package);
  static const IconData paperPlaneRight =
      IconData(0xe396, fontFamily: _family, fontPackage: _package);
  static const IconData pauseCircle =
      IconData(0xe3a0, fontFamily: _family, fontPackage: _package);
  static const IconData pencilSimple =
      IconData(0xe3b4, fontFamily: _family, fontPackage: _package);
  static const IconData playCircle =
      IconData(0xe3d2, fontFamily: _family, fontPackage: _package);
  static const IconData plugsConnected =
      IconData(0xeb5a, fontFamily: _family, fontPackage: _package);
  static const IconData plus =
      IconData(0xe3d4, fontFamily: _family, fontPackage: _package);
  static const IconData plusCircle =
      IconData(0xe3d6, fontFamily: _family, fontPackage: _package);
  static const IconData quotes =
      IconData(0xe660, fontFamily: _family, fontPackage: _package);
  static const IconData repeat =
      IconData(0xe3f6, fontFamily: _family, fontPackage: _package);
  static const IconData shieldCheck =
      IconData(0xe40c, fontFamily: _family, fontPackage: _package);
  static const IconData smiley =
      IconData(0xe436, fontFamily: _family, fontPackage: _package);
  static const IconData smileyMeh =
      IconData(0xe43a, fontFamily: _family, fontPackage: _package);
  static const IconData smileyNervous =
      IconData(0xe43c, fontFamily: _family, fontPackage: _package);
  static const IconData smileySad =
      IconData(0xe43e, fontFamily: _family, fontPackage: _package);
  static const IconData smileyWink =
      IconData(0xe666, fontFamily: _family, fontPackage: _package);
  static const IconData sortAscending =
      IconData(0xe444, fontFamily: _family, fontPackage: _package);
  static const IconData sparkle =
      IconData(0xe6a2, fontFamily: _family, fontPackage: _package);
  static const IconData stopCircle =
      IconData(0xe46e, fontFamily: _family, fontPackage: _package);
  static const IconData sun =
      IconData(0xe472, fontFamily: _family, fontPackage: _package);
  static const IconData sunDim =
      IconData(0xe474, fontFamily: _family, fontPackage: _package);
  static const IconData sunHorizon =
      IconData(0xe5b6, fontFamily: _family, fontPackage: _package);
  static const IconData swatches =
      IconData(0xe5b8, fontFamily: _family, fontPackage: _package);
  static const IconData tag =
      IconData(0xe478, fontFamily: _family, fontPackage: _package);
  static const IconData target =
      IconData(0xe47c, fontFamily: _family, fontPackage: _package);
  static const IconData textAlignLeft =
      IconData(0xe484, fontFamily: _family, fontPackage: _package);
  static const IconData textB =
      IconData(0xe5be, fontFamily: _family, fontPackage: _package);
  static const IconData textHOne =
      IconData(0xe6bc, fontFamily: _family, fontPackage: _package);
  static const IconData textItalic =
      IconData(0xe5c0, fontFamily: _family, fontPackage: _package);
  static const IconData timer =
      IconData(0xe492, fontFamily: _family, fontPackage: _package);
  static const IconData trash =
      IconData(0xe4a6, fontFamily: _family, fontPackage: _package);
  static const IconData trendUp =
      IconData(0xe4ae, fontFamily: _family, fontPackage: _package);
  static const IconData warningCircle =
      IconData(0xe4e2, fontFamily: _family, fontPackage: _package);
  static const IconData wifiSlash =
      IconData(0xe4f2, fontFamily: _family, fontPackage: _package);
  static const IconData x =
      IconData(0xe4f6, fontFamily: _family, fontPackage: _package);
  static const IconData xCircle =
      IconData(0xe4f8, fontFamily: _family, fontPackage: _package);
}
