import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// A small circular icon button for a sheet's title row.
///
/// Both task and reminder sheets put their destructive action in the same
/// spot, so it is one control rather than two copies that could drift.
class SheetIconAction extends StatelessWidget {
  const SheetIconAction({
    super.key,
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
    this.tint,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String semanticLabel;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = tint ?? palette.textSecondary;

    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 17, color: color),
        ),
      ),
    );
  }
}
