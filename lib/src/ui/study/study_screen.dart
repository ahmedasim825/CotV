import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../format/time_format.dart' show startOfDay;
import '../../models/study_view.dart';
import '../../models/subject.dart';
import '../../providers/clock_providers.dart';
import '../../providers/study_providers.dart';
import '../components/components.dart';
import '../responsive/breakpoints.dart';
import '../theme/app_theme.dart';
import '../widgets/ph_light_icons.dart';
import '../widgets/status_card.dart';
import 'start_session.dart';
import 'subject_colors.dart';
import 'widgets/study_month_grid.dart';
import 'widgets/study_timer_card.dart';
import 'widgets/subject_form_sheet.dart';

/// The study tracker: today against the day's goal beside the month at a
/// glance, over a list of tap-to-start subjects.
///
/// Every mutation goes through [StudyNotifier] and the two study
/// repositories into Hive; the box change streams feed straight back here,
/// so this screen keeps no copy of the totals it shows.
class StudyScreen extends ConsumerWidget {
  const StudyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AdaptiveLayout(
      builder: (context, windowSize) {
        final subjectsAsync = ref.watch(subjectListProvider);

        return subjectsAsync.when(
          data: (subjects) =>
              _StudyBody(subjects: subjects, windowSize: windowSize),
          loading: () => Center(
            child: CircularProgressIndicator(
              color: context.palette.accent,
              strokeWidth: 2.5,
            ),
          ),
          error: (error, _) => Padding(
            padding: EdgeInsets.all(windowSize.pagePadding),
            child: StatusCard(
              message: 'Could not load subjects: $error',
              tone: StatusTone.error,
            ),
          ),
        );
      },
    );
  }
}

class _StudyBody extends ConsumerWidget {
  const _StudyBody({required this.subjects, required this.windowSize});

  final List<Subject> subjects;
  final WindowSize windowSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final padding = windowSize.pagePadding;
    final summary = ref.watch(studySummaryProvider);
    final study = ref.watch(studyProvider);
    // Day granularity is all this needs: `now` reaches only `_TodayLog`,
    // which normalises it to a day. Watching the minute rebuilt this whole
    // `ListView` — every subject row, the timer card and the month grid —
    // once a minute for a value that changes at midnight.
    final now = ref.watch(currentDayProvider);
    final ordered = sortSubjects(subjects, summary);
    final isRunning = study.phase != StudyPhase.idle;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        padding,
        12,
        padding,
        // Clears the home indicator. No floating button to clear any more —
        // adding a subject is the control in the Subjects header.
        32 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        SectionHeader(
          title: 'Study',
          trailing: _HeaderAction(
            icon: PhLight.timer,
            label: 'Start a study session',
            tint: isRunning ? context.palette.accent : null,
            onTap: () => startAnySession(context, ref),
          ),
        ),
        const SizedBox(height: 24),
        if (isRunning) ...[
          StudyTimerCard(accent: studyAccentFor(context, ref)),
          const SizedBox(height: 24),
        ],
        _TodayRow(
          todayMinutes: summary.todayMinutes,
          twoUp: !windowSize.isCompact,
        ),
        const SizedBox(height: 32),
        SectionHeader(
          title: 'Subjects',
          titleSize: 26,
          trailing: _HeaderAction(
            icon: PhLight.plus,
            label: 'Add a subject',
            onTap: () => showSubjectFormSheet(context),
          ),
        ),
        const SizedBox(height: 14),
        if (ordered.isEmpty)
          const _EmptyState()
        else
          for (var i = 0; i < ordered.length; i++) ...[
            if (i != 0) const SizedBox(height: 10),
            _SubjectRow(
              key: ValueKey(ordered[i].id),
              subject: ordered[i],
              todayMinutes: summary.totalFor(ordered[i].id)?.todayMinutes ?? 0,
              isRunning: study.session?.subjectId == ordered[i].id,
              onStart: () => startSessionFor(context, ref, ordered[i]),
              onEdit: () => showSubjectFormSheet(context, existing: ordered[i]),
            ),
          ],
        if (summary.todaySessions > 0) ...[
          const SizedBox(height: 28),
          _TodayLog(now: now),
        ],
      ],
    );
  }

}

/// Today against the day's goal, beside the month a square at a time.
class _TodayRow extends StatelessWidget {
  const _TodayRow({required this.todayMinutes, required this.twoUp});

  final int todayMinutes;
  final bool twoUp;

  @override
  Widget build(BuildContext context) {
    final ring = _TodayRing(minutes: todayMinutes);

    // Stacked rather than squeezed: the grid is a fixed 162pt of squares and
    // the ring a fixed 150, and a narrow pane cannot seat both.
    if (!twoUp) {
      return Column(
        children: [
          ring,
          const SizedBox(height: 28),
          const StudyMonthGrid(),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: Center(child: ring)),
        const SizedBox(width: 24),
        const Expanded(child: Center(child: StudyMonthGrid())),
      ],
    );
  }
}

/// Minutes studied today, as a fraction of [dailyStudyGoalMinutes].
class _TodayRing extends StatelessWidget {
  const _TodayRing({required this.minutes});

  final int minutes;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return CountdownRing(
      progress: minutes / dailyStudyGoalMinutes,
      accent: palette.accent,
      diameter: 150,
      strokeWidth: 12,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            formatStudyMinutes(minutes),
            maxLines: 1,
            style: context.typography.display(
              size: 24,
              weight: FontWeight.w700,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'of ${dailyStudyGoalMinutes ~/ 60}h',
            style: context.typography.ui(size: 11.5, color: palette.textMuted),
          ),
        ],
      ),
    );
  }
}

/// A circular control for a [SectionHeader]'s trailing slot.
class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.tint,
  });

  final IconData icon;

  /// Doubles as the tooltip and the screen-reader name, since the control is
  /// a glyph and nothing else.
  final String label;

  final VoidCallback onTap;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final color = tint ?? context.palette.textSecondary;

    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 19, color: color),
          ),
        ),
      ),
    );
  }
}

/// One subject: tap to start a block, long-press or the pencil to edit.
class _SubjectRow extends StatefulWidget {
  const _SubjectRow({
    super.key,
    required this.subject,
    required this.todayMinutes,
    required this.isRunning,
    required this.onStart,
    required this.onEdit,
  });

  final Subject subject;
  final int todayMinutes;
  final bool isRunning;
  final VoidCallback onStart;
  final VoidCallback onEdit;

  @override
  State<_SubjectRow> createState() => _SubjectRowState();
}

class _SubjectRowState extends State<_SubjectRow> {
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered != value) setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = subjectColor(widget.subject.colorValue);

    return Semantics(
      button: true,
      label: widget.isRunning
          ? '${widget.subject.name}, session running'
          : '${widget.subject.name}, '
              '${formatStudyMinutes(widget.todayMinutes)} today. '
              'Start a session.',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: GestureDetector(
          onTap: widget.isRunning ? null : widget.onStart,
          onLongPress: widget.onEdit,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: context.motion.hover,
            curve: Curves.easeOut,
            height: 56,
            padding: const EdgeInsets.only(left: 18, right: 12),
            decoration: BoxDecoration(
              // The subject's colour washed over the surface rather than laid
              // on top of it, so eight swatches make eight legible rows
              // instead of eight differently-readable ones.
              color: Color.alphaBlend(
                accent.withValues(alpha: widget.isRunning ? 0.24 : 0.14),
                palette.surface,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: widget.isRunning ? accent : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.subject.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.typography.ui(
                      size: 15,
                      weight: FontWeight.w600,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
                if (widget.isRunning) ...[
                  Text(
                    'RUNNING',
                    style: context.typography.eyebrow(color: accent),
                  ),
                  const SizedBox(width: 12),
                ],
                Text(
                  formatStudyMinutes(widget.todayMinutes),
                  style: context.typography.ui(
                    size: 13,
                    weight: FontWeight.w600,
                    color: widget.todayMinutes > 0
                        ? palette.textPrimary
                        : palette.textMuted,
                  ),
                ),
                // Always takes its space, so revealing it does not shuffle
                // the number beside it.
                AnimatedOpacity(
                  opacity: _hovered ? 1 : 0,
                  duration: context.motion.hover,
                  curve: Curves.easeOut,
                  child: IgnorePointer(
                    ignoring: !_hovered,
                    child: Tooltip(
                      message: 'Edit',
                      child: InkWell(
                        onTap: widget.onEdit,
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 30,
                          height: 30,
                          child: Icon(
                            PhLight.pencilSimple,
                            size: 16,
                            color: palette.textMuted,
                          ),
                        ),
                      ),
                    ),
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
    final today = startOfDay(now);
    final logs = [
      for (final log in ref.watch(studyLogListProvider).value ?? const [])
        if (startOfDay(log.timestamp) == today) log,
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
