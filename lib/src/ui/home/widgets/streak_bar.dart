import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/ph_light_icons.dart';

/// One metric in the strip. Mock only.
class _Metric {
  const _Metric(this.icon, this.value, this.label);

  final IconData icon;
  final String value;
  final String label;
}

const List<_Metric> _mockMetrics = [
  _Metric(PhLight.fire, '12', 'day streak'),
  _Metric(PhLight.timer, '6h', 'studied'),
  _Metric(PhLight.forkKnife, '1417', 'kcal'),
  _Metric(PhLight.listChecks, '3', 'tasks left'),
  _Metric(PhLight.drop, '1.6L', 'water'),
];

/// The compact metrics strip under the header.
///
/// Scrolls horizontally rather than wrapping or shrinking: five cells across
/// a 393pt phone would leave ~70pt each, which is not enough for a value and
/// a label without ellipsising both.
class StreakBar extends StatelessWidget {
  const StreakBar({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      decoration: BoxDecoration(
        color: palette.glassFill,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.hairline),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        child: Row(
          children: [
            for (var i = 0; i < _mockMetrics.length; i++) ...[
              _MetricCell(metric: _mockMetrics[i]),
              if (i < _mockMetrics.length - 1)
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
