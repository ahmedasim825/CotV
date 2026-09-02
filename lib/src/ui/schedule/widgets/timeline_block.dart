import 'package:flutter/material.dart';

import '../../../models/daily_prayer_times.dart';
import '../../../models/task_view.dart';
import '../../../models/timeline_entry.dart';
import '../../format/time_format.dart';
import '../../theme/app_theme.dart';
import '../../theme/prayer_palette.dart';
import '../../widgets/ph_light_icons.dart';
import '../../widgets/prayer_icon.dart';

/// A single block drawn on the timeline.
///
/// Dispatches on the sealed [TimelineEntry] hierarchy, so each kind gets the
/// affordances it should have and no others: prayer lockouts are visibly
/// inert, schedule items and tasks are tappable.
class TimelineBlock extends StatelessWidget {
  const TimelineBlock({
    super.key,
    required this.entry,
    required this.height,
    this.onTap,
    this.isCurrent = false,
  });

  final TimelineEntry entry;
  final double height;
  final VoidCallback? onTap;

  /// True when the current-time indicator falls inside this block.
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final block = switch (entry) {
      PrayerLockoutEntry(:final window) => _BlockSurface(
          height: height,
          accent: context.palette.prayerHue(window.prayer),
          fill: context.palette.prayerLockoutFill(window.prayer),
          icon: iconForPrayer(window.prayer),
          title: '${window.prayer.displayName} · Prayer Lockout',
          subtitle: formatTimeRange(window.start, window.end),
          trailing: const _ReadOnlyLockBadge(),
          isCurrent: isCurrent,
        ),
      ScheduleItemEntry(:final item) => _BlockSurface(
          height: height,
          accent: item.isPrayerBlocked ? context.palette.accent : context.palette.textSecondary,
          fill: context.palette.surface,
          icon: item.isPrayerBlocked ? PhLight.mosque : PhLight.calendarBlank,
          title: item.title,
          subtitle: formatTimeRange(item.startTime, item.endTime),
          isCurrent: isCurrent,
        ),
      TaskEntry(:final task, :final dueDate) => _BlockSurface(
          height: height,
          accent: context.palette.priorityColor(task.priority),
          fill: context.palette.surface,
          icon: PhLight.listChecks,
          title: task.title,
          subtitle: 'Due ${formatClock(dueDate)} · ${task.priority.label}',
          isCurrent: isCurrent,
        ),
    };

    if (entry.isReadOnly || onTap == null) {
      return Semantics(
        label: '${entry.title}, ${formatTimeRange(entry.start, entry.end)}',
        readOnly: entry.isReadOnly,
        child: block,
      );
    }

    return Semantics(
      button: true,
      label: '${entry.title}, ${formatTimeRange(entry.start, entry.end)}',
      child: GestureDetector(onTap: onTap, child: block),
    );
  }
}

class _BlockSurface extends StatelessWidget {
  const _BlockSurface({
    required this.height,
    required this.accent,
    required this.fill,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isCurrent,
    this.trailing,
  });

  final double height;
  final Color accent;
  final Color fill;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isCurrent;
  final Widget? trailing;

  /// Below this height there is only room for the title line.
  static const double _twoLineThreshold = 58;

  @override
  Widget build(BuildContext context) {
    final isCompact = height < _twoLineThreshold;

    return AnimatedContainer(
      duration: context.motion.fast,
      curve: AppMotion.spring,
      height: height,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: isCompact ? 6 : 10),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCurrent ? accent.withValues(alpha: 0.85) : context.palette.hairline,
        ),
        boxShadow: [
          BoxShadow(color: context.palette.shadow, blurRadius: 14, offset: Offset(0, 6)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The accent spine: a block's kind is readable at a glance even
          // when it is too short to show its subtitle.
          Container(
            width: 3,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 13, color: accent),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.typography.ui(size: 13, weight: FontWeight.w600),
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 8),
                      trailing!,
                    ],
                  ],
                ),
                if (!isCompact) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.typography.ui(size: 11.5, color: context.palette.textMuted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Marks a block as derived, non-editable state.
class _ReadOnlyLockBadge extends StatelessWidget {
  const _ReadOnlyLockBadge();

  @override
  Widget build(BuildContext context) {
    return Icon(PhLight.lock, size: 12, color: context.palette.textMuted);
  }
}
