import 'package:flutter/material.dart';

import '../../../models/task.dart';
import '../../components/components.dart';
import '../../format/time_format.dart';
import '../../theme/app_theme.dart';
import '../../theme/prayer_palette.dart';
import '../../widgets/ph_light_icons.dart';

/// A single task row: an animated completion control, the task's text, and
/// its priority and due-time metadata.
///
/// The completion animation is driven locally so the checkbox reacts on the
/// same frame as the tap, while the Hive write travels through the
/// repository and comes back as new state. Local state is kept in sync with
/// [task] in [didUpdateWidget] so an external change (or a failed write)
/// can't leave the control lying about what is stored.
class TaskTile extends StatefulWidget {
  const TaskTile({
    super.key,
    required this.task,
    required this.now,
    required this.onToggleCompleted,
    required this.onTap,
  });

  final Task task;
  final DateTime now;
  final VoidCallback onToggleCompleted;
  final VoidCallback onTap;

  @override
  State<TaskTile> createState() => _TaskTileState();
}

class _TaskTileState extends State<TaskTile> {
  late bool _isCompleted = widget.task.isCompleted;
  bool _isPressed = false;

  @override
  void didUpdateWidget(TaskTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.task.isCompleted != oldWidget.task.isCompleted) {
      setState(() => _isCompleted = widget.task.isCompleted);
    }
  }

  void _handleToggle() {
    setState(() => _isCompleted = !_isCompleted);
    widget.onToggleCompleted();
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final accent = context.palette.priorityColor(task.priority);
    final isOverdue = !_isCompleted &&
        task.dueDate != null &&
        task.dueDate!.isBefore(widget.now);

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapCancel: () => setState(() => _isPressed = false),
      onTapUp: (_) => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.985 : 1,
        duration: AppMotion.fast,
        curve: AppMotion.spring,
        child: AnimatedOpacity(
          // Completed tasks recede rather than disappearing, so undoing a
          // mis-tap doesn't require hunting for the row.
          opacity: _isCompleted ? 0.55 : 1,
          duration: AppMotion.fast,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
            decoration: BoxDecoration(
              color: context.palette.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: context.palette.hairline),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CompletionControl(
                  isCompleted: _isCompleted,
                  accent: accent,
                  onTap: _handleToggle,
                  semanticLabel: task.title,
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedDefaultTextStyle(
                        duration: AppMotion.fast,
                        curve: AppMotion.spring,
                        style: context.typography.ui(
                          size: 14.5,
                          weight: FontWeight.w600,
                          height: 1.3,
                          color: _isCompleted
                              ? context.palette.textMuted
                              : context.palette.textPrimary,
                        ).copyWith(
                          decoration: _isCompleted
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                          decorationColor: context.palette.textMuted,
                        ),
                        child: Text(
                          task.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (task.description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          task.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.typography.ui(
                            size: 12.5,
                            color: context.palette.textMuted,
                            height: 1.4,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      _TaskMetaRow(
                        task: task,
                        now: widget.now,
                        accent: accent,
                        isOverdue: isOverdue,
                      ),
                    ],
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

/// The circular check control. Expands its hit area to 44pt without growing
/// the visible circle.
class _CompletionControl extends StatelessWidget {
  const _CompletionControl({
    required this.isCompleted,
    required this.accent,
    required this.onTap,
    required this.semanticLabel,
  });

  final bool isCompleted;
  final Color accent;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: isCompleted,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 30,
          height: 30,
          child: Center(
            child: AnimatedContainer(
              duration: AppMotion.fast,
              curve: AppMotion.spring,
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isCompleted ? accent : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isCompleted ? accent : context.palette.glassBorder,
                  width: 1.5,
                ),
              ),
              child: AnimatedScale(
                scale: isCompleted ? 1 : 0.4,
                duration: AppMotion.fast,
                curve: AppMotion.spring,
                child: AnimatedOpacity(
                  opacity: isCompleted ? 1 : 0,
                  duration: AppMotion.fast,
                  child: Icon(
                    PhLight.check,
                    size: 14,
                    color: context.palette.onAccent,
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

/// Priority chip, category and due time.
class _TaskMetaRow extends StatelessWidget {
  const _TaskMetaRow({
    required this.task,
    required this.now,
    required this.accent,
    required this.isOverdue,
  });

  final Task task;
  final DateTime now;
  final Color accent;
  final bool isOverdue;

  @override
  Widget build(BuildContext context) {
    final dueDate = task.dueDate;

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        PriorityBadge(priority: task.priority),
        if (task.category.isNotEmpty)
          _MetaChip(
            icon: PhLight.tag,
            label: task.category,
            color: context.palette.textMuted,
          ),
        if (dueDate != null)
          _MetaChip(
            icon: PhLight.clock,
            label: isOverdue
                ? 'Overdue · ${formatDueLabel(dueDate, now)}'
                : formatDueLabel(dueDate, now),
            color: isOverdue ? context.palette.danger : context.palette.textMuted,
            filled: isOverdue,
          ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.color,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.14) : context.palette.glassFill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: context.typography.ui(size: 11, color: color, weight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
