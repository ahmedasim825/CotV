import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../models/day_groups.dart';
import '../../models/task.dart';
import '../../models/task_list_entry.dart';
import '../../models/task_list_filter.dart';
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
import 'widgets/task_filter_menu.dart';

const _uuid = Uuid();

/// The Tasks destination: tasks and reminders in one list, grouped by day,
/// narrowed by the menu at the head of the first section.
///
/// ## One list, two boxes
///
/// The screen used to split into Tasks and Reminders segments. It does not any
/// more — both kinds interleave, ordered by when they are due, and the only
/// thing distinguishing them on screen is that a reminder carries a due line
/// under its title and a task does not. The dashboard's agenda card solves the
/// same problem with ring colour instead; this screen cannot, because a row's
/// trailing dot is already spoken for by priority.
///
/// ## What this screen does not show
///
/// Whatever the active filter's [DayRange] excludes, and nothing is clamped
/// into view to compensate: under the default range an item dated after today
/// is absent until the day arrives, and under [TaskListFilter.upcoming] the
/// past is. The form sheets can still create either, so a due date set far
/// out is a real way to put something where this screen will not show it.
///
/// Tasks with no due date fall back to [Task.createdAt], so a quick capture
/// sits under Today rather than vanishing for want of a date.
///
/// Filter selection is local UI state, not app state — nothing outside this
/// widget cares which filter is active, and it resets on rebuild the way the
/// segmented control's selection used to.
class TaskListView extends ConsumerStatefulWidget {
  const TaskListView({super.key});

  @override
  ConsumerState<TaskListView> createState() => _TaskListViewState();
}

class _TaskListViewState extends ConsumerState<TaskListView> {
  TaskListFilter _filter = TaskListFilter.all;

  @override
  Widget build(BuildContext context) {
    return AdaptiveLayout(
      builder: (context, windowSize) {
        final tasksAsync = ref.watch(taskListProvider);
        final remindersAsync = ref.watch(reminderListProvider);
        // Watched rather than read off the wall clock, so a row crossing
        // midnight moves from Today to Yesterday without waiting for an
        // unrelated rebuild — and so a reminder's due line turns red on its
        // own the minute it passes.
        final now = ref.watch(currentMinuteProvider);
        final padding = windowSize.pagePadding;

        final error = tasksAsync.error ?? remindersAsync.error;
        if (error != null) {
          return _Error(
            message: 'Could not load your list: $error',
            padding: padding,
          );
        }

        final tasks = tasksAsync.value;
        final reminders = remindersAsync.value;
        // Both boxes have to answer before anything can render: a list drawn
        // from one of them would show a partial day and then reshuffle when
        // the other arrived.
        if (tasks == null || reminders == null) return const _Loading();

        final kind = _filter.kind;
        final entries = mergeTaskList(tasks, reminders)
            .where((entry) => kind == null || entry.kind == kind)
            .toList(growable: false);

        final sections = groupByDay<TaskListEntry>(
          entries,
          dateOf: (entry) => entry.bucketDate,
          now: now,
          range: _filter.range,
        ).where((section) {
          // `groupByDay` always emits Today so the add row has a home. Under
          // the Past filter that is wrong — a list called Past that opens on
          // today is not past — so it is dropped here rather than teaching the
          // grouping about filters it should not know about.
          return !(_filter.hidesToday && section.bucket == DayBucket.today);
        }).toList(growable: false);

        return _Sections(
          sections: sections,
          now: now,
          padding: padding,
          filter: _filter,
          onFilterChanged: (filter) => setState(() => _filter = filter),
        );
      },
    );
  }
}

class _Sections extends ConsumerWidget {
  const _Sections({
    required this.sections,
    required this.now,
    required this.padding,
    required this.filter,
    required this.onFilterChanged,
  });

  final List<DaySection<TaskListEntry>> sections;
  final DateTime now;
  final double padding;
  final TaskListFilter filter;
  final ValueChanged<TaskListFilter> onFilterChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (sections.isEmpty) {
      // Only reachable under a filter whose range came back empty — the
      // default range always has Today. Still a heading, so the menu that got
      // you here stays reachable.
      return _EmptyRange(
        padding: padding,
        filter: filter,
        onFilterChanged: onFilterChanged,
      );
    }

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
          // The design sets the menu level with the first heading rather than
          // in a bar of its own, so it belongs to whichever section leads.
          trailing: index == 0
              ? TaskFilterMenu(active: filter, onSelected: onFilterChanged)
              : null,
          rows: [
            for (final entry in section.items) _row(context, ref, entry),
          ],
          // Only Today takes new items. Adding to a past day would mean
          // back-dating, and to a future one would mean asking for a date this
          // control has no room to ask for.
          footer: section.bucket == DayBucket.today
              ? InlineAddRow(
                  hint: 'New task',
                  semanticLabel: 'Add task',
                  onSubmit: (title) => ref
                      .read(taskListProvider.notifier)
                      // A task, not a reminder: a merged list needs one
                      // default, and a task is the lighter of the two — a
                      // reminder cannot exist without a moment, and this row
                      // has nowhere to ask for one. Undated, so `groupByDay`
                      // files it under Today through `createdAt`.
                      .addTask(Task(id: _uuid.v4(), title: title)),
                )
              : null,
        );
      },
    );
  }

  Widget _row(BuildContext context, WidgetRef ref, TaskListEntry entry) {
    final isReminder = entry.kind == TaskListKind.reminder;
    final due = entry.dueAt;

    return CheckableRow(
      key: ValueKey(entry.id),
      title: entry.title,
      isCompleted: entry.isCompleted,
      priority: entry.priority,
      // The one thing separating the two kinds on screen. A task's due date is
      // carried by the section it sits in; a reminder's exact moment is the
      // point of it, so it gets a line of its own.
      dueLine: isReminder && due != null
          ? formatReminderDueLine(due, now)
          : null,
      dueOverdue: entry.isOverdue(now),
      onToggle: () => isReminder
          ? ref
              .read(reminderListProvider.notifier)
              .toggleCompleted(entry.sourceId)
          : ref.read(taskListProvider.notifier).toggleCompleted(entry.sourceId),
      onTap: () => _openSheet(context, ref, entry),
    );
  }

  void _openSheet(BuildContext context, WidgetRef ref, TaskListEntry entry) {
    switch (entry.kind) {
      case TaskListKind.task:
        final task = ref.read(taskRepositoryProvider).getById(entry.sourceId);
        if (task != null) showTaskFormSheet(context, existing: task);
      case TaskListKind.reminder:
        final reminder =
            ref.read(reminderRepositoryProvider).getById(entry.sourceId);
        if (reminder != null) {
          showReminderFormSheet(context, existing: reminder);
        }
    }
  }
}

/// A range with nothing in it — Upcoming before anything has been scheduled.
class _EmptyRange extends StatelessWidget {
  const _EmptyRange({
    required this.padding,
    required this.filter,
    required this.onFilterChanged,
  });

  final double padding;
  final TaskListFilter filter;
  final ValueChanged<TaskListFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(padding, 0, padding, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  filter.label,
                  style: context.typography.display(
                    size: 28,
                    weight: FontWeight.w700,
                    letterSpacing: -0.8,
                    color: context.palette.textPrimary,
                  ),
                ),
              ),
              TaskFilterMenu(active: filter, onSelected: onFilterChanged),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Nothing here yet.',
            style: context.typography.ui(
              size: 13.5,
              color: context.palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

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
