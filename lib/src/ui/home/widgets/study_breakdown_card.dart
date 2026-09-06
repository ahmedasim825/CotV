import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/study_view.dart';
import '../../../models/subject.dart';
import '../../../providers/study_providers.dart';
import '../../components/components.dart';
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

    return CustomCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhLight.brain, size: 18, color: palette.accent),
              const SizedBox(width: 10),
              Text(
                'Study today',
                style: context.typography.ui(size: 15, weight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 18),
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
                    style: context.typography.display(size: 30),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'of ${formatStudyMinutes(_dailyTargetMinutes)}',
                    style: context.typography.ui(
                      size: 11,
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
                total: total,
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
    required this.total,
    required this.color,
  });

  final SubjectStudyTotal subject;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final minutes = subject.todayMinutes;
    final share = total == 0 ? 0.0 : minutes / total;

    return Semantics(
      label: '${subject.subjectName}, ${formatStudyMinutes(minutes)}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                  style: context.typography.ui(size: 12.5),
                ),
              ),
              Text(
                formatStudyMinutes(minutes),
                style: context.typography.ui(
                  size: 12.5,
                  weight: FontWeight.w600,
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: share,
              minHeight: 5,
              backgroundColor: palette.glassFill,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}
