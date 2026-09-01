import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'glass_shell.dart';
import 'ph_light_icons.dart';

/// The "Fluid Island" header: a compact frosted pill detached from the top
/// edge rather than a flat, edge-to-edge Material app bar. Sits inline in
/// the scroll content (not fixed) since this is a single-screen app.
class FloatingHeader extends StatelessWidget {
  const FloatingHeader({super.key, required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return GlassShell(
      outerRadius: 999,
      shellPadding: 5,
      blurBackground: true,
      padding: const EdgeInsets.fromLTRB(18, 10, 10, 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(color: AppPalette.amberBright, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Text('Prayer Lockout', style: AppTypography.ui(size: 14, weight: FontWeight.w600)),
          const SizedBox(width: 24),
          _IconChip(icon: PhLight.arrowClockwise, onTap: onRefresh),
        ],
      ),
    );
  }
}

class _IconChip extends StatelessWidget {
  const _IconChip({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: AppPalette.glassBorder, shape: BoxShape.circle),
        child: Icon(icon, size: 16, color: AppPalette.textPrimary),
      ),
    );
  }
}
