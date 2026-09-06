import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/daily_prayer_times.dart';
import '../../../providers/prayer_window_providers.dart';
import '../../format/time_format.dart';
import '../../theme/app_theme.dart';
import 'milo_orb.dart';

/// The greeting the current hour calls for.
String _greetingFor(int hour) {
  if (hour < 5) return 'Still up';
  if (hour < 12) return 'Good Morning';
  if (hour < 17) return 'Good Afternoon';
  if (hour < 21) return 'Good Evening';
  return 'Good Night';
}

/// The dashboard's opening block: Milo, a greeting, and what's next.
///
/// The name is hardcoded for now — the stored user settings carry no
/// display-name field yet, and adding one belongs with the settings work
/// rather than here.
class DashboardHeader extends ConsumerWidget {
  const DashboardHeader({super.key, this.orbDiameter = 128});

  final double orbDiameter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final next = ref.watch(prayerNowStateProvider).nextAdhan;

    return Column(
      children: [
        MiloOrb(diameter: orbDiameter),
        const SizedBox(height: 8),
        Text(
          '${_greetingFor(DateTime.now().hour)}, Ahmed',
          textAlign: TextAlign.center,
          style: context.typography.display(size: 30),
        ),
        const SizedBox(height: 10),
        Text(
          'Next prayer is ${next.prayer.displayName} '
          'at ${formatClock(next.time)}',
          textAlign: TextAlign.center,
          style: context.typography.ui(
            size: 13.5,
            color: palette.textSecondary,
          ),
        ),
      ],
    );
  }
}
