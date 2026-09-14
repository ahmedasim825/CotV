import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/task.dart';
import '../../../providers/task_providers.dart';
import '../../../providers/task_view_providers.dart';
import '../../components/components.dart';
import '../../app_shell.dart';
import '../../tasks/task_form_sheet.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ph_light_icons.dart';
import 'home_card_note.dart';

/// How many of today's tasks the dashboard names.
///
/// The shortlist is a prompt, not the list: five rows is what fits beside
/// the rest of the dashboard, and anything past that is one tap away on the
/// Tasks screen.
const int _shortlistLength = 5;

/// Today's shortlist, ticked straight through to the repository.
///
/// Reads [todayFocusTasksProvider] rather than `visibleTasksProvider` so
/// what the dashboard calls "today" cannot be changed by the filter chips on
/// another screen.
///
/// No "N left" counter above the rows and no per-row detail line: the mock
/// draws each row as a circle and a title, nothing else, and the Tasks
/// screen one tap away is where a count or a due time actually belongs.
class FocusTasksCard extends ConsumerWidget {
  const FocusTasksCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(todayFocusTasksProvider);

    return HomeCardFrame(
      title: 'Tasks',
      onEdit: () => showTaskFormSheet(context),
      onTap: () => AppNavigation.maybeOf(context)?.call(AppDestination.tasks),
      semanticLabel: 'Tasks. Open the task list.',
      // The rows inside are each their own control and win the gesture arena
      // for taps that land on them, so ticking a task still ticks it rather
      // than navigating.
      hoverLift: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          tasks.when(
            data: (list) => _Rows(tasks: list),
            // A spinner rather than an empty list: on a cold launch the Hive
            // stream has not delivered yet, and "No tasks today" would be a
            // claim the app cannot back at that point.
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 26),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (_, _) => const HomeCardNote(
              icon: PhLight.warningCircle,
              message: 'Your tasks could not be read.',
            ),
          ),
        ],
      ),
    );
  }
}

class _Rows extends ConsumerWidget {
  const _Rows({required this.tasks});

  final List<Task> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tasks.isEmpty) {
      return const HomeCardNote(message: 'No tasks today.');
    }

    final shown = tasks.take(_shortlistLength).toList(growable: false);
    final hidden = tasks.length - shown.length;

    return Column(
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          _FocusRow(
            task: shown[i],
            onTap: () => ref
                .read(taskListProvider.notifier)
                .toggleCompleted(shown[i].id),
          ),
          // Only between rows, not under the last one: Reminders gates its
          // separator the same way.
          if (i < shown.length - 1) Divider(color: context.palette.hairline, height: 20),
        ],
        if (hidden > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              '+$hidden more on Tasks',
              style: context.typography.ui(
                size: 11.5,
                color: context.palette.textMuted,
              ),
            ),
          ),
      ],
    );
  }
}

class _FocusRow extends StatelessWidget {
  const _FocusRow({
    required this.task,
    required this.onTap,
  });

  final Task task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isDone = task.isCompleted;

    return Semantics(
      button: true,
      checked: isDone,
      label: task.title,
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
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isDone ? palette.accent : Colors.transparent,
                  shape: BoxShape.circle,
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
                child: Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // Struck through rather than removed: a completed task
                  // leaves the Today filter on the repository's next
                  // event, and the strike is what makes that read as a
                  // tick rather than a row vanishing under the finger.
                  style: context.typography.ui(
                    size: 13.5,
                    color: isDone ? palette.textMuted : palette.textPrimary,
                  ).copyWith(
                    decoration: isDone ? TextDecoration.lineThrough : null,
                    decorationColor: palette.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              PriorityBadge(priority: task.priority, compact: true),
            ],
          ),
        ),
      ),
    );
  }
}
