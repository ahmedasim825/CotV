import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The microscopic tracked-out label that precedes every section heading
/// and highlights the hero card's status.
class EyebrowPill extends StatelessWidget {
  const EyebrowPill({super.key, required this.label, this.color});

  final String label;

  /// Defaults to the active theme's accent. Left nullable rather than
  /// defaulted to a constant so the pill re-tints when the theme changes.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? context.palette.accent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: context.typography.eyebrow(color: tint)),
    );
  }
}
