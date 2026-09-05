import 'package:flutter/material.dart';

import '../../../models/task.dart';
import '../../components/components.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ph_light_icons.dart';

/// One row of the focus list. Mock only — the real list will come from
/// `visibleTasksProvider` once this screen is wired up.
class _FocusItem {
  const _FocusItem(this.id, this.title, this.detail, this.priority);

  final String id;
  final String title;
  final String detail;
  final TaskPriority priority;
}

const List<_FocusItem> _mockFocus = [
  _FocusItem('f1', 'Finish Anatomy dissection notes', 'Due 18:00', TaskPriority.high),
  _FocusItem('f2', 'Review Pathology flashcards', '40 cards left', TaskPriority.high),
  _FocusItem('f3', 'Email Dr. Farouk about the rotation', 'Due today', TaskPriority.medium),
  _FocusItem('f4', 'Refill water bottle', 'Habit', TaskPriority.low),
];

/// Today's shortlist, with working checkboxes over hardcoded rows.
///
/// The tick state lives in this widget and dies with it — deliberately, this
/// pass. Persisting it would mean a repository and a Hive box, which is the
/// step after this one.
class FocusTasksCard extends StatefulWidget {
  const FocusTasksCard({super.key});

  @override
  State<FocusTasksCard> createState() => _FocusTasksCardState();
}

class _FocusTasksCardState extends State<FocusTasksCard> {
  final Set<String> _done = <String>{};

  void _toggle(String id) {
    setState(() {
      if (!_done.remove(id)) _done.add(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final remaining = _mockFocus.length - _done.length;

    return CustomCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhLight.listChecks, size: 18, color: palette.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Today's focus",
                  style: context.typography.ui(size: 15, weight: FontWeight.w600),
                ),
              ),
              Text(
                remaining == 0 ? 'All clear' : '$remaining left',
                style: context.typography.ui(
                  size: 12,
                  color: remaining == 0 ? palette.success : palette.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final item in _mockFocus)
            _FocusRow(
              item: item,
              isDone: _done.contains(item.id),
              onTap: () => _toggle(item.id),
            ),
        ],
      ),
    );
  }
}

class _FocusRow extends StatelessWidget {
  const _FocusRow({
    required this.item,
    required this.isDone,
    required this.onTap,
  });

  final _FocusItem item;
  final bool isDone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Semantics(
      button: true,
      checked: isDone,
      label: item.title,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: minTouchTarget,
          child: Row(
            children: [
              AnimatedContainer(
                duration: context.motion.fast,
                curve: AppMotion.spring,
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isDone ? palette.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: isDone ? palette.accent : palette.textMuted,
                    width: 1.4,
                  ),
                ),
                child: isDone
                    ? Icon(PhLight.check, size: 13, color: palette.onAccent)
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // Struck through rather than removed: a list that
                      // reshuffles under the finger is hard to tick twice.
                      style: context.typography.ui(
                        size: 13.5,
                        color: isDone ? palette.textMuted : palette.textPrimary,
                      ).copyWith(
                        decoration:
                            isDone ? TextDecoration.lineThrough : null,
                        decorationColor: palette.textMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.typography.ui(
                        size: 11.5,
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              PriorityBadge(priority: item.priority, compact: true),
            ],
          ),
        ),
      ),
    );
  }
}
