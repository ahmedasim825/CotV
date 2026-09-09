import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/reminder.dart';
import '../../models/task.dart';
import '../../models/task_view.dart';
import '../../providers/clock_providers.dart';
import '../../providers/reminder_providers.dart';
import '../../providers/task_providers.dart';
import '../../providers/task_view_providers.dart';
import '../format/time_format.dart';
import '../habits/habit_screen.dart';
import '../home/widgets/home_card_note.dart';
import '../responsive/breakpoints.dart';
import '../theme/app_theme.dart';
import '../widgets/ph_light_icons.dart';
import '../widgets/status_card.dart';
import 'task_form_sheet.dart';
import 'widgets/task_tile.dart';

/// Which of the three lists the segmented control is showing.
enum _TaskSegment { tasks, reminders, habits }

/// The Tasks destination: a segmented control over the task list, the
/// reminder list, and the habit grid.
///
/// Habits lives here rather than as its own sidebar destination because the
/// sidebar has exactly five rows by design (see `AppDestinationX.navItems`);
/// this segment is what makes [HabitScreen] reachable again. Tasks stays the
/// default segment so `paneFor(AppDestination.tasks)` opens to the same
/// screen it always has.
///
/// Segment selection is local UI state, not app state — nothing outside this
/// widget cares which of the three is showing, and it resets on rebuild the
/// way a `TabBar`'s selection would. That is why this is a
/// [ConsumerStatefulWidget] rather than the [ConsumerWidget] it used to be:
/// a `Notifier` would outlive the screen for no reason and give every other
/// consumer a provider to ignore.
class TaskListView extends ConsumerStatefulWidget {
  const TaskListView({super.key, this.showFab = true});

  /// The split view hosts a single shared FAB, so the pane suppresses its
  /// own. Only meaningful for the tasks and habits segments — each renders
  /// its own FAB internally and reads this same flag.
  final bool showFab;

  @override
  ConsumerState<TaskListView> createState() => _TaskListViewState();
}

class _TaskListViewState extends ConsumerState<TaskListView> {
  _TaskSegment _segment = _TaskSegment.tasks;

  /// The task list exactly as it was before segments existed.
  ///
  /// Every mutation goes through [TaskListNotifier], which writes to Hive;
  /// the box's change stream feeds [visibleTasksProvider] straight back
  /// here, so nothing in this method manages its own copy of the list.
  Widget _buildTaskList(BuildContext context) {
    return AdaptiveLayout(
      builder: (context, windowSize) {
        final tasksAsync = ref.watch(visibleTasksProvider);
        final filter = ref.watch(taskFilterProvider);
        final now = ref.watch(currentMinuteProvider);
        final padding = windowSize.pagePadding;

        return Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(padding, 12, padding, 0),
                  child: const _TaskListHeader(),
                ),
                const SizedBox(height: 14),
                _FilterTabs(horizontalPadding: padding),
                const SizedBox(height: 14),
                Expanded(
                  child: tasksAsync.when(
                    data: (tasks) => tasks.isEmpty
                        ? _EmptyState(filter: filter, padding: padding)
                        : _TaskList(
                            tasks: tasks,
                            now: now,
                            padding: padding,
                          ),
                    loading: () => Center(
                      child: CircularProgressIndicator(
                        color: context.palette.accent,
                        strokeWidth: 2.5,
                      ),
                    ),
                    error: (error, _) => Padding(
                      padding: EdgeInsets.all(padding),
                      child: StatusCard(
                        message: 'Could not load tasks: $error',
                        tone: StatusTone.error,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (widget.showFab)
              Positioned(
                right: padding,
                bottom: 20 + MediaQuery.paddingOf(context).bottom,
                child: const QuickAddTaskButton(),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: SegmentedButton<_TaskSegment>(
            segments: const [
              ButtonSegment(value: _TaskSegment.tasks, label: Text('Tasks')),
              ButtonSegment(
                  value: _TaskSegment.reminders, label: Text('Reminders')),
              ButtonSegment(value: _TaskSegment.habits, label: Text('Habits')),
            ],
            selected: {_segment},
            showSelectedIcon: false,
            onSelectionChanged: (next) =>
                setState(() => _segment = next.first),
          ),
        ),
        Expanded(
          child: switch (_segment) {
            _TaskSegment.tasks => _buildTaskList(context),
            _TaskSegment.reminders => const _ReminderList(),
            _TaskSegment.habits => HabitScreen(showFab: widget.showFab),
          },
        ),
      ],
    );
  }
}

class _TaskListHeader extends ConsumerWidget {
  const _TaskListHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(taskSortProvider);

    return Row(
      children: [
        Expanded(
          child: Text(
            'Tasks',
            style: context.typography.display(size: 30, weight: FontWeight.w500),
          ),
        ),
        Semantics(
          button: true,
          label: 'Sort by ${sort.label}. Tap to change.',
          child: GestureDetector(
            onTap: () => ref.read(taskSortProvider.notifier).toggle(),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: BoxDecoration(
                color: context.palette.glassFill,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: context.palette.glassBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    PhLight.sortAscending,
                    size: 14,
                    color: context.palette.accent,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    sort.label,
                    style: context.typography.ui(size: 12.5, weight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The reminder segment: one row per [Reminder] from [reminderListProvider].
///
/// A plain [ConsumerWidget] rather than a stateful one — there is no local
/// interaction here yet (Task 8 adds the edit pencil), only watches on the
/// provider and the clock provider, and a render.
class _ReminderList extends ConsumerWidget {
  const _ReminderList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reminders = ref.watch(reminderListProvider);
    // Watch the clock provider so the list updates when a reminder crosses
    // its due instant while this segment stays mounted. Without this, a row
    // would show stale `isOverdue()` and due-label colors until an unrelated
    // rebuild triggered (a segment switch, or an add/update/remove). We watch
    // currentMinuteProvider rather than reading DateTime.now() inline so the
    // update is driven by the provider instead of the wall clock.
    final now = ref.watch(currentMinuteProvider);

    if (reminders.isEmpty) {
      return const Center(
        child: HomeCardNote(icon: PhLight.bellSimple, message: 'No reminders'),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        // Clears the home indicator; this segment has no FAB of its own.
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      itemCount: reminders.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) =>
          _ReminderRow(reminder: reminders[index], now: now),
    );
  }
}

class _ReminderRow extends StatelessWidget {
  const _ReminderRow({required this.reminder, required this.now});

  final Reminder reminder;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final overdue = reminder.isOverdue(now);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.palette.hairline),
      ),
      child: Row(
        children: [
          Icon(PhLight.bellSimple, size: 16, color: context.palette.accent),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reminder.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.typography.ui(size: 15, weight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  formatReminderDueLabel(reminder.dueAt, now),
                  style: context.typography.ui(
                    size: 11.5,
                    color: overdue ? context.palette.danger : context.palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterTabs extends ConsumerWidget {
  const _FilterTabs({required this.horizontalPadding});

  final double horizontalPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(taskFilterProvider);
    final counts = ref.watch(taskFilterCountsProvider);

    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        itemCount: TaskFilter.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = TaskFilter.values[index];
          return _FilterChip(
            filter: filter,
            count: counts[filter] ?? 0,
            isSelected: filter == selected,
            onTap: () => ref.read(taskFilterProvider.notifier).select(filter),
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.filter,
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  final TaskFilter filter;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: '${filter.label}, $count tasks',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: context.motion.fast,
          curve: AppMotion.spring,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? context.palette.accent : context.palette.glassFill,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isSelected ? context.palette.accent : context.palette.glassBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                filter.label,
                style: context.typography.ui(
                  size: 13,
                  weight: FontWeight.w600,
                  color: isSelected ? context.palette.onAccent : context.palette.textSecondary,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 7),
                Text(
                  '$count',
                  style: context.typography.ui(
                    size: 11.5,
                    weight: FontWeight.w700,
                    color: isSelected
                        ? context.palette.onAccent.withValues(alpha: 0.7)
                        : context.palette.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskList extends ConsumerWidget {
  const _TaskList({
    required this.tasks,
    required this.now,
    required this.padding,
  });

  final List<Task> tasks;
  final DateTime now;
  final double padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        padding,
        4,
        padding,
        // Clears the FAB and the home indicator.
        96 + MediaQuery.paddingOf(context).bottom,
      ),
      itemCount: tasks.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final task = tasks[index];
        return _DismissibleTask(
          key: ValueKey(task.id),
          task: task,
          now: now,
        );
      },
    );
  }
}

/// Wraps a [TaskTile] in swipe-to-delete with an undo affordance.
///
/// Deletion is committed immediately rather than held behind a timer, so the
/// list and the database never disagree; undo re-adds the task from the copy
/// captured before the delete.
class _DismissibleTask extends ConsumerWidget {
  const _DismissibleTask({super.key, required this.task, required this.now});

  final Task task;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messenger = ScaffoldMessenger.of(context);
    // Resolved before the delete so the snack bar is styled from tokens
    // captured while this context was still mounted.
    final palette = context.palette;
    final typography = context.typography;

    return Dismissible(
      key: ValueKey('dismiss:${task.id}'),
      direction: DismissDirection.endToStart,
      // Deliberately more than the default 0.4: deleting is destructive, so
      // it should take a decisive swipe.
      dismissThresholds: const {DismissDirection.endToStart: 0.55},
      background: const _DeleteBackground(),
      onDismissed: (_) async {
        final removed = task;
        await ref.read(taskListProvider.notifier).deleteTask(removed.id);

        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              backgroundColor: palette.surface,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: palette.glassBorder),
              ),
              content: Text(
                'Deleted "${removed.title}"',
                style: typography.ui(size: 13),
              ),
              action: SnackBarAction(
                label: 'Undo',
                textColor: palette.accent,
                onPressed: () =>
                    ref.read(taskListProvider.notifier).addTask(removed),
              ),
            ),
          );
      },
      child: TaskTile(
        task: task,
        now: now,
        onToggleCompleted: () =>
            ref.read(taskListProvider.notifier).toggleCompleted(task.id),
        onTap: () => showTaskFormSheet(context, existing: task),
      ),
    );
  }
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 24),
      decoration: BoxDecoration(
        color: context.palette.danger.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhLight.trash, size: 18, color: context.palette.danger),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filter, required this.padding});

  final TaskFilter filter;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: padding + 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.palette.glassFill,
                shape: BoxShape.circle,
              ),
              child: Icon(
                PhLight.sparkle,
                size: 24,
                color: context.palette.accent,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              filter.emptyMessage,
              textAlign: TextAlign.center,
              style: context.typography.ui(
                size: 14,
                color: context.palette.textMuted,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The quick-add FAB. Exposed so the iPad split view can host one shared
/// button above both panes.
class QuickAddTaskButton extends StatelessWidget {
  const QuickAddTaskButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Add task',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => showTaskFormSheet(context),
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            decoration: BoxDecoration(
              color: context.palette.accent,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: context.palette.accent.withValues(alpha: 0.28),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(PhLight.plus, size: 17, color: context.palette.onAccent),
                const SizedBox(width: 9),
                Text(
                  'Task',
                  style: context.typography.ui(
                    size: 14,
                    weight: FontWeight.w700,
                    color: context.palette.onAccent,
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
