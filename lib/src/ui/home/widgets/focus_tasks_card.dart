import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/task.dart';
import '../../../providers/clock_providers.dart';
import '../../../providers/task_providers.dart';
import '../../../providers/task_view_providers.dart';
import '../../components/components.dart';
import '../../format/time_format.dart';
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
class FocusTasksCard extends ConsumerWidget {
  const FocusTasksCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final tasks = ref.watch(todayFocusTasksProvider);

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
      // The rows inside are each their own control, so the card lights up
      // under a pointer even though the card itself does nothing.
      hoverLift: true,
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
              _RemainingLabel(tasks: tasks),
            ],
          ),
          const SizedBox(height: 6),
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

/// `3 left` / `All clear`, or nothing at all until the list has arrived.
class _RemainingLabel extends StatelessWidget {
  const _RemainingLabel({required this.tasks});

  final AsyncValue<List<Task>> tasks;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final list = tasks.value;
    if (list == null) return const SizedBox.shrink();

    final remaining = list.where((task) => !task.isCompleted).length;

    return Text(
      remaining == 0 ? 'All clear' : '$remaining left',
      style: context.typography.ui(
        size: 12,
        color: remaining == 0 ? palette.success : palette.textMuted,
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
      return const HomeCardNote(
        icon: PhLight.listChecks,
        message: 'No tasks today',
      );
    }

    final now = ref.watch(currentMinuteProvider);
    final shown = tasks.take(_shortlistLength).toList(growable: false);
    final hidden = tasks.length - shown.length;

    return Column(
      children: [
        for (final task in shown)
          _FocusRow(
            task: task,
            now: now,
            onTap: () =>
                ref.read(taskListProvider.notifier).toggleCompleted(task.id),
          ),
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
    required this.now,
    required this.onTap,
  });

  final Task task;
  final DateTime now;
  final VoidCallback onTap;

  /// The line under the title: when it is due if it has a time today, and
  /// what it belongs to otherwise.
  String get _detail =>
      task.dueDate == null ? task.category : formatDueLabel(task.dueDate!, now);

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
                        decoration:
                            isDone ? TextDecoration.lineThrough : null,
                        decorationColor: palette.textMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _detail,
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
              PriorityBadge(priority: task.priority, compact: true),
            ],
          ),
        ),
      ),
    );
  }
}
