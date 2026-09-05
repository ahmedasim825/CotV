import 'dart:io';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/ph_light_icons.dart';

/// A food photo with a plate glyph behind it.
///
/// Every food image in this feature goes through here rather than a bare
/// [Image.network]: Nutritionix photo URLs 404 often enough that an
/// unguarded one shows Flutter's red error box in a release build, and a
/// common food frequently has no photo at all.
class FoodThumbnail extends StatelessWidget {
  const FoodThumbnail({
    super.key,
    this.url,
    this.filePath,
    this.size = 52,
    this.radius = 14,
    this.icon = PhLight.bowlFood,
  });

  /// A remote image. Ignored when [filePath] is set.
  final String? url;

  /// A file on this device — a recipe cover chosen with the image picker.
  final String? filePath;

  /// Square side. A null [size] fills the space it is given, which is how
  /// the detail screen's hero uses it.
  final double? size;

  final double radius;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: _image(context),
      ),
    );
  }

  Widget _image(BuildContext context) {
    final path = filePath;
    if (path != null && path.isNotEmpty) {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (context, _, _) => _Placeholder(icon: icon),
      );
    }

    final source = url;
    if (source == null || source.isEmpty) return _Placeholder(icon: icon);

    return Image.network(
      source,
      fit: BoxFit.cover,
      errorBuilder: (context, _, _) => _Placeholder(icon: icon),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return _Placeholder(icon: icon, showSpinner: true);
      },
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.icon, this.showSpinner = false});

  final IconData icon;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return ColoredBox(
      color: palette.glassFill,
      child: Center(
        child: showSpinner
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: palette.textMuted,
                ),
              )
            : Icon(icon, size: 20, color: palette.textMuted),
      ),
    );
  }
}
