import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'glass_shell.dart';
import 'ph_light_icons.dart';

enum StatusTone { success, error }

/// A glass-tinted feedback row replacing the flat Material success/error
/// [Card] — used to report the outcome of calendar sync / notification
/// scheduling without breaking the app's visual language.
class StatusCard extends StatelessWidget {
  const StatusCard({super.key, required this.message, required this.tone});

  final String message;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final color = tone == StatusTone.success ? AppPalette.success : AppPalette.danger;
    final icon = tone == StatusTone.success ? PhLight.checkCircle : PhLight.warningCircle;

    return GlassShell(
      outerRadius: 22,
      shellPadding: 4,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      tint: color.withValues(alpha: 0.08),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: AppTypography.ui(size: 13, color: AppPalette.textSecondary, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
