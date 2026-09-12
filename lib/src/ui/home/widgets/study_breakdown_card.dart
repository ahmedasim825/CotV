import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/study_view.dart';
import '../../../models/subject.dart';
import '../../../providers/study_providers.dart';
import '../../study/subject_colors.dart';
import '../../study/widgets/study_timer_card.dart' show CountdownRing;
import '../../theme/app_theme.dart';
import '../../widgets/ph_light_icons.dart';
import 'home_card_note.dart';

/// What a full day of study looks like on the ring.
///
/// A target rather than a measurement, so it is a constant on purpose:
/// the stored user settings carry no study goal to read it from, and the
/// ring needs something to be a fraction of.
const int _dailyTargetMinutes = 480;

/// Hours studied today, as a ring plus a per-subject breakdown.
///
/// Both come from [studySummaryProvider], the same transform the Study
/// screen and Milo's context block read, so the dashboard cannot quote a
/// different total than the screen it links to.
class StudyBreakdownCard extends ConsumerWidget {
  const StudyBreakdownCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final summary = ref.watch(studySummaryProvider);
    final subjects = ref.watch(subjectListProvider).value ?? const <Subject>[];

    final total = summary.todayMinutes;
    final today = [
      for (final entry in summary.bySubject)
        if (entry.todayMinutes > 0) entry,
    ];

    // Colours live on the subject, not on the totals: a log keeps the name
    // of a subject that has since been deleted, so a row can outlive the
    // swatch it was drawn in.
    final colors = {
      for (final subject in subjects) subject.id: subjectColor(subject.colorValue),
    };

    return HomeCardFrame(
      title: 'Study time',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: CountdownRing(
              progress: total / _dailyTargetMinutes,
              accent: palette.accent,
              diameter: 132,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatStudyMinutes(total),
                    style: context.typography.display(
                      size: 22,
                      weight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'of ${_dailyTargetMinutes ~/ 60}h',
                    style: context.typography.ui(
                      size: 10.5,
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (today.isEmpty)
            const HomeCardNote(
              icon: PhLight.timer,
              message: 'Nothing logged today',
              padding: EdgeInsets.only(top: 20),
            )
          else ...[
            const SizedBox(height: 20),
            for (var i = 0; i < today.length; i++) ...[
              _SubjectRow(
                subject: today[i],
                color: colors[today[i].subjectId] ?? palette.accent,
              ),
              if (i < today.length - 1) const SizedBox(height: 12),
            ],
          ],
        ],
      ),
    );
  }
}

class _SubjectRow extends StatelessWidget {
  const _SubjectRow({
    required this.subject,
    required this.color,
  });

  final SubjectStudyTotal subject;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final minutes = subject.todayMinutes;

    return Semantics(
      label: '${subject.subjectName}, ${formatStudyMinutes(minutes)}',
      excludeSemantics: true,
      // No MeterBar: the mock's legend rows are a dot, a coloured name and a
      // coloured duration — the bar isn't part of it, and `total` (the share
      // it needed) goes with it.
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              subject.subjectName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.typography.ui(size: 12.5, color: color),
            ),
          ),
          Text(
            formatStudyMinutes(minutes),
            style: context.typography.ui(
              size: 12.5,
              weight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
