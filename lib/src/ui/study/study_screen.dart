import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/habit_view.dart' show normalizeDay;
import '../../models/study_view.dart';
import '../../models/subject.dart';
import '../../providers/clock_providers.dart';
import '../../providers/study_providers.dart';
import '../components/components.dart';
import '../responsive/breakpoints.dart';
import '../settings/option_picker_sheet.dart';
import '../theme/app_theme.dart';
import '../widgets/ph_light_icons.dart';
import '../widgets/status_card.dart';
import 'subject_colors.dart';
import 'widgets/study_timer_card.dart';
import 'widgets/subject_form_sheet.dart';

/// The session lengths offered when a subject is tapped.
///
/// Two Pomodoro-shaped options and three block lengths, rather than a free
/// number field: picking is one tap, and a study block is chosen from habit
/// far more often than it is calculated.
const List<int> studyDurationMinutes = [15, 25, 45, 60, 90];

/// The study tracker: a session card when one is running, over a summary
/// strip and a grid of tap-to-start subjects.
///
/// Every mutation goes through [StudyNotifier] and the two study
/// repositories into Hive; the box change streams feed straight back here,
/// so this screen keeps no copy of the totals it shows.
class StudyScreen extends ConsumerWidget {
  const StudyScreen({super.key, this.showFab = true});

  /// Suppressed when a wider layout hosts a single shared add button.
  final bool showFab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AdaptiveLayout(
      builder: (context, windowSize) {
        final subjectsAsync = ref.watch(subjectListProvider);
        final padding = windowSize.pagePadding;

        return Stack(
          children: [
            subjectsAsync.when(
              data: (subjects) =>
                  _StudyBody(subjects: subjects, windowSize: windowSize),
              loading: () => Center(
                child: CircularProgressIndicator(
                  color: context.palette.accent,
                  strokeWidth: 2.5,
                ),
              ),
              error: (error, _) => Padding(
                padding: EdgeInsets.all(padding),
                child: StatusCard(
                  message: 'Could not load subjects: $error',
                  tone: StatusTone.error,
                ),
              ),
            ),
            if (showFab)
              Positioned(
                right: padding,
                bottom: 20 + MediaQuery.paddingOf(context).bottom,
                child: const QuickAddSubjectButton(),
              ),
          ],
        );
      },
    );
  }
}

class _StudyBody extends ConsumerWidget {
  const _StudyBody({required this.subjects, required this.windowSize});

  final List<Subject> subjects;
  final WindowSize windowSize;

  /// Wider windows get more columns rather than wider tiles — a subject
  /// tile is a fixed stack of name, total and bar, and stretching it just
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
    final summary = ref.watch(studySummaryProvider);
    final study = ref.watch(studyProvider);
    final now = ref.watch(currentMinuteProvider);
    final ordered = sortSubjects(subjects, summary);

    return ListView(
      padding: EdgeInsets.fromLTRB(
        padding,
        12,
        padding,
        // Clears the add button and the home indicator.
        96 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        const SectionHeader(eyebrow: 'FOCUS', title: 'Study'),
        const SizedBox(height: 18),
        if (study.phase != StudyPhase.idle) ...[
          StudyTimerCard(accent: studyAccentFor(context, ref)),
          const SizedBox(height: 20),
        ],
        _SummaryStrip(summary: summary, now: now),
        const SizedBox(height: 20),
        if (ordered.isEmpty)
          const _EmptyState()
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: ordered.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _columns,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              // A fixed extent rather than an aspect ratio, so the tile's
              // fixed content stack cannot overflow on a narrow phone.
              mainAxisExtent: 146,
            ),
            itemBuilder: (context, index) {
              final subject = ordered[index];
              return _SubjectTile(
                key: ValueKey(subject.id),
                subject: subject,
                total: summary.totalFor(subject.id),
                weekBest: summary.bySubject.isEmpty
                    ? 0
                    : summary.bySubject.first.weekMinutes,
                isRunning: study.session?.subjectId == subject.id,
                onStart: () => _startSession(context, ref, subject),
                onEdit: () => showSubjectFormSheet(context, existing: subject),
              );
            },
          ),
        if (summary.todaySessions > 0) ...[
          const SizedBox(height: 28),
          _TodayLog(now: now),
        ],
      ],
    );
  }

  /// Asks how long, then starts. Returns without starting if the sheet was
  /// dismissed.
  Future<void> _startSession(
    BuildContext context,
    WidgetRef ref,
    Subject subject,
  ) async {
    final minutes = await showOptionPicker<int>(
      context,
      title: subject.name,
      subtitle: 'How long is this block?',
      selected: studyDurationMinutes[1],
      options: [
        for (final value in studyDurationMinutes)
          PickerOption(
            value: value,
            label: formatStudyMinutes(value),
            note: _durationNote(value),
          ),
      ],
    );
    if (minutes == null) return;

    await ref.read(studyProvider.notifier).start(subject, minutes: minutes);
  }

  String? _durationNote(int minutes) {
    switch (minutes) {
      case 25:
        return 'One Pomodoro.';
      case 90:
        return 'A full ultradian block.';
      default:
        return null;
    }
  }
}

/// Today and this week, plus the average that says whether today is
/// actually a good day or just a long one.
class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.summary, required this.now});

  final StudySummary summary;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final average = summary.dailyAverageMinutes(now);

    return CustomCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _Stat(
                  value: formatStudyMinutes(summary.todayMinutes),
                  label: 'Today',
                  tint: summary.todayMinutes > 0 ? palette.accent : null,
                ),
              ),
              const _StatDivider(),
              Expanded(
                child: _Stat(
                  value: formatStudyMinutes(summary.weekMinutes),
                  label: 'This week',
                ),
              ),
              const _StatDivider(),
              Expanded(
                child: _Stat(
                  value: '${summary.todaySessions}',
                  label: 'Sessions',
                ),
              ),
            ],
          ),
          if (!summary.isEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Averaging ${formatStudyMinutes(average)} a day this week.',
              style: context.typography.ui(
                size: 12,
                color: palette.textMuted,
              ),
            ),
          ],
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

/// One subject: tap to start a block, long-press to edit.
class _SubjectTile extends StatelessWidget {
  const _SubjectTile({
    super.key,
    required this.subject,
    required this.total,
    required this.weekBest,
    required this.isRunning,
    required this.onStart,
    required this.onEdit,
  });

  final Subject subject;
  final SubjectStudyTotal? total;

  /// This week's busiest subject, which the bar is drawn relative to — so
  /// the bars compare subjects against each other rather than against an
  /// arbitrary ceiling.
  final int weekBest;

  final bool isRunning;
  final VoidCallback onStart;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = subjectColor(subject.colorValue);
    final today = total?.todayMinutes ?? 0;
    final week = total?.weekMinutes ?? 0;
    final share = weekBest == 0 ? 0.0 : (week / weekBest).clamp(0.0, 1.0);

    return GestureDetector(
      onLongPress: onEdit,
      child: CustomCard(
        accent: accent,
        selected: isRunning,
        onTap: isRunning ? null : onStart,
        semanticLabel: isRunning
            ? '${subject.name}, session running'
            : '${subject.name}, ${formatStudyMinutes(today)} today. '
                'Start a session.',
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isRunning ? PhLight.timer : PhLight.bookOpen,
                    size: 15,
                    color: accent,
                  ),
                ),
                const Spacer(),
                if (isRunning)
                  Text(
                    'RUNNING',
                    style: context.typography.eyebrow(color: accent),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              subject.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.typography.ui(size: 14.5, weight: FontWeight.w600),
            ),
            const Spacer(),
            Text(
              formatStudyMinutes(today),
              style: context.typography.display(
                size: 20,
                weight: FontWeight.w500,
                color: today > 0 ? accent : palette.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Stack(
                children: [
                  Container(height: 4, color: palette.glassFill),
                  LayoutBuilder(
                    builder: (context, constraints) => AnimatedContainer(
                      duration: context.motion.base,
                      curve: AppMotion.spring,
                      height: 4,
                      width: constraints.maxWidth * share,
                      color: accent,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${formatStudyMinutes(week)} this week',
              style: context.typography.ui(size: 10.5, color: palette.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// What was actually studied today, newest first.
class _TodayLog extends ConsumerWidget {
  const _TodayLog({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    // Filtered off the watched list rather than read back through the
    // repository, so a session finishing while this is on screen adds its
    // row without waiting for something else to rebuild it.
    final today = normalizeDay(now);
    final logs = [
      for (final log in ref.watch(studyLogListProvider).value ?? const [])
        if (normalizeDay(log.timestamp) == today) log,
    ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (logs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          eyebrow: 'TODAY',
          title: 'Sessions',
          titleSize: 22,
        ),
        const SizedBox(height: 14),
        CustomCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < logs.length; i++) ...[
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          logs[i].subjectName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.typography.ui(size: 13.5),
                        ),
                      ),
                      Text(
                        formatStudyMinutes(logs[i].durationMinutes),
                        style: context.typography.ui(
                          size: 13.5,
                          weight: FontWeight.w600,
                          color: palette.accent,
                        ),
                      ),
                    ],
                  ),
                ),
                if (i != logs.length - 1)
                  Divider(height: 1, thickness: 1, color: palette.hairline),
              ],
            ],
          ),
        ),
      ],
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
            child: Icon(PhLight.bookOpen, size: 24, color: palette.accent),
          ),
          const SizedBox(height: 18),
          Text(
            'No subjects yet.\nAdd one, then tap it to start a block.',
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
class QuickAddSubjectButton extends StatelessWidget {
  const QuickAddSubjectButton({super.key});

  @override
  Widget build(BuildContext context) {
    return PrimaryButton(
      label: 'Subject',
      icon: PhLight.plus,
      onPressed: () => showSubjectFormSheet(context),
    );
  }
}
