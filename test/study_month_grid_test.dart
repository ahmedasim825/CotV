// The month grid: one square a day, seven to a row, shaded against the
// month's own busiest day.
//
// The layout rule is the thing worth pinning — how many squares a month gets
// and how they break into rows is the part a reader checks by counting, and
// the part that quietly goes wrong in February. It is asserted off rendered
// geometry (squares sharing a `dy` are on a row) rather than off the widget
// tree, so it keeps holding if the rows are ever built some other way.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cotv/src/models/study_view.dart';
import 'package:cotv/src/ui/study/widgets/study_month_grid.dart';
import 'package:cotv/src/ui/theme/app_theme.dart';

MonthStudy _month({
  required int year,
  required int month,
  required int days,
  Map<int, int> minutes = const {},
}) {
  final byDay = List<int>.filled(days, 0);
  minutes.forEach((day, value) => byDay[day - 1] = value);

  var busiest = 0;
  for (final value in byDay) {
    if (value > busiest) busiest = value;
  }

  return MonthStudy(
    year: year,
    month: month,
    minutesByDay: List.unmodifiable(byDay),
    busiestDayMinutes: busiest,
  );
}

/// September 2026: 30 days, with today the 12th.
final _september = _month(year: 2026, month: 9, days: 30);
final _today = DateTime(2026, 9, 12);

String _tip(int day, String month, [int minutes = 0]) => minutes > 0
    ? '$day $month · ${formatStudyMinutes(minutes)}'
    : '$day $month · nothing logged';

Future<void> _pump(
  WidgetTester tester,
  MonthStudy month,
  DateTime today,
) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: Center(child: StudyMonthGridView(month: month, today: today)),
    ),
  ));
  await tester.pump();
}

/// How many squares sit on each row, top row first.
List<int> _rowLengths(WidgetTester tester, MonthStudy month, String name) {
  final byRow = <double, int>{};
  for (var day = 1; day <= month.days; day++) {
    final dy = tester.getCenter(find.byTooltip(_tip(day, name))).dy;
    byRow[dy] = (byRow[dy] ?? 0) + 1;
  }
  final tops = byRow.keys.toList()..sort();
  return [for (final top in tops) byRow[top]!];
}

Color _squareColor(WidgetTester tester, String tooltip) {
  final container = tester.widget<Container>(find.descendant(
    of: find.byTooltip(tooltip),
    matching: find.byType(Container),
  ));
  return (container.decoration! as BoxDecoration).color!;
}

void main() {
  group('layout', () {
    testWidgets('a 30-day month is 7+7+7+7+2', (tester) async {
      await _pump(tester, _september, _today);

      expect(find.byType(Tooltip), findsNWidgets(30));
      expect(_rowLengths(tester, _september, 'September'), [7, 7, 7, 7, 2]);
    });

    testWidgets('a 31-day month is 7+7+7+7+3', (tester) async {
      final october = _month(year: 2026, month: 10, days: 31);
      await _pump(tester, october, DateTime(2026, 10, 5));

      expect(find.byType(Tooltip), findsNWidgets(31));
      expect(_rowLengths(tester, october, 'October'), [7, 7, 7, 7, 3]);
    });

    testWidgets('a 28-day month fills four rows exactly', (tester) async {
      final february = _month(year: 2027, month: 2, days: 28);
      await _pump(tester, february, DateTime(2027, 2, 10));

      expect(find.byType(Tooltip), findsNWidgets(28));
      expect(_rowLengths(tester, february, 'February'), [7, 7, 7, 7]);
    });

    testWidgets('a leap February gets its extra square', (tester) async {
      final february = _month(year: 2028, month: 2, days: 29);
      await _pump(tester, february, DateTime(2028, 2, 10));

      expect(_rowLengths(tester, february, 'February'), [7, 7, 7, 7, 1]);
    });

    testWidgets('the month names itself', (tester) async {
      await _pump(tester, _september, _today);

      expect(find.text('September'), findsOneWidget);
    });

    testWidgets('a month with no tail still names itself', (tester) async {
      // 28 days fills every row, so the label has no gap to sit in beside the
      // grid and drops to its own line instead.
      final february = _month(year: 2027, month: 2, days: 28);
      await _pump(tester, february, DateTime(2027, 2, 10));

      expect(find.text('February'), findsOneWidget);
      final lastSquare = tester.getCenter(find.byTooltip(_tip(28, 'February')));
      expect(tester.getCenter(find.text('February')).dy,
          greaterThan(lastSquare.dy));
    });
  });

  group('shading', () {
    testWidgets('the busiest day is the deep end of the ramp', (tester) async {
      final month = _month(
        year: 2026,
        month: 9,
        days: 30,
        minutes: {1: 30, 7: 200, 9: 120},
      );
      await _pump(tester, month, _today);

      expect(_squareColor(tester, _tip(7, 'September', 200)), studyHeatBusy);
    });

    testWidgets('a lighter day sits partway along the ramp', (tester) async {
      final month =
          _month(year: 2026, month: 9, days: 30, minutes: {1: 30, 7: 200});
      await _pump(tester, month, _today);

      expect(
        _squareColor(tester, _tip(1, 'September', 30)),
        Color.lerp(studyHeatQuiet, studyHeatBusy, 30 / 200),
      );
    });

    testWidgets('a day still to come is fainter than one already missed',
        (tester) async {
      await _pump(tester, _september, _today);

      final missed = _squareColor(tester, _tip(5, 'September'));
      final toCome = _squareColor(tester, _tip(20, 'September'));

      expect(missed, kPalette.textPrimary.withValues(alpha: 0.10));
      expect(toCome, kPalette.textPrimary.withValues(alpha: 0.04));
    });

    testWidgets('today itself is not treated as the future', (tester) async {
      await _pump(tester, _september, _today);

      expect(_squareColor(tester, _tip(12, 'September')),
          kPalette.textPrimary.withValues(alpha: 0.10));
    });

    testWidgets('a month that is not this one has no future days',
        (tester) async {
      // Looking at October while it is September: nothing in it has happened,
      // but the grid is not the current month, so nothing is dimmed for it.
      final october = _month(year: 2026, month: 10, days: 31);
      await _pump(tester, october, _today);

      expect(_squareColor(tester, _tip(31, 'October')),
          kPalette.textPrimary.withValues(alpha: 0.10));
    });
  });

  group('studyDayColor', () {
    test('a lone logged day is its own maximum, so it paints the deep end',
        () {
      expect(
        studyDayColor(
          minutes: 45,
          busiestMinutes: 45,
          isFuture: false,
          palette: kPalette,
        ),
        studyHeatBusy,
      );
    });

    test('a day with nothing on it is off the ramp entirely', () {
      final empty = studyDayColor(
        minutes: 0,
        busiestMinutes: 200,
        isFuture: false,
        palette: kPalette,
      );

      expect(empty, isNot(studyHeatQuiet));
      expect(empty, kPalette.textPrimary.withValues(alpha: 0.10));
    });

    test('more minutes than the month best clamps rather than overshooting',
        () {
      expect(
        studyDayColor(
          minutes: 500,
          busiestMinutes: 200,
          isFuture: false,
          palette: kPalette,
        ),
        studyHeatBusy,
      );
    });
  });
}
