import 'package:flutter/material.dart';

import '../../components/components.dart';
import '../../study/subject_colors.dart';
import '../../study/widgets/study_timer_card.dart' show CountdownRing;
import '../../theme/app_theme.dart';
import '../../widgets/ph_light_icons.dart';

/// One subject's share of the day. Mock only — the real numbers will come
/// from `studyLogRepository` totals.
class _SubjectSlice {
  const _SubjectSlice(this.name, this.minutes, this.colorValue);

  final String name;
  final int minutes;
  final int colorValue;
}

const int _dailyTargetMinutes = 480;

const List<_SubjectSlice> _mockSubjects = [
  _SubjectSlice('Anatomy', 180, 0xFF7B8FCB),
  _SubjectSlice('Pathology', 150, 0xFF34D399),
  _SubjectSlice('Pharmacology', 30, 0xFFE5B769),
];

/// Hours studied today, as a ring plus a per-subject breakdown.
class StudyBreakdownCard extends StatelessWidget {
  const StudyBreakdownCard({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final total = _mockSubjects.fold<int>(0, (sum, s) => sum + s.minutes);

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
                    _hours(total),
                    style: context.typography.display(size: 30),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'of ${_hours(_dailyTargetMinutes)}',
                    style: context.typography.ui(
                      size: 11,
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          for (var i = 0; i < _mockSubjects.length; i++) ...[
            _SubjectRow(subject: _mockSubjects[i], total: total),
            if (i < _mockSubjects.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _SubjectRow extends StatelessWidget {
  const _SubjectRow({required this.subject, required this.total});

  final _SubjectSlice subject;
  final int total;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = subjectColor(subject.colorValue);
    final share = total == 0 ? 0.0 : subject.minutes / total;

    return Semantics(
      label: '${subject.name}, ${_hours(subject.minutes)}',
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
                  subject.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.typography.ui(size: 12.5),
                ),
              ),
              Text(
                _hours(subject.minutes),
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

/// `3h`, `2h 30m`, `30m` — the same shape the study screen uses, kept local
/// because this card counts a whole day rather than one session.
String _hours(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}
