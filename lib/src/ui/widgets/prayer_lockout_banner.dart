import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/daily_prayer_times.dart';
import '../../providers/clock_providers.dart';
import '../../providers/focus_session_providers.dart';
import '../../providers/prayer_window_providers.dart';
import '../format/time_format.dart';
import '../theme/app_theme.dart';
import '../theme/prayer_palette.dart';
import 'ph_light_icons.dart';
import 'prayer_icon.dart';

/// The live prayer status card.
///
/// Two states, driven by [prayerNowStateProvider]:
///   * **Locked out** — a prayer window is underway. The card takes the
///     prayer's accent, shows a progress bar and counts down to the end of
///     the window.
///   * **Free** — counts down to the next Adhan in a quieter treatment, so
///     the loud state stays meaningful.
///
/// The countdown digits come from [nowTickerProvider] inside
/// [_CountdownText] rather than from this widget, so the per-second rebuild
/// is confined to a single [Text] instead of the whole card.
class PrayerLockoutBanner extends ConsumerWidget {
  const PrayerLockoutBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prayerState = ref.watch(prayerNowStateProvider);
    final lockout = prayerState.activeLockout;
    final isLockedOut = lockout != null;

    final prayer = lockout?.prayer ?? prayerState.nextAdhan.prayer;
    final accent = context.palette.prayerHue(prayer);
    final target = lockout?.end ?? prayerState.nextAdhan.time;

    return AnimatedContainer(
      duration: context.motion.base,
      curve: AppMotion.spring,
      padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
      decoration: BoxDecoration(
        color: isLockedOut
            ? Color.alphaBlend(accent.withValues(alpha: 0.18), context.palette.surface)
            : context.palette.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isLockedOut ? accent.withValues(alpha: 0.7) : context.palette.hairline,
        ),
        boxShadow: isLockedOut
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.22),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ]
            : [
                BoxShadow(
                  color: context.palette.shadow,
                  blurRadius: 20,
                  offset: Offset(0, 8),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isLockedOut ? 0.28 : 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(iconForPrayer(prayer), size: 19, color: accent),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isLockedOut
                          ? '${prayer.displayName} · Prayer Lockout'
                          : 'Next: ${prayer.displayName}',
                      style: context.typography.ui(size: 14, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isLockedOut
                          ? 'Until ${formatClock(lockout.end)}'
                          : 'Adhan at ${formatClock(prayerState.nextAdhan.time)}',
                      style: context.typography.ui(
                        size: 12,
                        color: context.palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _CountdownText(target: target, accent: accent, emphasised: isLockedOut),
            ],
          ),
          if (isLockedOut) ...[
            const SizedBox(height: 14),
            _LockoutProgressBar(
              progress: prayerState.lockoutProgress ?? 0,
              accent: accent,
            ),
          ],
          const SizedBox(height: 14),
          _QuickActions(isLockedOut: isLockedOut, accent: accent),
        ],
      ),
    );
  }
}

/// The live digits. Watches the one-second ticker so only this subtree
/// rebuilds each second.
class _CountdownText extends ConsumerWidget {
  const _CountdownText({
    required this.target,
    required this.accent,
    required this.emphasised,
  });

  final DateTime target;
  final Color accent;
  final bool emphasised;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(nowTickerProvider).value ?? DateTime.now();
    final remaining = target.difference(now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          formatCountdown(remaining),
          style: context.typography.display(
            size: emphasised ? 26 : 22,
            weight: FontWeight.w500,
            color: emphasised ? accent : context.palette.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          emphasised ? 'remaining' : 'to adhan',
          style: context.typography.eyebrow(color: context.palette.textMuted),
        ),
      ],
    );
  }
}

class _LockoutProgressBar extends StatelessWidget {
  const _LockoutProgressBar({required this.progress, required this.accent});

  final double progress;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Stack(
        children: [
          Container(height: 5, color: context.palette.glassFill),
          LayoutBuilder(
            builder: (context, constraints) => AnimatedContainer(
              duration: context.motion.base,
              curve: AppMotion.spring,
              height: 5,
              width: constraints.maxWidth * progress.clamp(0.0, 1.0),
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// Starts or ends the in-app focus session.
class _QuickActions extends ConsumerWidget {
  const _QuickActions({required this.isLockedOut, required this.accent});

  final bool isLockedOut;
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFocusing = ref.watch(isFocusSessionActiveProvider);

    if (isFocusing) {
      return _ActionButton(
        icon: PhLight.pauseCircle,
        label: 'End focus session',
        accent: context.palette.textSecondary,
        filled: false,
        onTap: () => ref.read(focusSessionProvider.notifier).end(),
      );
    }

    return _ActionButton(
      icon: PhLight.playCircle,
      label: isLockedOut ? 'Start prayer focus' : 'Focus until adhan',
      accent: accent,
      filled: isLockedOut,
      onTap: () => ref
          .read(focusSessionProvider.notifier)
          .startFromCurrentPrayerState(ref.read(prayerNowStateProvider)),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.accent,
    required this.filled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = filled ? context.palette.onAccent : accent;

    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: filled ? accent : accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: filled ? accent : accent.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: foreground),
                const SizedBox(width: 9),
                Text(
                  label,
                  style: context.typography.ui(
                    size: 13,
                    weight: FontWeight.w700,
                    color: foreground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
