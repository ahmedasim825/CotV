import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/daily_prayer_times.dart';
import '../../models/focus_session.dart';
import '../../providers/clock_providers.dart';
import '../../providers/focus_session_providers.dart';
import '../format/time_format.dart';
import '../theme/app_theme.dart';
import '../theme/prayer_palette.dart';
import '../widgets/ambient_background.dart';
import '../widgets/glass_shell.dart';
import '../widgets/glow_pill_button.dart';
import '../widgets/ph_light_icons.dart';
import '../widgets/prayer_icon.dart';

/// Full-screen quiet mode shown while a focus session runs.
///
/// Deliberately near-empty: one countdown and one way out. The point is to
/// remove things to look at, so anything not load-bearing stays off it.
class FocusSessionOverlay extends ConsumerWidget {
  const FocusSessionOverlay({super.key, required this.session});

  final FocusSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(nowTickerProvider).value ?? DateTime.now();
    final accent = PrayerPalette.of(session.prayer);
    final remaining = session.remainingAt(now);
    final isFinished = session.isFinishedAt(now);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AmbientBackground(
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: GlassShell(
                  outerRadius: 36,
                  padding: const EdgeInsets.fromLTRB(30, 36, 30, 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 76,
                        height: 76,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.16),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          iconForPrayer(session.prayer),
                          size: 32,
                          color: accent,
                        ),
                      ),
                      const SizedBox(height: 26),
                      Text(
                        isFinished
                            ? '${session.prayer.displayName} complete'
                            : '${session.prayer.displayName} focus',
                        style: AppTypography.ui(
                          size: 15,
                          color: AppPalette.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        isFinished ? 'Done' : formatCountdown(remaining),
                        style: AppTypography.display(size: 56, color: accent),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        isFinished
                            ? 'The window has closed.'
                            : 'Until ${formatClock(session.endsAt)}',
                        textAlign: TextAlign.center,
                        style: AppTypography.ui(
                          size: 13,
                          color: AppPalette.textMuted,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 22),
                      _SessionProgress(
                        progress: session.progressAt(now),
                        accent: accent,
                      ),
                      const SizedBox(height: 28),
                      GlowPillButton(
                        label: isFinished ? 'Close' : 'End session',
                        icon: isFinished ? PhLight.check : PhLight.pauseCircle,
                        expand: true,
                        filled: isFinished,
                        onPressed: () =>
                            ref.read(focusSessionProvider.notifier).end(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SessionProgress extends StatelessWidget {
  const _SessionProgress({required this.progress, required this.accent});

  final double progress;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Stack(
        children: [
          Container(height: 6, color: AppPalette.glassFill),
          LayoutBuilder(
            builder: (context, constraints) => AnimatedContainer(
              duration: AppMotion.base,
              curve: AppMotion.spring,
              height: 6,
              width: constraints.maxWidth * progress.clamp(0.0, 1.0),
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}
