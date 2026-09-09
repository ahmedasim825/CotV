import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/daily_prayer_times.dart';
import '../../../providers/prayer_window_providers.dart';
import '../../../providers/weather_providers.dart';
import '../../format/time_format.dart';
import '../../theme/app_theme.dart';

/// "Welcome, Ahmed" over the next prayer and the current temperature.
///
/// The greeting is painted through a radial shader rather than a flat colour:
/// white at the core, falling to the accent by half the radius. The centre
/// sits right of middle so the purple lands on "Welcome," and the white on
/// the name, which is how the design reads.
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
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => RadialGradient(
            center: const Alignment(0.6, 0.0),
            radius: 0.9,
            colors: [palette.textPrimary, palette.accent],
            stops: const [0.0, 0.5],
          ).createShader(bounds),
          child: Text(
            'Welcome, $name',
            style: context.typography.display(
              size: 42,
              weight: FontWeight.w700,
              letterSpacing: -1.4,
              // srcIn discards the colour but uses the alpha channel; an opaque
              // colour is needed so the shader shows through completely.
              color: palette.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              '${next.prayer.displayName} is at ${formatClock(next.time)}',
              style: context.typography.ui(
                size: 17,
                weight: FontWeight.w600,
                color: palette.textPrimary,
              ),
            ),
            if (weather != null) ...[
              const SizedBox(width: 16),
              Icon(weather.condition.icon, size: 22, color: palette.textSecondary),
              const SizedBox(width: 7),
              Text(
                weather.label,
                style: context.typography.ui(
                  size: 17,
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
