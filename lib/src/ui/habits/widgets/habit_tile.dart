import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/habit.dart';
import '../../../models/habit_view.dart';
import '../../components/components.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ph_light_icons.dart';
import '../habit_colors.dart';

/// One cell of the habit grid.
///
/// Follows the same split as a task row: the circular control toggles the
/// current period, tapping anywhere else opens the editor. The control
/// flips locally on tap so it reacts on the same frame, and is re-synced
/// from [habit] in [didUpdateWidget] so an external change — or a failed
/// write — can never leave it lying about what is stored.
class HabitTile extends StatefulWidget {
  const HabitTile({
    super.key,
    required this.habit,
    required this.now,
    required this.onToggle,
    required this.onEdit,
  });

  final Habit habit;
  final DateTime now;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  @override
  State<HabitTile> createState() => _HabitTileState();
}

class _HabitTileState extends State<HabitTile> {
  late bool _isComplete = widget.habit.isCompletedNow(widget.now);

  @override
  void didUpdateWidget(HabitTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final stored = widget.habit.isCompletedNow(widget.now);
    if (stored != _isComplete) {
      setState(() => _isComplete = stored);
    }
  }

  void _handleToggle() {
    setState(() => _isComplete = !_isComplete);
    // A habit is completed dozens of times a week; the tick is the only
    // confirmation the user gets before the write lands.
    HapticFeedback.selectionClick();
    widget.onToggle();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final habit = widget.habit;
    final color = habitColorFromHex(habit.colorHex, palette.accent);

    return CustomCard(
      accent: color,
      selected: _isComplete,
      onTap: widget.onEdit,
      semanticLabel: '${habit.title}, ${habit.frequency.label}. '
          '${_isComplete ? 'Done' : 'Not done'} this '
          '${habit.frequency.periodNoun}. '
          'Streak ${habit.streakCount}. Tap to edit.',
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _CompletionControl(
                isComplete: _isComplete,
                color: color,
                onTap: _handleToggle,
                semanticLabel: habit.title,
              ),
              const Spacer(),
              if (habit.streakCount > 0)
                _StreakBadge(count: habit.streakCount, color: color),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            habit.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.typography.ui(
              size: 14.5,
              weight: FontWeight.w600,
              height: 1.25,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            habit.frequency.cadenceNote,
            style: context.typography.ui(size: 11.5, color: palette.textMuted),
          ),
          const Spacer(),
          _HistoryDots(
            history: habit.recentHistory(widget.now),
            color: color,
          ),
        ],
      ),
    );
  }
}

/// The circular tick. Keeps a 44pt hit area without growing the visible
/// circle past 26pt.
class _CompletionControl extends StatelessWidget {
  const _CompletionControl({
    required this.isComplete,
    required this.color,
    required this.onTap,
    required this.semanticLabel,
  });

  final bool isComplete;
  final Color color;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Semantics(
      checked: isComplete,
      label: 'Mark $semanticLabel complete',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Align(
            alignment: Alignment.centerLeft,
            child: AnimatedContainer(
              duration: context.motion.fast,
              curve: AppMotion.spring,
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: isComplete ? color : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isComplete ? color : palette.glassBorder,
                  width: 1.5,
                ),
              ),
              child: AnimatedScale(
                scale: isComplete ? 1 : 0.4,
                duration: context.motion.fast,
                curve: AppMotion.spring,
                child: AnimatedOpacity(
                  opacity: isComplete ? 1 : 0,
                  duration: context.motion.fast,
                  child: Icon(
                    PhLight.check,
                    size: 15,
                    color: palette.onAccent,
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

class _StreakBadge extends StatelessWidget {
  const _StreakBadge({required this.count, required this.color});

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$count period streak',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhLight.fire, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: context.typography.ui(
                size: 11.5,
                weight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The recent-history strip. The last dot is the current period, drawn with
/// a ring so "today" is locatable even when the whole row is empty.
class _HistoryDots extends StatelessWidget {
  const _HistoryDots({required this.history, required this.color});

  final List<bool> history;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Row(
      children: [
        for (var i = 0; i < history.length; i++) ...[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: history[i] ? color : palette.glassBorder,
              border: i == history.length - 1
                  ? Border.all(color: color.withValues(alpha: 0.6))
                  : null,
            ),
          ),
          if (i != history.length - 1) const SizedBox(width: 5),
        ],
      ],
    );
  }
}
