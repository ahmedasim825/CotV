import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../models/day_groups.dart';
import '../../models/reminder.dart';
import '../../models/task.dart';
import '../../models/task_view.dart';
import '../../providers/clock_providers.dart';
import '../../providers/reminder_providers.dart';
import '../../providers/task_providers.dart';
import '../format/time_format.dart';
import '../responsive/breakpoints.dart';
import '../theme/app_theme.dart';
import '../widgets/status_card.dart';
import 'reminder_form_sheet.dart';
import 'task_form_sheet.dart';
import 'widgets/bento_section.dart';
import 'widgets/checkable_row.dart';
import 'widgets/inline_add_row.dart';
import 'widgets/segment_switcher.dart';

const _uuid = Uuid();

/// Which of the two lists the segmented control is showing.
enum _TaskSegment { tasks, reminders }

/// The Tasks destination: a segmented control over the task list and the
/// reminder list, each grouped into Today / Yesterday / Last 7 days.
///
/// ## What this screen does not show
///
/// Anything dated after today. [groupByDay] drops it — there is no section a
/// future item could land in, and the design has none. A task due next week
/// exists, syncs and fires its notification; it simply is not on this screen
/// until the day arrives. The form sheet reached from the dashboard can still
/// create one, so this is a real way to set something and not see it here.
///
/// Tasks with no due date fall back to [Task.createdAt], so a quick capture
/// made today sits under Today rather than vanishing for want of a date.
///
/// Segment selection is local UI state, not app state — nothing outside this
/// widget cares which of the two is showing, and it resets on rebuild the way
/// a `TabBar`'s selection would.
class TaskListView extends ConsumerStatefulWidget {
  const TaskListView({super.key});

  @override
  ConsumerState<TaskListView> createState() => _TaskListViewState();
}

class _TaskListViewState extends ConsumerState<TaskListView> {
  _TaskSegment _segment = _TaskSegment.tasks;

  @override
  Widget build(BuildContext context) {
    return AdaptiveLayout(
      builder: (context, windowSize) {
        final padding = windowSize.pagePadding;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(padding, 18, padding, 0),
              child: SegmentSwitcher(
                labels: const ['Tasks', 'Reminders'],
                selectedIndex: _segment.index,
                onSelected: (index) => setState(
                  () => _segment = _TaskSegment.values[index],
                ),
              ),
            ),
            const SizedBox(height: 26),
            Expanded(
              child: switch (_segment) {
                _TaskSegment.tasks => _TaskSections(padding: padding),
                _TaskSegment.reminders => _ReminderSections(padding: padding),
              },
            ),
          ],
        );
      },
    );
  }
}

/// The day-grouped list both segments render into.
///
/// Generic over the row type so the two segments share their whole layout —
/// the scroll padding, the section spacing, the inline add in Today — and
/// differ only in what a row is and what adding one means.
class _SectionList<T> extends StatelessWidget {
  const _SectionList({
    required this.sections,
    required this.padding,
    required this.rowBuilder,
    required this.addHint,
    required this.addLabel,
    required this.onAdd,
  });

  final List<DaySection<T>> sections;
  final double padding;
  final Widget Function(T item) rowBuilder;
  final String addHint;
  final String addLabel;
  final ValueChanged<String> onAdd;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        padding,
        0,
        padding,
        // Clears the nav bar, the home indicator, and the keyboard when the
        // inline add has focus — without the inset the field would open
        // underneath it.
        28 +
            MediaQuery.paddingOf(context).bottom +
            MediaQuery.viewInsetsOf(context).bottom,
      ),
      itemCount: sections.length,
      separatorBuilder: (_, _) => const SizedBox(height: 32),
      itemBuilder: (context, index) {
        final section = sections[index];
        return BentoSection(
          title: section.title,
          isPast: section.isPast,
          rows: [for (final item in section.items) rowBuilder(item)],
          // Only Today takes new items. Adding to a past day would mean
          // back-dating, which is a different gesture than the one this
          // control offers.
          footer: section.bucket == DayBucket.today
              ? InlineAddRow(
                  hint: addHint,
                  semanticLabel: addLabel,
                  onSubmit: onAdd,
                )
              : null,
        );
      },
    );
  }
}

class _TaskSections extends ConsumerWidget {
  const _TaskSections({required this.padding});

  final double padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(taskListProvider);
    // Watched rather than read off the wall clock, so a row crossing midnight
    // moves from Today to Yesterday without waiting for an unrelated rebuild.
    final now = ref.watch(currentMinuteProvider);

    return tasksAsync.when(
      data: (tasks) {
        final sections = groupByDay<Task>(
          // Sorted before grouping, so each section comes out in due-time
          // order without every section re-sorting its own slice.
          sortTasks(tasks, TaskSort.dueTime),
          dateOf: (task) => task.dueDate ?? task.createdAt,
          now: now,
        );

        return _SectionList<Task>(
          sections: sections,
          padding: padding,
          addHint: 'New task',
          addLabel: 'Add task',
          onAdd: (title) => ref.read(taskListProvider.notifier).addTask(
                // No due date: `groupByDay` falls back to `createdAt`, which
                // is now, so it lands in Today without this control having to
                // ask for a date it has no room to ask for.
                Task(id: _uuid.v4(), title: title),
              ),
          rowBuilder: (task) => CheckableRow(
            key: ValueKey(task.id),
            title: task.title,
            isCompleted: task.isCompleted,
            priority: task.priority,
            onToggle: () =>
                ref.read(taskListProvider.notifier).toggleCompleted(task.id),
            onTap: () => showTaskFormSheet(context, existing: task),
          ),
        );
      },
      loading: () => _Loading(),
      error: (error, _) => _Error(message: 'Could not load tasks: $error',
          padding: padding),
    );
  }
}

class _ReminderSections extends ConsumerWidget {
  const _ReminderSections({required this.padding});

  final double padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remindersAsync = ref.watch(reminderListProvider);
    // Also drives the overdue colour: a reminder passing its due instant
    // while this segment is on screen has to turn red by itself.
    final now = ref.watch(currentMinuteProvider);

    return remindersAsync.when(
      data: (reminders) {
        final sorted = [...reminders]
          ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
        final sections = groupByDay<Reminder>(
          sorted,
          dateOf: (reminder) => reminder.dueAt,
          now: now,
        );

        return _SectionList<Reminder>(
          sections: sections,
          padding: padding,
          addHint: 'New reminder',
          addLabel: 'Add reminder',
          onAdd: (title) =>
              ref.read(reminderListProvider.notifier).addReminder(
                    Reminder(
                      id: _uuid.v4(),
                      title: title,
                      // End of today. A reminder must have a moment, and this
                      // control has no room to ask for one: the last minute of
                      // the day puts the row in Today without it arriving
                      // already overdue. Tapping the row opens the sheet to
                      // set a real time.
                      dueAt: _endOfDay(now),
                    ),
                  ),
          rowBuilder: (reminder) => CheckableRow(
            key: ValueKey(reminder.id),
            title: reminder.title,
            isCompleted: reminder.isCompleted,
            priority: reminder.priority,
            dueLine: formatReminderDueLine(reminder.dueAt, now),
            dueOverdue: reminder.isOverdue(now),
            onToggle: () => ref
                .read(reminderListProvider.notifier)
                .toggleCompleted(reminder.id),
            onTap: () => showReminderFormSheet(context, existing: reminder),
          ),
        );
      },
      loading: () => _Loading(),
      error: (error, _) => _Error(
        message: 'Could not load reminders: $error',
        padding: padding,
      ),
    );
  }
}

DateTime _endOfDay(DateTime now) =>
    DateTime(now.year, now.month, now.day, 23, 59);

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CircularProgressIndicator(
        color: context.palette.accent,
        strokeWidth: 2.5,
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.message, required this.padding});

  final String message;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(padding),
      child: StatusCard(message: message, tone: StatusTone.error),
    );
  }
}
