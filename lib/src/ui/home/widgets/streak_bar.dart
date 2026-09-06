import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/habit.dart';
import '../../../models/habit_view.dart';
import '../../../models/study_view.dart';
import '../../../providers/clock_providers.dart';
import '../../../providers/habit_providers.dart';
import '../../../providers/nutrition_providers.dart';
import '../../../providers/study_providers.dart';
import '../../../providers/task_view_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ph_light_icons.dart';

/// One metric in the strip.
class _Metric {
  const _Metric(this.icon, this.value, this.label);

  final IconData icon;
  final String value;
  final String label;
}

/// The compact metrics strip under the header.
///
/// Four cells, each behind a provider. There was a fifth reading `1.6L
/// water`, which was dropped rather than wired: nothing in the app records
/// water, so the only way to keep the cell was to keep inventing the number.
///
/// Scrolls horizontally rather than wrapping or shrinking: four cells across
/// a 393pt phone leave ~90pt each, which is enough for a value and a label
/// only while none of them grows — `2h 30m` and a four-digit calorie count
/// together already overflow it.
class StreakBar extends ConsumerWidget {
  const StreakBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final now = ref.watch(currentMinuteProvider);

    final habits = ref.watch(habitListProvider).value ?? const <Habit>[];
    final streak = summarizeHabits(habits, now).bestStreak;
    final studied = ref.watch(studySummaryProvider).todayMinutes;
    final calories = ref.watch(dailyNutritionProvider).totals.calories.round();
    final tasksLeft = (ref.watch(todayFocusTasksProvider).value ?? const [])
        .where((task) => !task.isCompleted)
        .length;

    final container = BoxDecoration(
      color: palette.glassFill,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: palette.hairline),
    );

    // Four zeros say less than one sentence does, and read as broken rather
    // than as a day that has not started yet.
    if (streak == 0 && studied == 0 && calories == 0 && tasksLeft == 0) {
      return Container(
        width: double.infinity,
        decoration: container,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Text(
          'Nothing tracked yet today',
          textAlign: TextAlign.center,
          style: context.typography.ui(size: 13, color: palette.textMuted),
        ),
      );
    }

    final metrics = [
      _Metric(PhLight.fire, '$streak', 'day streak'),
      _Metric(PhLight.timer, formatStudyMinutes(studied), 'studied'),
      _Metric(PhLight.forkKnife, '$calories', 'kcal'),
      _Metric(PhLight.listChecks, '$tasksLeft', 'tasks left'),
    ];

    return Container(
      decoration: container,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        child: Row(
          children: [
            for (var i = 0; i < metrics.length; i++) ...[
              _MetricCell(metric: metrics[i]),
              if (i < metrics.length - 1)
                Container(
                  width: 1,
                  height: 26,
                  color: palette.hairline,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({required this.metric});

  final _Metric metric;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Semantics(
      label: '${metric.value} ${metric.label}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(metric.icon, size: 14, color: palette.accent),
                const SizedBox(width: 6),
                Text(
                  metric.value,
                  style: context.typography.ui(
                    size: 15,
                    weight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              metric.label,
              style: context.typography.ui(
                size: 10.5,
                color: palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
