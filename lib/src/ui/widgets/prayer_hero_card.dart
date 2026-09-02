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
      tint: context.palette.heroTint,
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
                decoration: BoxDecoration(
                  color: context.palette.accentSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(iconForPrayer(prayer), size: 20, color: context.palette.accentBright),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(prayer.displayName, style: context.typography.ui(size: 16, color: context.palette.textSecondary)),
          const SizedBox(height: 4),
          Text(_formatTime(time), style: context.typography.display(size: 60)),
          const SizedBox(height: 14),
          Text(
            _formatCountdown(remaining),
            style: context.typography.ui(size: 13.5, color: context.palette.accent, weight: FontWeight.w600),
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
