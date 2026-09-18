import 'package:flutter/material.dart';

import '../../../models/task.dart';
import '../../../models/task_view.dart';
import '../../theme/app_theme.dart';
import '../../theme/prayer_palette.dart';
import '../../widgets/ph_light_icons.dart';

/// The three-way priority picker shared by the task and reminder sheets.
///
/// Lifted out of the task form sheet, where it was private, when reminders
/// grew a priority of their own: the two sheets sit behind the same screen and
/// set the same [TaskPriority], so a second copy would be two controls the
/// user has to learn as one.
class PrioritySelector extends StatelessWidget {
  const PrioritySelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final TaskPriority selected;
  final ValueChanged<TaskPriority> onChanged;

  @override
  Widget build(BuildContext context) {
    // High first: the order the list sorts in.
    const ordered = [TaskPriority.high, TaskPriority.medium, TaskPriority.low];

    return Row(
      children: [
        for (final priority in ordered) ...[
          Expanded(
            child: _PriorityChip(
              priority: priority,
              isSelected: priority == selected,
              onTap: () => onChanged(priority),
            ),
          ),
          if (priority != ordered.last) const SizedBox(width: 10),
        ],
      ],
    );
  }
}

class _PriorityChip extends StatelessWidget {
  const _PriorityChip({
    required this.priority,
    required this.isSelected,
    required this.onTap,
  });

  final TaskPriority priority;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = context.palette.priorityColor(priority);

    return Semantics(
      button: true,
      selected: isSelected,
      label: '${priority.label} priority',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: context.motion.fast,
          curve: AppMotion.spring,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected
                ? accent.withValues(alpha: 0.16)
                : context.palette.glassFill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? accent : context.palette.glassBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                PhLight.flagPennant,
                size: 13,
                color: isSelected ? accent : context.palette.textMuted,
              ),
              const SizedBox(width: 7),
              Text(
                priority.label,
                style: context.typography.ui(
                  size: 13,
                  weight: FontWeight.w600,
                  color: isSelected ? accent : context.palette.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
