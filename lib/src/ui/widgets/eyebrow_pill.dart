import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The microscopic tracked-out label that precedes every section heading
/// and highlights the hero card's status.
class EyebrowPill extends StatelessWidget {
  const EyebrowPill({super.key, required this.label, this.color = AppPalette.amber});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: AppTypography.eyebrow(color: color)),
    );
  }
}
