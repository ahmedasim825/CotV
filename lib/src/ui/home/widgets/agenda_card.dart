import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/agenda_view.dart';
import '../../../models/reminder.dart';
import '../../../providers/clock_providers.dart';
import '../../../providers/reminder_providers.dart';
import '../../../providers/task_providers.dart';
import '../../../providers/task_view_providers.dart';
import '../../app_shell.dart';
import '../../format/time_format.dart';
import '../../tasks/reminder_form_sheet.dart';
import '../../tasks/task_form_sheet.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ph_light_icons.dart';
import 'home_card_note.dart';

/// How many rows the card names before it starts counting instead.
///
/// The same five [FocusTasksCard] and [RemindersCard] each allow — but five
/// across *both* kinds now, not five each, because the mock draws one card
/// where there were two and ten rows would be most of a phone screen.
const int _shortlistLength = 5;

/// Tasks and reminders in one list, soonest first — the iOS dashboard's
/// replacement for the Tasks and Reminders pair.
///
/// The two cards it replaces are still there and still used on Windows; this
/// is composed in their place only where `context.useLiquidGlass` holds. The
/// duplicated row rendering between them is deliberate: the originals are
/// pinned by a dozen assertions that describe the desktop bento, and pulling a
/// shared row out of them would disturb every one of those to buy Windows
/// nothing.
///
/// The rows carry no headings and no group separator, so **the ring colour is
/// the only thing saying which kind a row is** — a task's ring is
/// `palette.taskRing`, a reminder's `palette.reminderRing`. That is also why
/// [mergeAgenda]'s ordering has to be total: with nothing else marking the
/// boundary, a row that moved between rebuilds would look like a glitch.
class AgendaCard extends ConsumerWidget {
  const AgendaCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(todayFocusTasksProvider);
    // Defaulted rather than branched on: `tasks.when` below already holds a
    // spinner over the frame before the Hive streams deliver, and both boxes
    // are opened before `runApp`, so an empty reminder list here is only ever
    // visible underneath that spinner.
    final reminders = ref.watch(reminderListProvider).value ?? const [];
    // Watched, not `DateTime.now()`: a reminder crossing its due instant while
    // the card is on screen has to turn red by itself, which is the same
    // reason `RemindersCard` reads this provider.
    final now = ref.watch(currentMinuteProvider);

    return HomeCardFrame(
      title: 'Tasks / Reminders',
      // One pencil for two kinds, and it makes a task. The mock draws a single
      // action here, and a chooser sheet in front of it would put two taps
      // between the user and the common case; the Tasks screen this card opens
      // has a reminder segment for the other one.
      onEdit: () => showTaskFormSheet(context),
      onTap: () => AppNavigation.maybeOf(context)?.call(AppDestination.tasks),
      semanticLabel: 'Tasks and reminders. Open the task list.',
      // The rows are each their own control and win the gesture arena for taps
      // that land on them, so ticking a task still ticks it rather than
      // navigating.
      hoverLift: true,
      child: tasks.when(
        data: (list) => _Rows(
          entries: mergeAgenda(list, reminders),
          reminders: reminders,
          now: now,
        ),
        // A spinner rather than an empty list: on a cold launch the Hive
        // stream has not delivered yet, and "Nothing due" would be a claim the
        // app cannot back at that point.
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
    );
  }
}

class _Rows extends ConsumerWidget {
  const _Rows({
    required this.entries,
    required this.reminders,
    required this.now,
  });

  final List<AgendaEntry> entries;

  /// Kept alongside [entries] so a tapped reminder row can hand the form sheet
  /// the record it is editing. [AgendaEntry] is flattened for drawing and does
  /// not carry one.
  final List<Reminder> reminders;

  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (entries.isEmpty) {
      return const HomeCardNote(message: 'Nothing due today.');
    }

    final shown = entries.take(_shortlistLength).toList(growable: false);
    final hidden = entries.length - shown.length;

    void openReminder(String id) {
      final match = reminders.where((r) => r.id == id).firstOrNull;
      if (match != null) showReminderFormSheet(context, existing: match);
    }

    return Column(
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          _AgendaRow(
            entry: shown[i],
            now: now,
            onTap: switch (shown[i].kind) {
              AgendaKind.task => () => ref
                  .read(taskListProvider.notifier)
                  .toggleCompleted(shown[i].sourceId),
              AgendaKind.reminder => () => openReminder(shown[i].sourceId),
            },
          ),
          // Only between rows, not under the last one — the same gating Study
          // time and Nutrition use.
          if (i < shown.length - 1)
            Divider(color: context.palette.hairline, height: 20),
        ],
        if (hidden > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              // Reminders live as a segment of the Tasks screen rather than a
              // destination of their own, so this is true of both kinds.
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

/// One row: a ring, a title, and — on a late reminder only — the time it was
/// due.
class _AgendaRow extends StatelessWidget {
  const _AgendaRow({
    required this.entry,
    required this.now,
    required this.onTap,
  });

  final AgendaEntry entry;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isTask = entry.kind == AgendaKind.task;
    final isDone = entry.isCompleted;
    final ring = isTask ? palette.taskRing : palette.reminderRing;

    // Only a late reminder explains itself. A due time under every row would
    // roughly double the card's height, and a task's own card has never shown
    // one — the Tasks screen is where times belong.
    final bool showDue = !isTask && entry.isOverdue(now);

    return Semantics(
      button: true,
      // A reminder has nothing to tick, so it must not announce a checkbox
      // state — `checked:` on it would tell a screen reader it is unfinished.
      checked: isTask ? isDone : null,
      label: entry.title,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          // The whole row is the control, so the whole row carries the touch
          // target — padded out to the platform minimum rather than any glyph
          // inside it being grown to meet it. A two-line overdue reminder is
          // already taller than this and simply keeps its own height.
          constraints: const BoxConstraints(minHeight: minTouchTarget),
          child: Row(
            children: [
              AnimatedContainer(
                key: ValueKey('ring-${entry.id}'),
                duration: context.motion.fast,
                curve: AppMotion.spring,
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isDone ? ring : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(color: ring, width: 1.4),
                ),
                child: isDone
                    // Not `onAccent`. White on #FFE100 measures about 1.1:1 —
                    // the ground is the only readable ink on this fill.
                    ? Icon(PhLight.check, size: 13, color: palette.background)
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // Struck through rather than removed: a completed task
                      // leaves the Today filter on the repository's next
                      // event, and the strike is what makes that read as a
                      // tick rather than a row vanishing under the finger.
                      style: context.typography
                          .ui(
                            size: 13.5,
                            color: isDone
                                ? palette.textMuted
                                : palette.textPrimary,
                          )
                          .copyWith(
                            decoration:
                                isDone ? TextDecoration.lineThrough : null,
                            decorationColor: palette.textMuted,
                          ),
                    ),
                    if (showDue) ...[
                      const SizedBox(height: 2),
                      Text(
                        formatReminderDueLabel(entry.due, now),
                        key: ValueKey('due-${entry.id}'),
                        style: context.typography.ui(
                          size: 11,
                          weight: FontWeight.w600,
                          // The row's own red, not `danger`: one red per row.
                          // A #FF0000 ring over #EF4444 text reads as two
                          // near-misses rather than one signal.
                          color: palette.reminderRing,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
