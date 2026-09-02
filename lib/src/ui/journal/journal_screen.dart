import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/journal_entry.dart';
import '../../models/journal_view.dart';
import '../../providers/journal_filter_providers.dart';
import '../../providers/journal_providers.dart';
import '../components/components.dart';
import '../responsive/breakpoints.dart';
import '../theme/app_theme.dart';
import '../widgets/ph_light_icons.dart';
import '../widgets/status_card.dart';
import 'journal_writer_screen.dart';
import 'widgets/journal_entry_card.dart';
import 'widgets/mood_picker.dart';
import 'widgets/tag_chip.dart';

/// The journal: search and filters over a reverse-chronological list of
/// entries, each opening into the full-screen writer.
///
/// Filter state lives in providers rather than local state so it survives
/// switching tabs and coming back, matching how the task list behaves.
class JournalScreen extends ConsumerWidget {
  const JournalScreen({super.key, this.showFab = true});

  final bool showFab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AdaptiveLayout(
      builder: (context, windowSize) {
        final entriesAsync = ref.watch(visibleJournalEntriesProvider);
        final padding = windowSize.pagePadding;

        return Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(padding, 12, padding, 0),
                  child: const SectionHeader(
                    eyebrow: 'REFLECTION',
                    title: 'Journal',
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: padding),
                  child: const _SearchField(),
                ),
                const SizedBox(height: 12),
                _MoodFilterRow(horizontalPadding: padding),
                const _TagFilterRow(),
                const SizedBox(height: 8),
                Expanded(
                  child: entriesAsync.when(
                    data: (entries) => entries.isEmpty
                        ? _EmptyState(padding: padding)
                        : _EntryList(entries: entries, padding: padding),
                    loading: () => Center(
                      child: CircularProgressIndicator(
                        color: context.palette.accent,
                        strokeWidth: 2.5,
                      ),
                    ),
                    error: (error, _) => Padding(
                      padding: EdgeInsets.all(padding),
                      child: StatusCard(
                        message: 'Could not load the journal: $error',
                        tone: StatusTone.error,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (showFab)
              Positioned(
                right: padding,
                bottom: 20 + MediaQuery.paddingOf(context).bottom,
                child: const QuickWriteButton(),
              ),
          ],
        );
      },
    );
  }
}

class _SearchField extends ConsumerStatefulWidget {
  const _SearchField();

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    // Seeded from the provider so a query survives leaving the tab and
    // coming back, which is where the text field itself is rebuilt.
    _controller = TextEditingController(text: ref.read(journalQueryProvider));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final query = ref.watch(journalQueryProvider);

    return TextField(
      controller: _controller,
      textInputAction: TextInputAction.search,
      style: context.typography.ui(size: 14),
      onChanged: ref.read(journalQueryProvider.notifier).set,
      decoration: appInputDecoration(
        context,
        hint: 'Search entries and tags',
        prefixIcon: Icon(
          PhLight.magnifyingGlass,
          size: 17,
          color: palette.textMuted,
        ),
        suffixIcon: query.isEmpty
            ? null
            : IconButton(
                icon: Icon(PhLight.xCircle, size: 17, color: palette.textMuted),
                tooltip: 'Clear search',
                onPressed: () {
                  _controller.clear();
                  ref.read(journalQueryProvider.notifier).clear();
                },
              ),
      ),
    );
  }
}

class _MoodFilterRow extends ConsumerWidget {
  const _MoodFilterRow({required this.horizontalPadding});

  final double horizontalPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final selected = ref.watch(journalMoodFilterProvider);

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        itemCount: orderedMoods.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final mood = orderedMoods[index];
          final isSelected = mood == selected;
          final color = colorForMood(mood, palette);

          return Semantics(
            button: true,
            selected: isSelected,
            label: 'Filter by ${mood.label} mood',
            child: GestureDetector(
              onTap: () =>
                  ref.read(journalMoodFilterProvider.notifier).toggle(mood),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: AppMotion.fast,
                curve: AppMotion.spring,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected
                      ? color.withValues(alpha: 0.16)
                      : palette.glassFill,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isSelected ? color : palette.glassBorder,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      iconForMood(mood),
                      size: 14,
                      color: isSelected ? color : palette.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      mood.label,
                      style: context.typography.ui(
                        size: 12.5,
                        weight: FontWeight.w600,
                        color: isSelected ? color : palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TagFilterRow extends ConsumerWidget {
  const _TagFilterRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = ref.watch(journalTagsProvider);
    if (tags.isEmpty) return const SizedBox.shrink();

    final selected = ref.watch(journalTagFilterProvider);
    final padding = windowSizeOf(context).pagePadding;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: SizedBox(
        height: 30,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: padding),
          itemCount: tags.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final tag = tags[index];
            return TagChip(
              label: tag,
              selected: tag == selected,
              onTap: () =>
                  ref.read(journalTagFilterProvider.notifier).toggle(tag),
            );
          },
        ),
      ),
    );
  }
}

class _EntryList extends ConsumerWidget {
  const _EntryList({required this.entries, required this.padding});

  final List<JournalEntry> entries;
  final double padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        padding,
        6,
        padding,
        // Clears the write button and the home indicator.
        96 + MediaQuery.paddingOf(context).bottom,
      ),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _DismissibleEntry(
          key: ValueKey(entry.id),
          entry: entry,
          today: today,
        );
      },
    );
  }
}

/// Swipe-to-delete with undo.
///
/// The delete is committed immediately rather than held behind a timer, so
/// the list and the database never disagree; undo re-adds the entry from
/// the copy captured before the delete.
class _DismissibleEntry extends ConsumerWidget {
  const _DismissibleEntry({
    super.key,
    required this.entry,
    required this.today,
  });

  final JournalEntry entry;
  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messenger = ScaffoldMessenger.of(context);
    // Captured while this context is mounted, since the snack bar is built
    // after the delete has been awaited.
    final palette = context.palette;
    final typography = context.typography;

    return Dismissible(
      key: ValueKey('dismiss:${entry.id}'),
      direction: DismissDirection.endToStart,
      // Deliberately more than the default 0.4: losing writing to a stray
      // swipe should take a decisive gesture.
      dismissThresholds: const {DismissDirection.endToStart: 0.55},
      background: const _DeleteBackground(),
      onDismissed: (_) async {
        final removed = entry;
        await ref.read(journalListProvider.notifier).deleteEntry(removed.id);

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
                'Entry deleted',
                style: typography.ui(size: 13),
              ),
              action: SnackBarAction(
                label: 'Undo',
                textColor: palette.accent,
                onPressed: () =>
                    ref.read(journalListProvider.notifier).addEntry(removed),
              ),
            ),
          );
      },
      child: JournalEntryCard(
        entry: entry,
        today: today,
        onTap: () => openJournalWriter(context, existing: entry),
      ),
    );
  }
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 24),
      decoration: BoxDecoration(
        color: palette.danger.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Icon(PhLight.trash, size: 18, color: palette.danger),
    );
  }
}

class _EmptyState extends ConsumerWidget {
  const _EmptyState({required this.padding});

  final double padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final hasFilters = ref.watch(journalHasFiltersProvider);

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
                color: palette.glassFill,
                shape: BoxShape.circle,
              ),
              child: Icon(
                hasFilters ? PhLight.magnifyingGlass : PhLight.bookOpen,
                size: 24,
                color: palette.accent,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              hasFilters
                  ? 'No entries match these filters.'
                  : 'Nothing written yet.\nThe first entry is the hard one.',
              textAlign: TextAlign.center,
              style: context.typography.ui(
                size: 14,
                color: palette.textMuted,
                height: 1.5,
              ),
            ),
            if (hasFilters) ...[
              const SizedBox(height: 18),
              PrimaryButton(
                label: 'Clear filters',
                icon: PhLight.x,
                variant: ButtonVariant.outline,
                size: ButtonSize.compact,
                onPressed: () {
                  ref.read(journalQueryProvider.notifier).clear();
                  ref.read(journalTagFilterProvider.notifier).clear();
                  ref.read(journalMoodFilterProvider.notifier).clear();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Opens today's entry if one exists, otherwise starts a new one — so the
/// button can never create a second entry for the same day.
class QuickWriteButton extends ConsumerWidget {
  const QuickWriteButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PrimaryButton(
      label: 'Write',
      icon: PhLight.notePencil,
      onPressed: () {
        final today = DateTime.now();
        final existing =
            ref.read(journalListProvider.notifier).getByDate(today);
        openJournalWriter(context, existing: existing, initialDate: today);
      },
    );
  }
}
