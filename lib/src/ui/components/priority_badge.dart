import 'package:flutter/material.dart';

import '../../models/task.dart';
import '../../models/task_view.dart';
import '../theme/app_theme.dart';
import '../theme/prayer_palette.dart';
import '../widgets/ph_light_icons.dart';

/// A task's priority, rendered identically everywhere it appears — list
/// tile, timeline block, form sheet, detail sheet.
///
/// High priority fills its chip so it separates from the rest at a glance;
/// medium and low stay on the neutral glass fill and carry their color in
/// the icon and label only, which keeps a dense list from turning into a
/// wall of competing swatches.
class PriorityBadge extends StatelessWidget {
  const PriorityBadge({
    super.key,
    required this.priority,
    this.compact = false,
    this.filled,
  });

  final TaskPriority priority;

  /// Drops the label and shows only the flag glyph, for very tight rows.
  final bool compact;

  /// Overrides the default (fill only for [TaskPriority.high]).
  final bool? filled;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = palette.priorityColor(priority);
    final isFilled = filled ?? (priority == TaskPriority.high);

    return Semantics(
      label: '${priority.label} priority',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 8,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: isFilled
              ? color.withValues(alpha: 0.14)
              : palette.glassFill,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhLight.flagPennant, size: 11, color: color),
            if (!compact) ...[
              const SizedBox(width: 5),
              Text(
                priority.label,
                style: context.typography.ui(
                  size: 11,
                  color: color,
                  weight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
