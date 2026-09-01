import 'package:flutter/material.dart';

import '../../models/daily_prayer_times.dart';
import '../theme/app_theme.dart';
import 'eyebrow_pill.dart';
import 'glass_shell.dart';
import 'prayer_icon.dart';

/// The bento grid's oversized hero cell — the next upcoming prayer, shown
/// with a large editorial-serif time and a live countdown, set apart from
/// the smaller grid tiles for the rest of the day.
class PrayerHeroCard extends StatelessWidget {
  const PrayerHeroCard({
    super.key,
    required this.prayer,
    required this.time,
    required this.now,
    required this.isTomorrow,
  });

  final PrayerLabel prayer;
  final DateTime time;
  final DateTime now;
  final bool isTomorrow;

  @override
  Widget build(BuildContext context) {
    final remaining = time.difference(now);
    return GlassShell(
      outerRadius: 36,
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 28),
      tint: const Color(0xFF171119),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              EyebrowPill(
                label: isTomorrow ? 'NEXT · TOMORROW' : 'NEXT PRAYER',
              ),
              const Spacer(),
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Color(0x1FD8A657),
                  shape: BoxShape.circle,
                ),
                child: Icon(iconForPrayer(prayer), size: 20, color: AppPalette.amberBright),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(prayer.displayName, style: AppTypography.ui(size: 16, color: AppPalette.textSecondary)),
          const SizedBox(height: 4),
          Text(_formatTime(time), style: AppTypography.display(size: 60)),
          const SizedBox(height: 14),
          Text(
            _formatCountdown(remaining),
            style: AppTypography.ui(size: 13.5, color: AppPalette.amber, weight: FontWeight.w600),
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

  String _formatCountdown(Duration remaining) {
    if (remaining.isNegative) return 'Underway';
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    if (hours > 0) return 'in ${hours}h ${minutes}m';
    return 'in ${minutes}m';
  }
}
