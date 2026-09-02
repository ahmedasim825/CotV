import 'package:flutter/material.dart';

import '../../../models/journal_entry.dart';
import '../../../models/journal_view.dart';
import '../../components/components.dart';
import '../../format/time_format.dart';
import '../../theme/app_theme.dart';
import 'mood_picker.dart';
import 'tag_chip.dart';

const List<String> _monthAbbreviations = [
  'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
  'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
];

/// One entry in the journal list: a date block, the mood it was written in,
/// a plain-text preview of the markdown body, and its tags.
class JournalEntryCard extends StatelessWidget {
  const JournalEntryCard({
    super.key,
    required this.entry,
    required this.today,
    required this.onTap,
  });

  final JournalEntry entry;

  /// Midnight-normalized "now", so the card can say Today/Yesterday.
  final DateTime today;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final entryDay =
        DateTime(entry.date.year, entry.date.month, entry.date.day);
    final relative = relativeDayName(entryDay, today);
    final excerpt = journalExcerpt(entry.content);

    return CustomCard(
      onTap: onTap,
      semanticLabel: '${relative ?? formatFullDate(entry.date)}, '
          'mood ${entry.mood.label}. ${excerpt.isEmpty ? 'Empty entry' : excerpt}',
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DateBlock(date: entryDay),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        relative ?? formatFullDate(entry.date),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.typography.ui(
                          size: 13.5,
                          weight: FontWeight.w600,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    MoodGlyph(mood: entry.mood, size: 30),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  excerpt.isEmpty ? 'Empty entry' : excerpt,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: context.typography.ui(
                    size: 13,
                    color: excerpt.isEmpty
                        ? palette.textMuted
                        : palette.textSecondary,
                    weight: FontWeight.w400,
                    height: 1.5,
                  ),
                ),
                if (entry.tags.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final tag in entry.tags) TagChip(label: tag),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The day-and-month stamp down the left edge.
class _DateBlock extends StatelessWidget {
  const _DateBlock({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      width: 52,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: palette.glassFill,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            date.day.toString().padLeft(2, '0'),
            style: context.typography.display(
              size: 22,
              weight: FontWeight.w500,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _monthAbbreviations[date.month - 1],
            style: context.typography.eyebrow(color: palette.accent),
          ),
        ],
      ),
    );
  }
}
