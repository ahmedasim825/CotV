import 'package:flutter/material.dart';

import '../../../models/task.dart';
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
    this.dueLine,
    this.dueOverdue = false,
  });

  final String title;
  final bool isCompleted;
  final TaskPriority priority;
  final VoidCallback onToggle;
  final VoidCallback onTap;

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
          crossAxisAlignment: CrossAxisAlignment.start,
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(top: 7),
                        child: _PriorityDot(priority: widget.priority),
                      ),
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

/// The priority marker: a filled dot, always at 60%.
///
/// The alpha is applied here rather than in the palette because the same
/// three hues are drawn at full strength by the priority badge and the
/// timeline blocks — this row is the surface that wants them quiet.
class _PriorityDot extends StatelessWidget {
  const _PriorityDot({required this.priority});

  final TaskPriority priority;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${priority.name} priority',
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: context.palette.priorityColor(priority).withValues(alpha: 0.6),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
