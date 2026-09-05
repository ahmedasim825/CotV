import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/daily_prayer_times.dart';
import '../../../providers/clock_providers.dart';
import '../../../providers/prayer_window_providers.dart';
import '../../format/time_format.dart';
import '../../theme/app_theme.dart';
import '../../widgets/eyebrow_pill.dart';
import '../../widgets/glass_shell.dart';
import '../../widgets/ph_light_icons.dart';
import '../../widgets/prayer_icon.dart';

/// The dashboard's prayer cell: which prayer is next, at what time, and how
/// long is left.
///
/// This is the one card on the dashboard reading live data rather than mock
/// values. It costs nothing to do so — [prayerNowStateProvider] is local
/// arithmetic over the `adhan` package, with no network and no storage
/// behind it — and a wrong prayer time is the kind of mock that would be
/// actively misleading to look at.
class NextPrayerCard extends ConsumerWidget {
  const NextPrayerCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final next = ref.watch(prayerNowStateProvider).nextAdhan;
    // The minute-resolution state above is enough to know *which* prayer is
    // next; the digits themselves come off the second ticker so the
    // countdown stays live.
    final now = ref.watch(nowTickerProvider).value ?? DateTime.now();
    final remaining = next.time.difference(now);

    return GlassShell(
      outerRadius: 30,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      tint: palette.heroTint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const EyebrowPill(label: 'NEXT PRAYER'),
              const Spacer(),
              _MosqueMark(color: palette.accentBright),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Icon(
                iconForPrayer(next.prayer),
                size: 22,
                color: palette.accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  next.prayer.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.typography.ui(
                    size: 17,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                formatClock(next.time),
                style: context.typography.display(size: 40),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            remaining.isNegative
                ? 'Adhan has passed'
                : 'in ${formatCountdown(remaining)}',
            style: context.typography.ui(
              size: 13.5,
              color: palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// The mosque mark in the card's corner.
///
/// A tinted plate behind the glyph rather than bare line art, so it holds
/// its weight on Titanium and Monochrome where the accent barely differs
/// from the surface it sits on.
class _MosqueMark extends StatelessWidget {
  const _MosqueMark({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: 0.24),
            color.withValues(alpha: 0.06),
          ],
        ),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Icon(PhLight.mosque, size: 22, color: color),
    );
  }
}
