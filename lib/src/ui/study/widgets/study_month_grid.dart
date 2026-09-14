import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/study_view.dart';
import '../../../providers/clock_providers.dart';
import '../../../providers/study_providers.dart';
import '../../format/time_format.dart';
import '../../theme/app_theme.dart';

/// The colour of the month's lightest day of study.
const Color studyHeatQuiet = Color(0xFF9600FF);

/// The colour of the month's busiest day.
const Color studyHeatBusy = Color(0xFF500484);

const double _square = 18;
const double _gap = 6;
const int _columns = 7;

/// The colour one day's square takes.
///
/// Days with time on them ride a ramp from [studyHeatQuiet] to [studyHeatBusy],
/// scaled against the month's own busiest day rather than against a fixed
/// target — so the deep end is always occupied and the grid reads as "how this
/// month was spread", not "how this month compared to a goal".
///
/// A day with nothing on it is off the ramp entirely, and one that has not
/// happened yet is fainter still: an empty square you could have filled should
/// not look the same as one you have not reached.
Color studyDayColor({
  required int minutes,
  required int busiestMinutes,
  required bool isFuture,
  required AppPalette palette,
}) {
  if (minutes <= 0) {
    return palette.textPrimary.withValues(alpha: isFuture ? 0.04 : 0.10);
  }
  final t = busiestMinutes <= 0
      ? 1.0
      : (minutes / busiestMinutes).clamp(0.0, 1.0);
  return Color.lerp(studyHeatQuiet, studyHeatBusy, t)!;
}

/// This month's study, one square a day, reading the providers.
class StudyMonthGrid extends ConsumerWidget {
  const StudyMonthGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StudyMonthGridView(
      month: ref.watch(studyMonthProvider),
      today: ref.watch(currentDayProvider),
    );
  }
}

/// The grid itself.
///
/// Takes its month rather than watching for one, so a test can paint February
/// 2028 without a provider scope or a Hive box behind it.
class StudyMonthGridView extends StatelessWidget {
  const StudyMonthGridView({
    super.key,
    required this.month,
    required this.today,
  });

  final MonthStudy month;

  /// Midnight today. Days after it are drawn as not-yet rather than as empty.
  final DateTime today;

  bool _isFuture(int day) =>
      month.year == today.year &&
      month.month == today.month &&
      day > today.day;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final label = Text(
      monthName(month.month),
      style: context.typography.ui(
        size: 12.5,
        weight: FontWeight.w600,
        color: palette.textSecondary,
      ),
    );

    // A month only ever leaves a tail of 0 to 3 squares (28, 29, 30 or 31
    // days over seven columns), so the name fits beside the last row whenever
    // there is a tail at all.
    final tail = month.days % _columns;

    final rows = <Widget>[];
    for (var start = 1; start <= month.days; start += _columns) {
      final end = math.min(start + _columns - 1, month.days);
      final isLastRow = end == month.days;

      rows.add(Padding(
        padding: EdgeInsets.only(top: start == 1 ? 0 : _gap),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var day = start; day <= end; day++) ...[
              if (day != start) const SizedBox(width: _gap),
              _DaySquare(
                day: day,
                monthLabel: monthName(month.month),
                minutes: month.minutesOn(day),
                color: studyDayColor(
                  minutes: month.minutesOn(day),
                  busiestMinutes: month.busiestDayMinutes,
                  isFuture: _isFuture(day),
                  palette: palette,
                ),
              ),
            ],
            if (isLastRow && tail > 0) ...[
              const SizedBox(width: 12),
              label,
            ],
          ],
        ),
      ));
    }

    var logged = 0;
    for (final minutes in month.minutesByDay) {
      if (minutes > 0) logged++;
    }

    return Semantics(
      label: '${monthName(month.month)}: $logged of ${month.days} days studied',
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ...rows,
          // February in a common year fills every row exactly, leaving the
          // name nowhere to sit beside the grid.
          if (tail == 0) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: _columns * _square + (_columns - 1) * _gap,
              child: Align(alignment: Alignment.centerRight, child: label),
            ),
          ],
        ],
      ),
    );
  }
}

class _DaySquare extends StatelessWidget {
  const _DaySquare({
    required this.day,
    required this.monthLabel,
    required this.minutes,
    required this.color,
  });

  final int day;
  final String monthLabel;
  final int minutes;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: minutes > 0
          ? '$day $monthLabel · ${formatStudyMinutes(minutes)}'
          : '$day $monthLabel · nothing logged',
      child: Container(
        width: _square,
        height: _square,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}
