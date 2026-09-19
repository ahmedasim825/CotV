import 'package:flutter/material.dart';

import '../../../models/task.dart';
import '../../../models/task_view.dart';
import '../../theme/app_theme.dart';
import '../../theme/prayer_palette.dart';
import '../../widgets/ph_light_icons.dart';

/// One row inside a bento section — a task or a reminder.
///
/// Both kinds render through this: the tasks and reminders segments are the
/// same list of the same shape, and the only difference the design draws is
/// the due line, which only reminders carry.
///
/// Much leaner than the tile it replaces. No description, no category chip,
/// no clock chip, no chevron: the row is a title, a state and a priority, and
/// everything else lives in the sheet a tap opens.
///
/// The completion animation is driven locally so the checkbox reacts on the
/// same frame as the tap, while the write travels through the repository and
/// comes back as new state. Local state is kept in sync with [isCompleted] in
/// [didUpdateWidget] so an external change — or a failed write — cannot leave
/// the control lying about what is stored.
class CheckableRow extends StatefulWidget {
  const CheckableRow({
    super.key,
    required this.title,
    required this.isCompleted,
    required this.priority,
    required this.onToggle,
    required this.onTap,
    this.subjectColor,
    this.dueLine,
    this.dueOverdue = false,
  });

  final String title;
  final bool isCompleted;
  final TaskPriority priority;
  final VoidCallback onToggle;
  final VoidCallback onTap;

  /// The swatch of the subject this task is filed under, or null for a task
  /// that is not study work and for every reminder.
  final Color? subjectColor;

  /// The line under the title. Reminders always have one; tasks never do.
  final String? dueLine;

  final bool dueOverdue;

  @override
  State<CheckableRow> createState() => _CheckableRowState();
}

class _CheckableRowState extends State<CheckableRow> {
  late bool _isCompleted = widget.isCompleted;

  @override
  void didUpdateWidget(CheckableRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isCompleted != oldWidget.isCompleted) {
      setState(() => _isCompleted = widget.isCompleted);
    }
  }

  void _handleToggle() {
    setState(() => _isCompleted = !_isCompleted);
    widget.onToggle();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final dueLine = widget.dueLine;

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        // The card's horizontal inset lives here rather than on the card, so
        // that a swipe panel behind this row reaches the card's inner edge.
        // See the note on [BentoSection].
        padding: const EdgeInsets.fromLTRB(12, 6, 14, 6),
        child: Row(
          // Centred, not top-aligned. A one-line title in a row whose tallest
          // child is the 30pt completion box sat visibly above that box's
          // middle; a two-line one still centres against it, which is what the
          // design draws.
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _CompletionBox(
              isCompleted: _isCompleted,
              onTap: _handleToggle,
              semanticLabel: widget.title,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // A Row rather than the title alone, so the priority dot
                  // sits immediately after the text and moves with its
                  // length. Right-aligning it to the card would read as a
                  // column of its own, which is not what the design draws.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _PriorityMarks(priority: widget.priority),
                      Flexible(
                        child: AnimatedDefaultTextStyle(
                          duration: context.motion.fast,
                          curve: AppMotion.spring,
                          style: context.typography
                              .ui(
                                size: 16,
                                weight: FontWeight.w500,
                                height: 1.3,
                                color: palette.textPrimary,
                              )
                              .copyWith(
                                // Struck through, but not dimmed. A completed
                                // row keeps its weight; the only thing that
                                // fades on this screen is a whole past
                                // section.
                                decoration: _isCompleted
                                    ? TextDecoration.lineThrough
                                    : TextDecoration.none,
                                decorationColor: palette.textPrimary,
                              ),
                          child: Text(
                            widget.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      if (widget.subjectColor != null) ...[
                        const SizedBox(width: 8),
                        _SubjectDot(color: widget.subjectColor!),
                      ],
                    ],
                  ),
                  if (dueLine != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      dueLine,
                      style: context.typography.ui(
                        size: 13,
                        weight: FontWeight.w500,
                        color: widget.dueOverdue
                            ? palette.dueOverdue
                            : palette.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The circular check control. Expands its hit area well past the visible
/// circle, which at 22pt is far below a comfortable target.
class _CompletionBox extends StatelessWidget {
  const _CompletionBox({
    required this.isCompleted,
    required this.onTap,
    required this.semanticLabel,
  });

  final bool isCompleted;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

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
              duration: context.motion.fast,
              curve: AppMotion.spring,
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                // Flat accent when checked, whatever the priority. The box
                // says done; the dot beside the title says how urgent.
                color: isCompleted ? palette.accent : palette.checkboxFill,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isCompleted ? palette.accent : palette.bentoBorder,
                ),
              ),
              child: AnimatedScale(
                scale: isCompleted ? 1 : 0.4,
                duration: context.motion.fast,
                curve: AppMotion.spring,
                child: AnimatedOpacity(
                  opacity: isCompleted ? 1 : 0,
                  duration: context.motion.fast,
                  child: Icon(PhLight.check, size: 13, color: palette.onAccent),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The priority marker: one exclamation per step, in the priority's own hue.
///
/// Leading the title rather than trailing it, and marks rather than a dot: the
/// trailing slot now belongs to the subject swatch, and three priorities read
/// faster as a count than as three shades of the same circle. [TaskPriority.none]
/// draws nothing at all — an unprioritised task is unmarked, not marked quietly.
class _PriorityMarks extends StatelessWidget {
  const _PriorityMarks({required this.priority});

  final TaskPriority priority;

  int get _count {
    switch (priority) {
      case TaskPriority.none:
        return 0;
      case TaskPriority.low:
        return 1;
      case TaskPriority.medium:
        return 2;
      case TaskPriority.high:
        return 3;
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _count;
    if (count == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Semantics(
        label: '${priority.label} priority',
        child: Text(
          '!' * count,
          style: context.typography.ui(
            size: 15,
            weight: FontWeight.w700,
            color: context.palette.priorityColor(priority),
          ),
        ),
      ),
    );
  }
}

/// The subject swatch at the end of a study task's title.
class _SubjectDot extends StatelessWidget {
  const _SubjectDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Study task',
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
