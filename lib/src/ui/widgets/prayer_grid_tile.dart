import 'package:flutter/material.dart';

import '../../models/daily_prayer_times.dart';
import '../theme/app_theme.dart';
import 'glass_shell.dart';
import 'prayer_icon.dart';

/// A compact bento cell for a single prayer — used for every prayer other
/// than the hero (next) one.
class PrayerGridTile extends StatelessWidget {
  const PrayerGridTile({super.key, required this.prayer, required this.time, this.isPast = false});

  final PrayerLabel prayer;
  final DateTime time;
  final bool isPast;

  @override
  Widget build(BuildContext context) {
    return GlassShell(
      outerRadius: 26,
      shellPadding: 4,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.palette.glassBorder,
              shape: BoxShape.circle,
            ),
            child: Icon(
              iconForPrayer(prayer),
              size: 16,
              color: isPast ? context.palette.textMuted : context.palette.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            prayer.displayName,
            style: context.typography.ui(size: 12.5, color: context.palette.textMuted, weight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            _formatTime(time),
            style: context.typography.display(
              size: 24,
              weight: FontWeight.w500,
              color: isPast ? context.palette.textMuted : context.palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime t) {
    final hour = t.hour.toString().padLeft(2, '0');
    final minute = t.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
