import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/daily_prayer_times.dart';
import '../../../providers/prayer_window_providers.dart';
import '../../../providers/weather_providers.dart';
import '../../format/time_format.dart';
import '../../theme/app_theme.dart';

/// "Welcome, Ahmed" over the next prayer and the current temperature.
///
/// The greeting is flat white at 70%. It used to ramp from violet to white
/// through a [ShaderMask]; the redesign dropped the gradient, so it is now
/// dimmer than the prayer line beneath it rather than more colourful than it.
class WelcomeHeader extends ConsumerWidget {
  const WelcomeHeader({super.key, this.name = 'Ahmed'});

  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final next = ref.watch(prayerNowStateProvider).nextAdhan;
    final weather = ref.watch(weatherProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Welcome, $name',
          style: context.typography.display(
            size: 42,
            weight: FontWeight.w700,
            letterSpacing: -1.4,
            // White at 70% — `textSecondary` is exactly that.
            color: palette.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            // Flexible, not a bare Text: the prayer name and the user's text
            // scale are both variable, and on the compact layout this Row is
            // the narrowest thing on the screen (as little as ~353pt wide).
            // Without give here, a long prayer name at a larger accessibility
            // text scale overflows the Row. The prayer line yields first —
            // it ellipsises rather than the ~60pt weather chip, since a
            // truncated temperature reads worse than a truncated prayer name.
            Flexible(
              child: Text(
                '${next.prayer.displayName} is at ${formatClock(next.time)}',
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: context.typography.ui(
                  size: 15,
                  weight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
            ),
            if (weather != null) ...[
              const SizedBox(width: 16),
              Icon(weather.condition.icon, size: 20, color: palette.textSecondary),
              const SizedBox(width: 7),
              Text(
                weather.label,
                style: context.typography.ui(
                  size: 15,
                  weight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
