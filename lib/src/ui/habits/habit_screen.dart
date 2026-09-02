import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/habit.dart';
import '../../models/habit_view.dart';
import '../../providers/clock_providers.dart';
import '../../providers/habit_providers.dart';
import '../components/components.dart';
import '../responsive/breakpoints.dart';
import '../theme/app_theme.dart';
import '../widgets/ph_light_icons.dart';
import '../widgets/status_card.dart';
import 'habit_form_sheet.dart';
import 'widgets/habit_tile.dart';

/// The habit tracker: a summary strip over a grid of tap-to-complete tiles.
///
/// Every mutation goes through [HabitListNotifier] into [HabitRepository],
/// which writes to Hive; the box's change stream feeds [habitListProvider]
/// straight back here, so this screen keeps no copy of the list and the
/// streak shown is always the one the repository computed.
class HabitScreen extends ConsumerWidget {
  const HabitScreen({super.key, this.showFab = true});

  /// Suppressed when a wider layout hosts a single shared add button.
  final bool showFab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AdaptiveLayout(
      builder: (context, windowSize) {
        final habitsAsync = ref.watch(habitListProvider);
        final now = ref.watch(currentMinuteProvider);
        final padding = windowSize.pagePadding;

        return Stack(
          children: [
            habitsAsync.when(
              data: (habits) => _HabitBody(
                habits: sortHabits(habits, now),
                summary: summarizeHabits(habits, now),
                now: now,
                windowSize: windowSize,
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
                  message: 'Could not load habits: $error',
                  tone: StatusTone.error,
                ),
              ),
            ),
            if (showFab)
              Positioned(
                right: padding,
                bottom: 20 + MediaQuery.paddingOf(context).bottom,
                child: const QuickAddHabitButton(),
              ),
          ],
        );
      },
    );
  }
}

class _HabitBody extends ConsumerWidget {
  const _HabitBody({
    required this.habits,
    required this.summary,
    required this.now,
    required this.windowSize,
  });

  final List<Habit> habits;
  final HabitSummary summary;
  final DateTime now;
  final WindowSize windowSize;

  /// Wider windows get more columns rather than wider tiles: a habit tile
  /// is a fixed stack of control, title and history, and stretching it just
  /// leaves a band of empty card.
  int get _columns {
    switch (windowSize) {
      case WindowSize.compact:
        return 2;
      case WindowSize.medium:
        return 3;
      case WindowSize.expanded:
        return 4;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final padding = windowSize.pagePadding;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        padding,
        12,
        padding,
        // Clears the add button and the home indicator.
        96 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        const SectionHeader(
          eyebrow: 'CONSISTENCY',
          title: 'Habits',
        ),
        const SizedBox(height: 18),
        _SummaryStrip(summary: summary),
        const SizedBox(height: 20),
        if (habits.isEmpty)
          const _EmptyState()
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: habits.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _columns,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              // A fixed extent rather than an aspect ratio, so the tile's
              // fixed content stack cannot overflow on a narrow phone.
              mainAxisExtent: 178,
            ),
            itemBuilder: (context, index) {
              final habit = habits[index];
              return HabitTile(
                key: ValueKey(habit.id),
                habit: habit,
                now: now,
                onToggle: () {
                  // For a weekly habit the stored completion may be an
                  // earlier day in the same week; toggling has to remove
                  // that date, not add today's on top of it.
                  final recorded = habit.completionDateIn(now) ?? now;
                  ref
                      .read(habitListProvider.notifier)
                      .toggleCompletedOn(habit.id, recorded);
                },
                onEdit: () => showHabitFormSheet(context, existing: habit),
              );
            },
          ),
      ],
    );
  }
}

/// Today's progress plus the two figures that make a streak feel worth
/// keeping.
class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.summary});

  final HabitSummary summary;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return CustomCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _Stat(
                  value: summary.isEmpty
                      ? '—'
                      : '${summary.completedThisPeriod}/${summary.total}',
                  label: 'Done now',
                ),
              ),
              _StatDivider(),
              Expanded(
                child: _Stat(
                  value: '${summary.bestStreak}',
                  label: 'Best streak',
                  tint: summary.bestStreak > 0 ? palette.secondary : null,
                ),
              ),
              _StatDivider(),
              Expanded(
                child: _Stat(
                  value: '${summary.activeStreaks}',
                  label: 'Running',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: summary.completionRate),
              duration: AppMotion.base,
              curve: AppMotion.spring,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 6,
                backgroundColor: palette.glassFill,
                valueColor: AlwaysStoppedAnimation(palette.accent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.tint});

  final String value;
  final String label;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: context.typography.display(
            size: 26,
            weight: FontWeight.w500,
            color: tint ?? palette.textPrimary,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label.toUpperCase(),
          style: context.typography.eyebrow(color: palette.textMuted),
        ),
      ],
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      color: context.palette.hairline,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.glassFill,
              shape: BoxShape.circle,
            ),
            child: Icon(PhLight.target, size: 24, color: palette.accent),
          ),
          const SizedBox(height: 18),
          Text(
            'No habits yet.\nAdd one and it starts counting from today.',
            textAlign: TextAlign.center,
            style: context.typography.ui(
              size: 14,
              color: palette.textMuted,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// The quick-add button. Exposed so a wider layout can host one shared
/// button above several panes.
class QuickAddHabitButton extends StatelessWidget {
  const QuickAddHabitButton({super.key});

  @override
  Widget build(BuildContext context) {
    return PrimaryButton(
      label: 'Habit',
      icon: PhLight.plus,
      onPressed: () => showHabitFormSheet(context),
    );
  }
}
