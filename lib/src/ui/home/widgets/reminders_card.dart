import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/clock_providers.dart';
import '../../../providers/reminder_providers.dart';
import '../../format/time_format.dart';
import '../../tasks/reminder_form_sheet.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ph_light_icons.dart';
import 'home_card_note.dart';

/// Dated prompts, soonest first, overdue ones in red.
class RemindersCard extends ConsumerWidget {
  const RemindersCard({super.key});

  static const int _shortlistLength = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    // Watched, not `DateTime.now()`: a reminder crossing its due instant
    // while the card is on screen has to flip to danger by itself. The task
    // list next door already keys off this provider for the same reason.
    final now = ref.watch(currentMinuteProvider);
    final reminders = [...ref.watch(reminderListProvider)]
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));

    return HomeCardFrame(
      title: 'Reminders',
      onEdit: () => showReminderFormSheet(context),
      child: reminders.isEmpty
          ? const HomeCardNote(
              icon: PhLight.bellSimple,
              message: 'No reminders',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final reminder
                    in reminders.take(_shortlistLength)) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Icon(PhLight.circle,
                            size: 16, color: palette.textMuted),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              reminder.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.typography.ui(
                                size: 15,
                                weight: FontWeight.w600,
                                color: palette.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              // `formatReminderDueLabel`, not
                              // `formatDueLabel`: it's the one that produces
                              // the `Yesterday, 03:00` / `27/07/2026, 20:00`
                              // shape a reminder's always-present time needs.
                              formatReminderDueLabel(reminder.dueAt, now),
                              key: ValueKey('due-${reminder.id}'),
                              style: context.typography.ui(
                                size: 11,
                                weight: FontWeight.w600,
                                color: reminder.isOverdue(now)
                                    ? palette.danger
                                    : palette.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Divider(color: palette.hairline, height: 20),
                ],
              ],
            ),
    );
  }
}
